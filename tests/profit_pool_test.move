#[allow(unused_use)]
module games::profits_pool_test {
    use games::hongwang_coin::{Self as hw_c, HONGWANG_COIN};
    use games::profits_pool::{Self as pp, Pool, HW_CAP};
    use games::locked_coin::LockedCoin;
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::test_scenario as ts;

    #[allow(unused_assignment)]
    #[test]
    fun test_pool_earn_system() {
        use std::debug;
        use sui::clock;
        use sui::sui::SUI;

        // ------------ Control block ------------
        
        let buy_amount = 10000;
        let sell_amount = 3000;

        // ------------ Genensis block ------------

        let user1 = @0x0;
        let user2 = @0x1;
        let user3 = @0x2;
        let user4 = @0x3;

        let scenario_val = ts::begin(user1);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ts::ctx(scenario));
        clock::increment_for_testing( &mut clock, 42);
        
        // ------------ Init Pool Cap ------------

        ts::next_tx(scenario, user1);
        {
            hw_c::init_hwcoin_for_test(ts::ctx(scenario));
            pp::init_for_testing(ts::ctx(scenario));
        };

        // ------------ Init Pool ------------

        ts::next_tx(scenario, user1);
        {
            let hw_cap = ts::take_from_sender<HW_CAP>(scenario);
            pp::init_pool<SUI>(&hw_cap, ts::ctx(scenario));
            ts::return_to_sender(scenario, hw_cap);
        };

        // ------------ Mint HWCOIN ------------

        ts::next_tx(scenario, user1);
        {
            let treasury_cap = ts::take_from_address<TreasuryCap<HONGWANG_COIN>>(scenario, user1);

            let pool = ts::take_from_address<Pool<SUI>>(scenario, user1);
            pp::income_pool_supply(&mut pool, &mut treasury_cap, 10_000, ts::ctx(scenario));
            ts::return_to_address(user1, treasury_cap);
            ts::return_to_sender(scenario, pool);
        };
        
        // ------------ Buy HW COIN ------------

        ts::next_tx(scenario, user2);
        {
            let pool = ts::take_from_address<Pool<SUI>>(scenario, user1);
            debug::print(&std::string::utf8(b"Before buy coin"));
            debug::print(&pool);
            pp::add_liquidity(&mut pool, coin::mint_for_testing<SUI>(10_000, ts::ctx(scenario)), buy_amount, ts::ctx(scenario));
            ts::return_to_address(user1, pool);
        };

        // ------------ Sale HW COIN ------------

        ts::next_tx(scenario, user2);
        {
            let pool = ts::take_from_address<Pool<SUI>>(scenario, user1);
            let shwcoin = ts::take_from_sender<Coin<HONGWANG_COIN>>(scenario);
            pp::remove_liquidity(&mut pool, shwcoin, sell_amount, ts::ctx(scenario));
            debug::print(&std::string::utf8(b"After sell coin"));
            debug::print(&pool);
            ts::return_to_address(user1, pool);
        };

        // ------------ End Scenario ------------

