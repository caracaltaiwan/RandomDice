// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module games::locked_coin {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use games::epoch_time_lock::{Self, EpochTimeLock};

    use std::debug;

    friend games::profits_pool;
    friend games::drand_random_dice;

    /// A coin of type `T` locked until `locked_until_epoch`.
    struct LockedCoin<phantom T> has key, store {
        id: UID,
        balance: Balance<T>,
        locked_until_epoch: EpochTimeLock
    }

    /// Create a LockedCoin from `balance` and transfer it to `owner`.
    public(friend) fun new_from_balance<T>(
        balance: Balance<T>, 
        locked_until_epoch: EpochTimeLock, 
        owner: address, 
        ctx: &mut TxContext
    ) {
        let locked_coin = LockedCoin {
            id: object::new(ctx),
            balance,
            locked_until_epoch
        };
        debug::print(&owner);
        debug::print(&locked_coin.id);
        transfer::transfer(locked_coin, owner);
    }

    /// Public getter for the locked coin's value
    public fun value<T>(self: &LockedCoin<T>): u64 {
        balance::value(&self.balance)
    }

    /// Lock a coin up until `locked_until_epoch`. The input Coin<T> is deleted and a LockedCoin<T>
    /// is transferred to the `recipient`. This function aborts if the `locked_until_epoch` is less than
    /// or equal to the current epoch.
    public(friend) entry fun lock_coin<T>(
        coin: Coin<T>, 
        recipient: address, 
        locked_until_epoch: u64, 
        ctx: &mut TxContext
    ) {
        let balance = coin::into_balance(coin);
        new_from_balance(balance, epoch_time_lock::new(locked_until_epoch, ctx), recipient, ctx);
    }

    /// Unlock a locked coin. The function aborts if the current epoch is less than the `locked_until_epoch`
    /// of the coin. If the check is successful, the locked coin is deleted and a Coin<T> is transferred back
    /// to the sender.
    public entry fun unlock_coin<T>(
        locked_coin: LockedCoin<T>, 
        ctx: &mut TxContext
    ) {
        let LockedCoin { id, balance, locked_until_epoch } = locked_coin;
        object::delete(id);
        epoch_time_lock::destroy(locked_until_epoch, ctx);
        let coin = coin::from_balance(balance, ctx);
        transfer::public_transfer(coin, tx_context::sender(ctx));
    }

    /// Create a LockedCoin from `balance` and transfer it to `owner`.
    public(friend) fun new_from_balance_for_cap<T>(
        balance: Balance<T>, 
        locked_until_epoch: EpochTimeLock,
        ctx: &mut TxContext
    ): LockedCoin<T> {
        LockedCoin {
            id: object::new(ctx),
            balance,
            locked_until_epoch
        }
    }

    /// Lock a coin up until `locked_until_epoch`. The input Coin<T> is deleted and a LockedCoin<T>
    /// is transferred to the `recipient`. This function aborts if the `locked_until_epoch` is less than
    /// or equal to the current epoch.
    public(friend) fun lock_coin_for_cap<T>(
        coin: Coin<T>, 
        locked_until_epoch: u64, 
        ctx: &mut TxContext
    ): LockedCoin<T> {
        let balance = coin::into_balance(coin);
        new_from_balance_for_cap(balance, epoch_time_lock::new(locked_until_epoch, ctx), ctx)
    }

    /// Unlock a locked coin. The function aborts if the current epoch is less than the `locked_until_epoch`
    /// of the coin. If the check is successful, the locked coin is deleted and a Coin<T> is transferred back
    /// to the sender.
    public entry fun unlock_coin_for_cap<T>(
        locked_coin: LockedCoin<T>, 
        ctx: &mut TxContext
    ) {
        let LockedCoin { id, balance, locked_until_epoch } = locked_coin;
        object::delete(id);
        epoch_time_lock::destroy(locked_until_epoch, ctx);
        let coin = coin::from_balance(balance, ctx);
        transfer::public_transfer(coin, tx_context::sender(ctx));
    }

    #[allow(unused_assignment)]
    #[test]
    fun test_lock_coin(){
        use sui::test_scenario;
        use std::debug;
        use sui::sui::SUI;
        use sui::tx_context;

        //Genensis block
        let user1 = @0x0;
        let user2 = @0x1;
        let scenario_val = test_scenario::begin(user1);
        let scenario = &mut scenario_val;
        let ctx = tx_context::dummy();

        //Init block
        test_scenario::next_tx(scenario, user1);
        let coinA = coin::mint_for_testing<SUI>(300, test_scenario::ctx(scenario));
        debug::print(&coinA);
        transfer::public_transfer(coinA, user1);
        
        //
        test_scenario::next_tx(scenario, user1);
        let coinOut = test_scenario::take_from_address<Coin<SUI>>(scenario, user1);
        lock_coin(coinOut, user1, 1, test_scenario::ctx(scenario));

        //
        test_scenario::next_epoch(scenario, user1);
        test_scenario::next_tx(scenario, user1);
        let lockCoin = test_scenario::take_from_address<LockedCoin<SUI>>(scenario, user1);
        unlock_coin(lockCoin, test_scenario::ctx(scenario));

        //
        test_scenario::end(scenario_val);
    }
}
