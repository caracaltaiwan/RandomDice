#[allow(unused_use)]
module games::profits_pool {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin, TreasuryCap};
    use games::hongwang_coin::HONGWANG_COIN;
    use games::locked_coin::{Self, LockedCoin};

    use std::debug;

    /// Not enough funds to pay for the good in question
    const EInsufficientFunds: u64 = 0;
    /// Nothing to withdraw
    const ENoProfits: u64 = 1;

    /// One time witness
    struct PROFITS_POOL has drop {}

    struct Pool has key, store {
        id : UID,
        reward_pool : balance::Balance<SUI>,
        epoch : u64,
        digest : vector<u8>,
        governanceToken : balance::Balance<HONGWANG_COIN>,
        token_supply: u64,
    }
    struct HW_CAP has key {
        id: UID,
    }

    #[allow(unused_function)]
    /// === Initial Profit Pool ===
    fun init(witness: PROFITS_POOL, ctx: &mut TxContext) {
        let hw_cap = HW_CAP{id: object::new(ctx)};
        transfer::transfer(hw_cap, tx_context::sender(ctx));

        let txEpoch = tx_context::epoch(ctx);
        let txDigest = *tx_context::digest(ctx);
        let pool = Pool{
            id: object::new(ctx),
            reward_pool: balance::zero<SUI>(), 
            epoch : txEpoch,
            digest : txDigest,
            governanceToken : balance::zero<HONGWANG_COIN>(),
            token_supply: 10000,
        };
        transfer::public_share_object(pool);
    }
    
    /// === Creator/Owner Operation ===
    public fun pool_update (pool: &mut Pool, ctx: &mut TxContext){
        pool.epoch = tx_context::epoch(ctx);
        pool.digest = *tx_context::digest(ctx);
    }

    public entry fun mint_hw_coin (cap: &mut TreasuryCap<HONGWANG_COIN>, amount: u64, ctx: &mut TxContext) {
        let coin = coin::mint(cap, amount, ctx);
        transfer::public_transfer(coin, tx_context::sender(ctx));
    }

    public fun deposit (pool: &mut Pool, coin: Coin<SUI>){
        let coinb = coin::into_balance(coin);
        assert!(balance::value(&coinb) >= 0, ENoProfits);
        balance::join(&mut pool.reward_pool, coinb);
    }

    /// === General Token Hodler ===
    public entry fun lock_coin_for_staking (pool: &mut Pool, coin: Coin<HONGWANG_COIN>, amount : u64, ctx : &mut TxContext) {
        let balance = coin::value(&coin);
        assert!(balance >= amount, EInsufficientFunds);
        let send_to_lock_coin = coin::split(&mut coin, amount, ctx);
        debug::print(&coin);
        debug::print(&send_to_lock_coin);
        locked_coin::lock_coin(send_to_lock_coin, tx_context::sender(ctx), tx_context::epoch(ctx) + 1,  ctx);
        transfer::public_transfer(coin, tx_context::sender(ctx));
    }

    public entry fun unlock_coin_from_staked (pool: &mut Pool, lock_coin: LockedCoin<HONGWANG_COIN>, ctx: &mut TxContext) {
        locked_coin::unlock_coin(lock_coin, ctx);
    }

    fun earn_profit (pool: &mut Pool, amount: Coin<HONGWANG_COIN>, ctx: &mut TxContext) {
        // Base on amount from SUI's balance.
        let counting = 
            coin::value(&amount) / balance::value(&pool.reward_pool) *
            balance::value(&pool.governanceToken);
        let profit = balance::split(&mut pool.reward_pool, counting);
        let earn = coin::from_balance(profit, ctx);
        transfer::public_transfer(earn, tx_context::sender(ctx));
        
        // Return HONGWANG coin 
        balance::join(&mut pool.governanceToken, coin::into_balance(amount));
    }

    /// === General ===
    public fun pool_reward(pool:&mut Pool): &mut Balance<SUI> {
        &mut pool.reward_pool
    } 

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(PROFITS_POOL{}, ctx);
    }

    #[test_only]
    public fun deposit_from_game(pool:&mut Pool, value: u64) {
        let test_balance = balance::create_for_testing<SUI>(value);
        balance::join(&mut pool.reward_pool, test_balance);
    }

    #[allow(unused_assignment)]
    #[test]
    fun test_pool_earn_system() {
        use sui::test_scenario;
        use std::debug;
        use sui::clock;
        use sui::sui::SUI;

        //Genensis block
        let user1 = @0x0;
        let user2 = @0x1;
        let user3 = @0x2;
        let user4 = @0x3;

        let scenario_val = test_scenario::begin(user1);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(test_scenario::ctx(scenario));
        clock::increment_for_testing( &mut clock, 42);
        
        //Init CTX
        test_scenario::next_tx(scenario, user1);
        init_for_testing(test_scenario::ctx(scenario));
        
        //Init Pool
        test_scenario::next_tx(scenario, user2);
        let pool = test_scenario::take_shared<Pool>(scenario);
        deposit(&mut pool, coin::mint_for_testing<SUI>(10_000_000_000_000, test_scenario::ctx(scenario)));
        
        //
        test_scenario::next_tx(scenario, user1);
        lock_coin_for_staking(&mut pool,coin::mint_for_testing<HONGWANG_COIN>(10_000_000_000, test_scenario::ctx(scenario)),9_000_000_000, test_scenario::ctx(scenario));
        debug::print(&pool.reward_pool);
        debug::print(&pool.governanceToken);

        //
        test_scenario::next_epoch(scenario, user1);
        test_scenario::next_tx(scenario, user1);
        unlock_coin_from_staked(&mut pool, test_scenario::take_from_address<LockedCoin<HONGWANG_COIN>>(scenario, user1), test_scenario::ctx(scenario));
        debug::print(&pool.governanceToken);

        //
        test_scenario::return_shared(pool);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_pool_epoch() {
        use sui::test_scenario;
        use std::debug;
        use sui::clock;

        //Genensis block
        let user1 = @0x0;
        let user2 = @0x1;

        let scenario_val = test_scenario::begin(user1);
        let scenario  = &mut scenario_val;
        let clock = clock::create_for_testing(test_scenario::ctx(scenario));
        clock::increment_for_testing( &mut clock, 42);
        
        //Init CTX
        test_scenario::next_tx(scenario, user1);
        init_for_testing(test_scenario::ctx(scenario));
        
        //Init Pool
        test_scenario::next_tx(scenario, user2);
        let pool = test_scenario::take_shared<Pool>(scenario);

        //After one epoch and update pool.
        test_scenario::next_epoch(scenario, user1);
        pool_update(&mut pool,test_scenario::ctx(scenario));

        //Close scenario object.
        test_scenario::return_shared(pool);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_hongwang_coin_supply() {
        
    }
}