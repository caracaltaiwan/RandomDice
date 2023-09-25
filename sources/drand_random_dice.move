// Copyright (coin) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[allow(unused_use)]
module games::drand_random_dice {

    use games::hongwang_coin::HONGWANG_COIN;
    use games::drand_lib as dl;
    use games::profits_pool::{Self, Pool};
    use games::locked_coin::{Self, LockedCoin};
    use sui::sui::SUI;
    use sui::object::{Self, ID, UID}; 
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::clock::{Self, Clock};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::table::{Self, Table};
    use sui::dynamic_object_field as dof;
    use std::option::{Self, Option};
    use std::debug;

    // ------------ Errors ------------

    const EGameNotInProgress: u64 = 0;
    const EGameAlreadyCompleted: u64 = 1;
    const EInvalidRandomness: u64 = 2;
    const EInvalidTicket: u64 = 3;

    // ------------ Constants ------------
    
    /// Not enough funds to pay for the good in question
    const EInsufficientFunds: u64 = 4;
    /// Nothing to withdraw
    const ENoProfits: u64 = 5;

    /// Game Status
    const IN_PROGRESS: u8 = 0;
    const CLOSED: u8 = 1;
    const COMPLETED: u8 = 2;
    const PREPARATION: u8 = 3;

    /// Game Participant Capability Type
    const Gold:   u8 = 0;
    const Silver: u8 = 1;
    const Copper: u8 = 2;

    // ------------ Objects ------------

    /// Game represents a set of parameters of a single game.
    /// This game can be extended to require ticket purchase, reward winners, etc.
    struct Game<phantom T> has key, store {
        id: UID,
        addition_round: u64,
        round: u64,
        status: u8,
        participants: u64,
        winner: Option<u64>,
        pool: Pool<T>,
    }

    /// Ticket represents a participant in a single game.
    /// Can be deconstructed only by the owner.
    struct Ticket has key, store {
        id: UID,
        game_id: ID,
        round: u64,
        price: u64,
        participant_index: u64,
    }

    // This Capability allows the owner to withdraw profits
    struct GameOwnerCapability has key {
        id: UID
    }

    struct OneTimeTicket has key, store {
        id: UID,
        ticket: Cap_Ticket,
    }

    struct Cap_Ticket has store, drop {
        game_id: ID,
        at_least_token: u64,
    }

    // This Capability allows the Participant to start new round.
    struct GameParticipantCapability has key, store {
        id: UID,
        game_id: ID,
        token: Table<ID, LockedCoin<HONGWANG_COIN>>,
    }

    // ------------ Witness ------------
    
    struct DRAND_RANDOM_DICE has drop {}

    // ------------ Constructor ------------
    
    fun init(_otw: DRAND_RANDOM_DICE, ctx: &mut sui::tx_context::TxContext) {
        std::debug::print(&std::string::utf8(b"init"));
        let game_owner_cap = GameOwnerCapability{
            id:object::new(ctx)
        };

        transfer::transfer(
            game_owner_cap,
            tx_context::sender(ctx)
        );
    }

    // ------------ Owner Capability Operation ------------
    
    public entry fun create_game_ott_capability<T> (_cap: &GameOwnerCapability, game: &mut Game<T>, invite_level: u8, ctx: &mut TxContext) {
        let amount = 100;
        if ( invite_level == Gold ) { amount = 0 }
        else if ( invite_level == Silver ) { amount = 10 }
        else if ( invite_level == Copper ) { amount = 40 };

        let id = *object::uid_as_inner(&game.id);

        let cap_ticket = Cap_Ticket {
            game_id: id,
            at_least_token: amount,
        };

        transfer::transfer(
            OneTimeTicket {
                id: object::new(ctx),
                ticket: cap_ticket,
            },
        tx_context::sender(ctx)
        );
    }

    // ------------ Participant Capability Operation ------------
    
    public entry fun create_game_articipant_capability<T> (
        cap: OneTimeTicket, game: &mut Game<T>, hw_coin: Coin<HONGWANG_COIN>, ctx: &mut TxContext
    ){
        let (game_id, amount) = unpack_one_time_ticket(cap);    
        assert!(game_id == object::uid_to_inner(&game.id),ENoProfits);
        assert!(coin::value(&hw_coin) >= amount, EGameNotInProgress);
        let lock_epoch = tx_context::epoch(ctx);
        let lockcoin = locked_coin::lock_coin_for_cap(hw_coin, lock_epoch, ctx);
        let hw_coin_table = table::new(ctx);
        table::add<ID, LockedCoin<HONGWANG_COIN>>(&mut hw_coin_table, object::id(&lockcoin), lockcoin);
        
        transfer::transfer(
            GameParticipantCapability {
                id: object::new(ctx),
                game_id: object::uid_to_inner(&game.id),
                token: hw_coin_table,
            }, 
        tx_context::sender(ctx)
        );
    }

