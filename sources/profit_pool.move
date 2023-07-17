#[allow(unused_use)]
module games::profits_pool {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use games::drand_based_lottery::{Self, Game};
    use games::locked_coin::{Self, LockedCoin};

    use std::debug;

    /// Not enough funds to pay for the good in question
    const EInsufficientFunds: u64 = 0;
    /// Nothing to withdraw
    const ENoProfits: u64 = 1;

    struct Pool has key, store {
        id : UID,
        balance : balance::Balance<SUI>,
        epoch : u64,
        digest : vector<u8>,
        supply : u64,
    }

    #[allow(unused_function)]
    fun init(ctx: &mut TxContext) {
        let txEpoch = tx_context::epoch(ctx);
        let txDigest = *tx_context::digest(ctx);
        let pool = Pool{
            id: object::new(ctx),
            balance: balance::zero<SUI>(), 
            epoch : txEpoch,
            digest : txDigest,
            supply : 0,
        };
        transfer::public_share_object(pool);
    }

    public fun pool_update (pool: &mut Pool, ctx: &mut TxContext){
        pool.epoch = tx_context::epoch(ctx);
        pool.digest = *tx_context::digest(ctx);
    }

    public fun deposit (pool: &mut Pool, coin: Coin<SUI>){
        let coinb = coin::into_balance(coin);
        assert!(balance::value(&coinb) >= 0, ENoProfits);
        balance::join(&mut pool.balance, coinb);
    }

    public entry fun lock_coin_for_staking (pool: &mut Pool, coin: Coin<SUI>, amount : u64, ctx : &mut TxContext) {
        let balance = coin::value(&coin);
        assert!(balance >= amount, EInsufficientFunds);
        pool.supply = pool.supply + balance;
        debug::print(&tx_context::sender(ctx));
        let send_to_lock_coin =coin::split(&mut coin, balance, ctx);
        locked_coin::lock_coin(send_to_lock_coin, tx_context::sender(ctx), tx_context::epoch(ctx) + 1,  ctx);
        transfer::public_transfer(coin, tx_context::sender(ctx));
    }

    public entry fun unlock_coin_from_staked (pool: &mut Pool, lock_coin: LockedCoin<SUI>, ctx: &mut TxContext) {
        let balance = locked_coin::value(&lock_coin);
        assert!(balance <= pool.supply, EInsufficientFunds);
        pool.supply= pool.supply - balance;
        locked_coin::unlock_coin(lock_coin, ctx);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    #[test_only]
    public fun deposit_from_game(pool:&mut Pool, value: u64) {
        let test_balance = balance::create_for_testing<SUI>(value);
        balance::join(&mut pool.balance, test_balance);
    }

    #[allow(unused_assignment)]
    #[test]
    fun test_pool_epoch() {
        use sui::test_scenario;
        use std::debug;
        use sui::clock;
        use sui::sui::SUI;

        let user1 = @0x0;
        let user2 = @0x1;
        let user3 = @0x2;
        let user4 = @0x3;

        let scenario_val = test_scenario::begin(user1);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(test_scenario::ctx(scenario));
        clock::increment_for_testing( &mut clock, 42);
        test_scenario::next_tx(scenario, user1);
        init_for_testing(test_scenario::ctx(scenario));
        
        //
        test_scenario::next_tx(scenario, user2);
        let pool = test_scenario::take_shared<Pool>(scenario);

        //
        debug::print(&pool.epoch);
        debug::print(&pool.digest);
        //
        test_scenario::next_epoch(scenario, user1);
        pool_update(&mut pool,test_scenario::ctx(scenario));
        debug::print(&pool.epoch);
        debug::print(&pool.digest);
        
        //
        test_scenario::next_tx(scenario, user1);
        //lock_coin_for_staking(&mut pool,coin::mint_for_testing<SUI>(10, test_scenario::ctx(scenario)),10, test_scenario::ctx(scenario));
        lock_coin_for_staking(&mut pool,coin::mint_for_testing<SUI>(10, test_scenario::ctx(scenario)),10, test_scenario::ctx(scenario));
        debug::print(&pool.supply);

        //
        test_scenario::next_epoch(scenario, user1);
        test_scenario::next_tx(scenario, user1);
        //locked_coin::unlock_coin(test_scenario::take_from_address<LockedCoin<SUI>>(scenario, user1), test_scenario::ctx(scenario));
        unlock_coin_from_staked(&mut pool, test_scenario::take_from_address<LockedCoin<SUI>>(scenario, user1), test_scenario::ctx(scenario));
        debug::print(&pool.supply);


        //
        test_scenario::return_shared(pool);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario_val);
    }
}