        ts::next_tx(scenario, user1);
        {
            clock::destroy_for_testing(clock);
            ts::end(scenario_val);
        };
    }

    #[allow(unused_assignment)]
    #[test]
    fun test_pool_lock_coin() {
        use std::debug;
        use sui::clock;
        use sui::sui::SUI;

        // ------------ Genensis block ------------
        let user1 = @0x0;
        let user2 = @0x1;
        let user3 = @0x2;
        let user4 = @0x3;

        let scenario_val = ts::begin(user1);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ts::ctx(scenario));
        clock::increment_for_testing( &mut clock, 42);
        
        // ------------ Init HWCOIN & Pool Cap ------------
        ts::next_tx(scenario, user1);
        {
            hw_c::init_hwcoin_for_test(ts::ctx(scenario));
            pp::init_for_testing(ts::ctx(scenario));
        };

        // ------------ Init Pool ------------
        ts::next_tx(scenario, user1);
        {
            let hw_cap = ts::take_from_sender<HW_CAP>(scenario);
            pp::init_pool<SUI>(&hw_cap, ts::ctx(scenario));
            ts::return_to_sender(scenario, hw_cap);
        };

        // ------------ Mint HWCOIN ------------
        ts::next_tx(scenario, user1);
        {
            let treasury_cap = ts::take_from_address<TreasuryCap<HONGWANG_COIN>>(scenario, user1);
            let pool = ts::take_from_address<Pool<SUI>>(scenario, user1);
            pp::income_pool_supply(&mut pool, &mut treasury_cap, 10_0000, ts::ctx(scenario));
            ts::return_to_address(user1, treasury_cap);
            ts::return_to_sender(scenario, pool);
        };
        
        // ------------ Time Lock Coin ------------
        ts::next_tx(scenario, user1);
        {
            let pool = ts::take_from_address<Pool<SUI>>(scenario, user1);
            pp::lock_coin_for_staking(coin::mint_for_testing<HONGWANG_COIN>(10, ts::ctx(scenario)),9, ts::ctx(scenario));
            debug::print(pp::pool_reward(&mut pool));
            debug::print(pp::pool_governance(&mut pool));
            ts::return_to_sender(scenario, pool);
        };

        // ------------ Time Unlock Coin ------------
        ts::next_epoch(scenario, user1);
        ts::next_tx(scenario, user1);
        {
            let pool = ts::take_from_address<Pool<SUI>>(scenario, user1);
            pp::unlock_coin_from_staked(ts::take_from_sender<LockedCoin<HONGWANG_COIN>>(scenario), ts::ctx(scenario));
            debug::print(pp::pool_governance(&mut pool));
            ts::return_to_sender(scenario, pool);
        };

        // ------------ End Scenario ------------
        ts::next_tx(scenario, user1);
        {
            clock::destroy_for_testing(clock);
            ts::end(scenario_val);
        }
    }

    #[test]
    fun test_pool_epoch() {
        use std::debug;
        use sui::clock;
        use sui::sui::SUI;

        // ------------ Genensis block ------------

        let user1 = @0x0;

        let scenario_val = ts::begin(user1);
        let scenario  = &mut scenario_val;
        let clock = clock::create_for_testing(ts::ctx(scenario));
        clock::increment_for_testing( &mut clock, 42);
        
        // ------------ Init Pool Cap ------------

        ts::next_tx(scenario, user1);
        {
            pp::init_for_testing(ts::ctx(scenario));
        };

        // ------------ Init Pool ------------
        ts::next_tx(scenario, user1);
        {
            let hw_cap = ts::take_from_sender<HW_CAP>(scenario);
            pp::init_pool<SUI>(&hw_cap, ts::ctx(scenario));
            ts::return_to_sender(scenario, hw_cap);
        };
        
        // ------------ Init Pool ------------

        ts::next_tx(scenario, user1);
        {
            let pool = ts::take_from_address<Pool<SUI>>(scenario, user1);
            //After one epoch and update pool.
            ts::next_epoch(scenario, user1);
            pp::pool_update(&mut pool,ts::ctx(scenario));
            ts::return_to_sender(scenario, pool);
        };

        // ------------ End Scenario ------------

        ts::next_tx(scenario, user1);
        {
            clock::destroy_for_testing(clock);
            ts::end(scenario_val);
        };
    }

    #[test]
    fun test_hongwang_coin_supply() {
        use std::debug;
        use sui::clock;
        use sui::sui::SUI;

        // ------------ Genensis block ------------

        let user1 = @0x0;

        let scenario_val = ts::begin(user1);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ts::ctx(scenario));
        clock::increment_for_testing( &mut clock, 42);
        
        // ------------ Init HWCOIN & Pool Cap ------------

        ts::next_tx(scenario, user1);
        {
            hw_c::init_hwcoin_for_test(ts::ctx(scenario));
            pp::init_for_testing(ts::ctx(scenario));
        };

        // ------------ Init Pool ------------

        ts::next_tx(scenario, user1);
        {
            let hw_cap = ts::take_from_sender<HW_CAP>(scenario);
            pp::init_pool<SUI>(&hw_cap, ts::ctx(scenario));
            ts::return_to_sender(scenario, hw_cap);
        };

        // ------------ Mint HWCOIN ------------

        ts::next_tx(scenario, user1);
        {
            let treasury_cap = ts::take_from_address<TreasuryCap<HONGWANG_COIN>>(scenario, user1);
            let pool = ts::take_from_address<Pool<SUI>>(scenario, user1);
            pp::income_pool_supply(&mut pool, &mut treasury_cap, 10_000, ts::ctx(scenario));
            debug::print(&coin::total_supply(&treasury_cap));
            ts::return_to_address(user1, treasury_cap);
            ts::return_to_sender(scenario, pool);
        };

        // ------------ End Scenario ------------

        ts::next_tx(scenario, user1);
        {
            clock::destroy_for_testing(clock);
            ts::end(scenario_val);
        }
    }
}