    public fun unpack_one_time_ticket (
        ott: OneTimeTicket
    ): (ID, u64){
        let OneTimeTicket {
            id,
            ticket,
        } = ott;
        object::delete(id);
        (ticket.game_id, ticket.at_least_token)
    }

    // ------------ Owner Operation ------------

    public entry fun create_after_round<T> (_cap: &GameOwnerCapability, pool: Pool<T>, clock: &Clock, round: u64, ctx: &mut TxContext) {
        debug::print(ctx);
        debug::print(&tx_context::epoch_timestamp_ms(ctx));
        let current_round = round + dl::get_lateset_round(ctx);
        debug::print(&dl::get_lateset_round(ctx));
        debug::print(&current_round);
        let game = Game {
            id: object::new(ctx),
            addition_round: round,
            round: current_round,
            status: IN_PROGRESS,
            participants: 0,
            winner: option::none(),
            pool: pool,
        };
        transfer::public_share_object(game);
    }

    public entry fun set_round<T> (_cap: &GameOwnerCapability, game: &mut Game<T>, round: u64){
        game.addition_round = round;
    }

    public entry fun start_game_by_owner<T> (_cap: &GameOwnerCapability, game:&mut Game<T>, ctx: &mut TxContext) {
        assert!(game.status == COMPLETED, EGameNotInProgress);
        game.round = game.addition_round + dl::get_lateset_round(ctx);
        game.status = IN_PROGRESS;
    }

    // ------------ Participant Operation ------------
    
    public entry fun start_game_by_participant<T> (_cap: &GameParticipantCapability, game:&mut Game<T>, ctx: &mut TxContext) {
        assert!(game.status == PREPARATION, EGameNotInProgress);
        game.round = game.addition_round + dl::get_lateset_round(ctx);
        game.status = IN_PROGRESS;
    }

    // ------------ Game Cycle Operation ------------
    
    /// Anyone can close the game by providing the randomness of round-2.
    public entry fun close<T> (game: &mut Game<T>, drand_sig: vector<u8>, drand_prev_sig: vector<u8>) {
        assert!(game.status == IN_PROGRESS, EGameNotInProgress);
        dl::verify_drand_signature(drand_sig, drand_prev_sig, closing_round(game.round));
        game.status = CLOSED;
    } 

    /// Anyone can complete the game by providing the randomness of round.
    public entry fun complete<T> (game: &mut Game<T>, drand_sig: vector<u8>, drand_prev_sig: vector<u8>) {
        assert!(game.status != COMPLETED, EGameAlreadyCompleted);
        dl::verify_drand_signature(drand_sig, drand_prev_sig, game.round);
        game.status = COMPLETED;
        // The randomness is derived from drand_sig by passing it through sha2_256 to make it uniform.
        let digest = dl::derive_randomness(drand_sig);
        game.winner = option::some(dl::safe_selection(game.participants, &digest));
    }

    /// Anyone can play random dice in the game and receive a ticket.
    public entry fun play_random_dice<T> (game: &mut Game<T>, coin: Coin<T>, ctx: &mut TxContext) {
        assert!(game.status == IN_PROGRESS, EGameNotInProgress);
        assert!(coin::value(&coin) >= 1, EInsufficientFunds);

        let b = coin::into_balance(coin);
        let price = balance::value(&b);
        let number = game.participants % 5;
        let ticket = Ticket {
            id: object::new(ctx),
            game_id: object::id(game),
            round: game.round,
            price: price,
            participant_index: number,
        };
        game.participants = game.participants + 1;

        balance::join(profits_pool::pool_reward(game_pool(game)), b);
        transfer::public_transfer(ticket, tx_context::sender(ctx));
    }

    public entry fun redeem<T> (game: &mut Game<T>, ticket: &Ticket, ctx: &mut TxContext) {
        assert!(game.status == COMPLETED, EGameNotInProgress);
        assert!(object::id(game) == ticket.game_id, EInvalidTicket);
        let amount = ticket.price * 6;
        let redeem = coin::take(profits_pool::pool_reward(game_pool(game)),amount, ctx);

        transfer::public_transfer(redeem, tx_context::sender(ctx));
    }

    // Note that a ticket can be deleted before the game was completed.
    public entry fun delete_ticket(ticket: Ticket) {
        let Ticket { id, game_id:  _, round: _, price: _, participant_index: _} = ticket;
        object::delete(id);
    }

    // ------------ General Operation ------------

    public fun get_ticket_game_id(ticket: &Ticket): ID {
        ticket.game_id
    }

    fun closing_round(round: u64): u64 {
        round - 2
    }

    public fun game_pool<T> (game:&mut Game<T>): &mut Pool<T> {
        &mut game.pool
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(DRAND_RANDOM_DICE{}, ctx);
    }

}
