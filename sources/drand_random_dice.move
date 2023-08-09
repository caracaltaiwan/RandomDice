// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[allow(unused_use)]
/// A basic game that depends on randomness from drand (chained mode).
///
/// The main chain of drand creates random 32 bytes every 30 seconds. This randomness is verifiable in the sense
/// that anyone can check if a given 32 bytes bytes are indeed the i-th output of drand. For more details see
/// https://drand.love/
///
/// One could implement on-chain games that need unbiasable and unpredictable randomness using drand as the source of
/// randomness. I.e., every time the game needs randomness, it receives the next 32 bytes from drand (whether as part
/// of a transaction or by reading it from an existing object) and follows accordingly.
/// However, this simplistic flow may be insecure in some cases because the blockchain is not aware of the latest round
/// of drand, and thus it may depend on randomness that is already public.
///
/// Below we design a game that overcomes this issue as following:
/// - The game is defined for a specific drand round N in the future, for example, the round that is expected in
///   5 mins from now.
///   The current round for the main chain can be retrieved (off-chain) using
///   `curl https://drand.cloudflare.com/8990e7a9aaed2ffed73dbd7092123d6f289930540d7651336225dc172e51b2ce/public/latest',
///   or using the following python script:
///      import time
///      genesis = 1595431050
///      curr_round = (time.time() - genesis) // 30 + 1
///   The round in 5 mins from now will be curr_round + 5*2.
///   (genesis is the epoch of the first round as returned from
///   curl https://drand.cloudflare.com/8990e7a9aaed2ffed73dbd7092123d6f289930540d7651336225dc172e51b2ce/info.)
/// - Anyone can *close* the game to new participants by providing drand's randomness of round N-2 (i.e., 1 minute before
///   round N). The randomness of round X can be retrieved using
///  `curl https://drand.cloudflare.com/8990e7a9aaed2ffed73dbd7092123d6f289930540d7651336225dc172e51b2ce/public/X'.
/// - Users can join the game as long as it is not closed and receive a *ticket*.
/// - Anyone can *complete* the game by proving drand's randomness of round N, which is used to declare the winner.
/// - The owner of the winning "ticket" can request a "winner ticket" and finish the game.
/// As long as someone is closing the game in time (or at least before round N) we have the guarantee that the winner is
/// selected using unpredictable and unbiasable randomness. Otherwise, someone could wait until the randomness of round N
/// is public, see if it could win the game and if so, join the game and drive it to completion. Therefore, honest users
/// are encourged to close the game in time.
///
/// All the external inputs needed for the following APIs can be retrieved from one of drand's public APIs, e.g. using
/// the above curl commands.
///
module games::drand_random_dice {
    use games::drand_lib::{derive_randomness, verify_drand_signature, safe_selection, get_lateset_round};
    use games::hongwang_coin::HONGWANG_COIN;
    use games::profits_pool::{Self, Pool};
    use std::option::{Self, Option};
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::clock::{Self, Clock};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;

    use std::debug;

    /// Error codes
    const EGameNotInProgress: u64 = 0;
    const EGameAlreadyCompleted: u64 = 1;
    const EInvalidRandomness: u64 = 2;
    const EInvalidTicket: u64 = 3;
    
    /// Not enough funds to pay for the good in question
    const EInsufficientFunds: u64 = 4;
    /// Nothing to withdraw
    const ENoProfits: u64 = 5;

    /// Game status
    const IN_PROGRESS: u8 = 0;
    const CLOSED: u8 = 1;
    const COMPLETED: u8 = 2;

    struct DRAND_RANDOM_DICE has drop {}

    /// Game represents a set of parameters of a single game.
    /// This game can be extended to require ticket purchase, reward winners, etc.
    ///
    struct Game has key, store {
        id: UID,
        round: u64,
        status: u8,
        participants: u64,
        winner: Option<u64>,
    }

    /// Ticket represents a participant in a single game.
    /// Can be deconstructed only by the owner.
    struct Ticket has key, store {
        id: UID,
        game_id: ID,
        price: u64,
        participant_index: u64,
    }

