#[allow(unused_use)]
module games::profits_pool {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use games::drand_based_lottery::{Self, Game};
    use games::locked_coin;

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

    /*public fun lock_coin_for_staking (pool: Pool, coin: Coin<SUI>, amount : u64, ctx : &mut TxContext) {
        let b = coin::into_balance(coin);
        assert!(balance::value(&b) >= amount, EInsufficientFunds);
        let lockCoin = locked_coin::lock_coin(coin, tx_context::sender(ctx), 1,  ctx);
        transfer::transfer(lockCoin, tx_context::sender(ctx));
    }*/

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
        use sui::test_scenario::{Self};
        use std::debug;
        use sui::clock;

        let user1 = @0x0;
        let user2 = @0x1;
        let user3 = @0x2;
        let user4 = @0x3;

        let scenario_val = test_scenario::begin(user1);
        let scenario = &mut scenario_val;
        let ctx = tx_context::dummy();
        let clock = clock::create_for_testing(&mut ctx);
        clock::increment_for_testing( &mut clock, 42);
        test_scenario::next_tx(scenario, user1);
        init_for_testing(&mut ctx);
        
        test_scenario::next_tx(scenario, user2);
        let pool = test_scenario::take_shared<Pool>(scenario);
        //debug::print(&pool.epoch);
        //debug::print(&pool.digest);
        pool_update(&mut pool,&mut ctx);
        //debug::print(&pool.epoch);
        //debug::print(&pool.digest);

        test_scenario::return_shared(pool);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario_val);
    }
}