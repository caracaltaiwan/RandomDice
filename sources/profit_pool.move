#[allow(unused_use)]
module games::profits_pool {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin, TreasuryCap};
    use games::hongwang_coin::{Self, HONGWANG_COIN};
    use games::locked_coin::{Self, LockedCoin};
    use games::drand_random_dice;

    use std::debug;
    use std::string;

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
        token_in_market: u64,
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
            token_in_market: 0,
            token_supply: 0,
        };
        transfer::transfer(pool, tx_context::sender(ctx));
    }
    
    /// === Creator/Owner Operation ===
    public fun income_pool_supply(pool: &mut Pool, _cap: &mut TreasuryCap<HONGWANG_COIN>, amount: u64, ctx: &mut TxContext){
        let hwcoin = coin::mint(_cap, amount, ctx);
        let balance = coin::into_balance(hwcoin);
        pool.token_supply = pool.token_supply + balance::value(&balance);
        balance::join(&mut pool.governanceToken, balance);
    }

    public fun pool_update (pool: &mut Pool, ctx: &mut TxContext){
        pool.epoch = tx_context::epoch(ctx);
        pool.digest = *tx_context::digest(ctx);
    }

    public entry fun mint_hw_coin (cap: &mut TreasuryCap<HONGWANG_COIN>, amount: u64, ctx: &mut TxContext) {
        let coin = coin::mint(cap, amount, ctx);
        transfer::public_transfer(coin, tx_context::sender(ctx));
    }

    public entry fun lock_coin_for_staking (coin: Coin<HONGWANG_COIN>, amount : u64, ctx : &mut TxContext) {
        let balance = coin::value(&coin);
        assert!(balance >= amount, EInsufficientFunds);
        let send_to_lock_coin = coin::split(&mut coin, amount, ctx);
        locked_coin::lock_coin(send_to_lock_coin, tx_context::sender(ctx), tx_context::epoch(ctx) + 1,  ctx);
        transfer::public_transfer(coin, tx_context::sender(ctx));
    }

    public entry fun unlock_coin_from_staked (lock_coin: LockedCoin<HONGWANG_COIN>, ctx: &mut TxContext) {
        locked_coin::unlock_coin(lock_coin, ctx);
    }

    /// === General Token Operation ===
    public entry fun buy_hw_coin (pool: &mut Pool, coin: Coin<SUI>, amount: u64, ctx: &mut TxContext){
        // Print pool status
        debug::print(pool);
        // Check hw-coin has enough amount
        assert!(amount > 0, ENoProfits);
        assert!(amount <= balance::value(&pool.governanceToken), ENoProfits);
        // Check sui-coin has enough amount
        let suicoin = coin::value(&coin);
        assert!(suicoin >= 0, ENoProfits);
        assert!(suicoin >= amount, ENoProfits);
        // Pool status
        let reward = balance::value(&pool.reward_pool);
        let token_in_market = pool.token_in_market;
        // Calculate price
        let price = 100;
        if (reward!=0) { 
            price = reward / token_in_market;
        } else {
            price = 1;
        };
        // Process Pool status update
        let counting = amount / price;
        pool.token_in_market = pool.token_in_market + counting;
        // Process Reward Pool
        balance::join(&mut pool.reward_pool, coin::into_balance(coin::split(&mut coin, amount, ctx)));
        // Process HW coin
        let hw_coin = coin::from_balance(balance::split(&mut pool.governanceToken, amount), ctx);
        // Transfer token
        transfer::public_transfer(hw_coin, tx_context::sender(ctx));
        transfer::public_transfer(coin, tx_context::sender(ctx));
    }

    public entry fun sell_hw_coin (pool: &mut Pool, coin: Coin<HONGWANG_COIN>, amount: u64, ctx: &mut TxContext) {
        // Check hw-coin has enough amount
        let hwcoin = coin::value(&coin);
        assert!(hwcoin> 0, ENoProfits);
        assert!(hwcoin >= amount, ENoProfits);
        // Check sui-coin has enough amount
        assert!(amount <= pool.token_supply, ENoProfits);
        // Pool status
        let reward = balance::value(&pool.reward_pool);
        let token_in_market = pool.token_in_market;
        // Calculate price 
        let price = reward / token_in_market;
        // dx = x * dy / (y + dy)
        let counting = hwcoin * price;

        let profit = balance::split(&mut pool.reward_pool, counting);
        let sui_coin = coin::from_balance(profit, ctx);
        pool.token_in_market = token_in_market - amount;

        transfer::public_transfer(sui_coin, tx_context::sender(ctx));
        balance::join(&mut pool.governanceToken, coin::into_balance(coin));
        // Print pool status
        debug::print(pool);
    }

    /// === General ===
    public fun pool_reward(pool:&mut Pool): &mut Balance<SUI> {
        &mut pool.reward_pool
    }

    public fun pool_token_supply(pool:&mut Pool): &mut u64 {
        &mut pool.token_in_market
    }

    // === Debug ===
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

        // Control  block
        let buy_amount = 10000;
        let sell_amount = 3000;

        // Genensis block
        let user1 = @0x0;
        let user2 = @0x1;
        let user3 = @0x2;
        let user4 = @0x3;

        let scenario_val = test_scenario::begin(user1);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(test_scenario::ctx(scenario));
        clock::increment_for_testing( &mut clock, 42);
        
        // Init HWCOIN & CTX
        test_scenario::next_tx(scenario, user1);
        hongwang_coin::init_hwcoin_for_test(test_scenario::ctx(scenario));
        init_for_testing(test_scenario::ctx(scenario));

        // Mint HWCOIN
        test_scenario::next_tx(scenario, user1);
        let treasury_cap = test_scenario::take_from_address<TreasuryCap<HONGWANG_COIN>>(scenario, user1);
        
        let pool = test_scenario::take_from_address<Pool>(scenario, user1);
        income_pool_supply(&mut pool, &mut treasury_cap, 10_000, test_scenario::ctx(scenario));
        test_scenario::return_to_address(user1, treasury_cap);
        
        // Buy HW COIN
        test_scenario::next_tx(scenario, user2);
        buy_hw_coin(&mut pool, coin::mint_for_testing<SUI>(10_000, test_scenario::ctx(scenario)), buy_amount, test_scenario::ctx(scenario));

        // Sale HW COIN
        test_scenario::next_tx(scenario, user2);
        let shwcoin = test_scenario::take_from_sender<Coin<HONGWANG_COIN>>(scenario);
        sell_hw_coin(&mut pool, shwcoin, sell_amount, test_scenario::ctx(scenario));

        // End Scenario
        test_scenario::next_tx(scenario, user1);
        test_scenario::return_to_sender(scenario, pool);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario_val);
    }

    #[allow(unused_assignment)]
    #[test]
    fun test_pool_lock_coin() {
        use sui::test_scenario;
        use std::debug;
        use sui::clock;
        use sui::sui::SUI;

        // Genensis block
        let user1 = @0x0;
        let user2 = @0x1;
        let user3 = @0x2;
        let user4 = @0x3;

        let scenario_val = test_scenario::begin(user1);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(test_scenario::ctx(scenario));
        clock::increment_for_testing( &mut clock, 42);
        
        // Init HWCOIN & CTX
        test_scenario::next_tx(scenario, user1);
        hongwang_coin::init_hwcoin_for_test(test_scenario::ctx(scenario));
        init_for_testing(test_scenario::ctx(scenario));

        // Mint HWCOIN
        test_scenario::next_tx(scenario, user1);
        let treasury_cap = test_scenario::take_from_address<TreasuryCap<HONGWANG_COIN>>(scenario, user1);
        let pool = test_scenario::take_from_address<Pool>(scenario, user1);
        income_pool_supply(&mut pool, &mut treasury_cap, 10_0000, test_scenario::ctx(scenario));
        test_scenario::return_to_address(user1, treasury_cap);
        
        // Time Lock Coin
        test_scenario::next_tx(scenario, user1);
        lock_coin_for_staking(coin::mint_for_testing<HONGWANG_COIN>(10, test_scenario::ctx(scenario)),9, test_scenario::ctx(scenario));
        debug::print(&pool.reward_pool);
        debug::print(&pool.governanceToken);

        // Time Unlock Coin
        test_scenario::next_epoch(scenario, user1);
        test_scenario::next_tx(scenario, user1);
        unlock_coin_from_staked(test_scenario::take_from_sender<LockedCoin<HONGWANG_COIN>>(scenario), test_scenario::ctx(scenario));
        debug::print(&pool.governanceToken);

        // End Scenario
        test_scenario::next_tx(scenario, user1);
        test_scenario::return_to_sender(scenario, pool);
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
        let pool = test_scenario::take_from_address<Pool>(scenario, user2);

        //After one epoch and update pool.
        test_scenario::next_epoch(scenario, user1);
        pool_update(&mut pool,test_scenario::ctx(scenario));

        //Close scenario object.
        test_scenario::return_to_sender(scenario, pool);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_hongwang_coin_supply() {
        
    }
}