    /// GameWinner represents a participant that won in a specific game.
    /// Can be deconstructed only by the owner.
    struct GameWinner has key, store {
        id: UID,
        game_id: ID,
        redeem: u64,
    }

    // This Capability allows the owner to withdraw profits
    struct GameOwnerCapability has key {
        id: UID
    }
    
    fun init(otw: DRAND_RANDOM_DICE, ctx: &mut sui::tx_context::TxContext) {
        let game_owner_cap = GameOwnerCapability{
            id:object::new(ctx)
        };
        transfer::transfer(
            game_owner_cap,
            tx_context::sender(ctx)
        );
    }

    /// Create a assign epoch shared-object Game.
    /*
    public entry fun create(round: u64, ctx: &mut TxContext) {
        let game = Game {
            id: object::new(ctx),
            round,
            status: IN_PROGRESS,
            participants: 0,
            winner: option::none(),
            profits: balance::zero<SUI>(),
        };
        debug::print(&round);
        transfer::public_share_object(game);
    }*/

    /// === Owner Operation ===
    public entry fun create_after_round(clock: &Clock, round: u64, ctx: &mut TxContext) {
        let clock_ms = clock::timestamp_ms(clock);
        round = round + get_lateset_round(clock_ms);
        let game = Game {
            id: object::new(ctx),
            round,
            status: IN_PROGRESS,
            participants: 0,
            winner: option::none(),
        };
        transfer::public_share_object(game);
    }

    /// Anyone can close the game by providing the randomness of round-2.
    public entry fun close(game: &mut Game, drand_sig: vector<u8>, drand_prev_sig: vector<u8>) {
        assert!(game.status == IN_PROGRESS, EGameNotInProgress);
        verify_drand_signature(drand_sig, drand_prev_sig, closing_round(game.round));
        game.status = CLOSED;
    }

    /// === Creator/User Operation ===

    /// Anyone can complete the game by providing the randomness of round.
    public entry fun complete(game: &mut Game, drand_sig: vector<u8>, drand_prev_sig: vector<u8>) {
        assert!(game.status != COMPLETED, EGameAlreadyCompleted);
        verify_drand_signature(drand_sig, drand_prev_sig, game.round);
        game.status = COMPLETED;
        // The randomness is derived from drand_sig by passing it through sha2_256 to make it uniform.
        let digest = derive_randomness(drand_sig);
        game.winner = option::some(safe_selection(game.participants, &digest));
    }

    /// Anyone can participate in the game and receive a ticket.
    public entry fun participate(pool: &mut Pool, game: &mut Game, c: Coin<SUI>, ctx: &mut TxContext) {
        assert!(game.status == IN_PROGRESS, EGameNotInProgress);
        let b = coin::into_balance(c);
        let price = balance::value(&b) * 9 / 10;
        let number = game.participants % 5;
        let ticket = Ticket {
            id: object::new(ctx),
            game_id: object::id(game),
            price: price,
            participant_index: number,
        };
        game.participants = game.participants + 1;

        //how many coin in this tx supply.
        balance::join(profits_pool::pool_reward(pool), b);
        transfer::public_transfer(ticket, tx_context::sender(ctx));
    }

    /// The winner can redeem its ticket.
    public entry fun redeem(pool: &mut Pool, game: &mut Game, ticket: &Ticket, ctx: &mut TxContext) {
        assert!(object::id(game) == ticket.game_id, EInvalidTicket);
        let amount = ticket.price;
        let redeem = coin::take(profits_pool::pool_reward(pool),amount, ctx);

        transfer::public_transfer(redeem, tx_context::sender(ctx));
    }

    // Note that a ticket can be deleted before the game was completed.
    public entry fun delete_ticket(ticket: Ticket) {
        let Ticket { id, game_id:  _, price: _, participant_index: _} = ticket;
        object::delete(id);
    }

    public fun get_ticket_game_id(ticket: &Ticket): &ID {
        &ticket.game_id
    }

    public fun get_game_winner_game_id(ticket: &GameWinner): &ID {
        &ticket.game_id
    }

    fun closing_round(round: u64): u64 {
        round - 2
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(DRAND_RANDOM_DICE{}, ctx);
    }
}
