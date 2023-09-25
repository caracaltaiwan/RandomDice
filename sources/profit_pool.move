#[allow(unused_use)]
module games::profits_pool {
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin, TreasuryCap};
    use games::hongwang_coin::{Self, HONGWANG_COIN};
    use games::locked_coin::{Self, LockedCoin};
    use games::drand_random_dice;

    use std::debug;

    friend drand_random_dice;

    /// Not enough funds to pay for the good in question
    const EInsufficientFunds: u64 = 0;
    /// Nothing to withdraw
    const ENoProfits: u64 = 1;

    // ------------ Objects ------------
    
    struct Pool<phantom T> has key, store {
        id : UID,
        // Also a sui pool.
        reward_pool : balance::Balance<T>,
        epoch : u64,
        digest : vector<u8>,
        governanceToken : balance::Balance<HONGWANG_COIN>,
        token_in_market: u64,
        token_supply: u64,
    }

    struct HW_CAP has key {
        id: UID,
    }

    // ------------ Witness ------------
    
    struct PROFITS_POOL has drop {}

    // ------------ Constructor ------------
    
    fun init (witness: PROFITS_POOL, ctx: &mut TxContext) {
        let hw_cap = HW_CAP{id: object::new(ctx)};
        transfer::transfer(hw_cap, tx_context::sender(ctx));
    }

    public entry fun init_pool<T> (_cap: &HW_CAP, ctx: &mut TxContext) {
        let pool = Pool<T> {
            id: object::new(ctx),
            reward_pool: balance::zero(), 
            epoch : tx_context::epoch(ctx),
            digest : *tx_context::digest(ctx),
            governanceToken : balance::zero<HONGWANG_COIN>(),
            token_in_market: 0,
            token_supply: 0,
        };
        transfer::transfer(pool, tx_context::sender(ctx));
    }
    
    // ------------ Creator/Owner Operation ------------
    
    public fun income_pool_supply<T> (pool: &mut Pool<T>, _cap: &mut TreasuryCap<HONGWANG_COIN>, amount: u64, ctx: &mut TxContext){
        let hwcoin = coin::mint(_cap, amount, ctx);
        let balance = coin::into_balance(hwcoin);
        pool.token_supply = pool.token_supply + balance::value(&balance);
        balance::join(&mut pool.governanceToken, balance);
    }

    public fun pool_update<T> (pool: &mut Pool<T>, ctx: &mut TxContext){
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

    // ------------ General Token Operation ------------

    public entry fun add_liquidity<T> (pool: &mut Pool<T>, coin: Coin<T>, amount: u64, ctx: &mut TxContext){
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
        if (reward != 0) { 
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

    public entry fun remove_liquidity<T> (pool: &mut Pool<T>, coin: Coin<HONGWANG_COIN>, amount: u64, ctx: &mut TxContext) {
        // Check hw-coin has enough amount
        let hwcoin = coin::value(&coin);
        assert!(hwcoin > 0, ENoProfits);
        assert!(hwcoin >= amount, ENoProfits);
        // Check sui-coin has enough amount
        debug::print(&amount);
        assert!(amount <= pool.token_supply, ENoProfits);
        // Pool status
        let reward = balance::value(&pool.reward_pool);
        debug::print(&reward);
        let token_in_market = pool.token_in_market;
        debug::print(&token_in_market);
        // Calculate price [dy /(y + dy)] = reward / token_in_market
        // dx = x * dy / (y + dy)
        // Commutative for Calculate Limit.
        let counting = hwcoin / token_in_market * reward;
        //debug::print(&price);
        debug::print(&counting);
        // Process Reward Pool
        let profit = balance::split(&mut pool.reward_pool, counting);
        let sui_coin = coin::from_balance(profit, ctx);
        // Process Pool status update
        pool.token_in_market = token_in_market - amount;
        transfer::public_transfer(sui_coin, tx_context::sender(ctx));
        // Process HW coin
        balance::join(&mut pool.governanceToken, coin::into_balance(coin));
    }

    // ------------ General ------------
    public fun pool_id<T> (pool: &Pool<T>): ID{
        object::uid_to_inner(&pool.id)
    }
    
    public fun pool_reward<T> (pool:&mut Pool<T>): &mut Balance<T> {
        &mut pool.reward_pool
    }

    public fun pool_governance<T> (pool:&mut Pool<T>): &mut Balance<HONGWANG_COIN> {
        &mut pool.governanceToken
    }

    public fun pool_token_supply<T> (pool:&mut Pool<T>): &mut u64 {
        &mut pool.token_in_market
    }

    // ------------ Debug ------------
    #[test_only]
    public fun init_for_testing (ctx: &mut TxContext) {
        init(PROFITS_POOL{}, ctx);
    }

    #[test_only]
    public fun deposit_from_game<T> (pool:&mut Pool<T>, value: u64) {
        let test_balance = balance::create_for_testing<T>(value);
        balance::join(&mut pool.reward_pool, test_balance);
    }
}