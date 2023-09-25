// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[allow(unused_use)]
#[test_only]
module games::drand_random_dice_test {
    use games::profits_pool::{Self as pp, HW_CAP, Pool};
    use games::drand_random_dice::{Self as drd, Game, Ticket, GameOwnerCapability};
    use games::hongwang_coin::{Self as hw_c,HONGWANG_COIN};
    use games::drand_lib::verify_time_has_passed;
    use sui::coin::{Self, TreasuryCap, Coin};
    use sui::sui::SUI;
    use sui::clock;
    use sui::tx_context;
    use sui::test_scenario as ts;
    use std::debug;

    const GENESIS: u64 = 1595431050000;

    #[test]
    fun test_verify_time_has_passed_success() {

        // Taken from the output of
        // curl https://drand.cloudflare.com/8990e7a9aaed2ffed73dbd7092123d6f289930540d7651336225dc172e51b2ce/public/8
        verify_time_has_passed(
            1595431050000 + 30*7, // exactly the 8th round
            x"b3ed3c540ef5c5407ea6dbf7407ca5899feeb54f66f7e700ee063db71f979a869d28efa9e10b5e6d3d24a838e8b6386a15b411946c12815d81f2c445ae4ee1a7732509f0842f327c4d20d82a1209f12dbdd56fd715cc4ed887b53c321b318cd7",
            x"ada04f01558359fec41abeee43c5762c4017476a1e64ad643d3378a50ac1f7d07ad0abf0ba4bada53e6762582d661a980adf6290b5fb1683dedd821fe192868d70624907b2cef002e3ee197acd2395f1406fb660c91337d505860ab306a4432e",
            8
        );
        verify_time_has_passed(
            1595431050000 + 30*7 - 10, // the 8th round - 10 seconds
            x"b3ed3c540ef5c5407ea6dbf7407ca5899feeb54f66f7e700ee063db71f979a869d28efa9e10b5e6d3d24a838e8b6386a15b411946c12815d81f2c445ae4ee1a7732509f0842f327c4d20d82a1209f12dbdd56fd715cc4ed887b53c321b318cd7",
            x"ada04f01558359fec41abeee43c5762c4017476a1e64ad643d3378a50ac1f7d07ad0abf0ba4bada53e6762582d661a980adf6290b5fb1683dedd821fe192868d70624907b2cef002e3ee197acd2395f1406fb660c91337d505860ab306a4432e",
            8
        );
    }

    #[test]
    #[expected_failure(abort_code = games::drand_lib::EInvalidProof)]
    fun test_verify_time_has_passed_failure() {

        // Taken from the output of
        // curl https://drand.cloudflare.com/8990e7a9aaed2ffed73dbd7092123d6f289930540d7651336225dc172e51b2ce/public/8
        verify_time_has_passed(
            1595431050000 + 30*8, // exactly the 9th round - 10 seconds
            x"b3ed3c540ef5c5407ea6dbf7407ca5899feeb54f66f7e700ee063db71f979a869d28efa9e10b5e6d3d24a838e8b6386a15b411946c12815d81f2c445ae4ee1a7732509f0842f327c4d20d82a1209f12dbdd56fd715cc4ed887b53c321b318cd7",
            x"ada04f01558359fec41abeee43c5762c4017476a1e64ad643d3378a50ac1f7d07ad0abf0ba4bada53e6762582d661a980adf6290b5fb1683dedd821fe192868d70624907b2cef002e3ee197acd2395f1406fb660c91337d505860ab306a4432e",
            8
        );
    }

    #[test]
    fun test_play_drand_dice() {

        // ----------- Control block ------------

        let treasury_amount = 10000_000_000_000;
        let buy_amount = 100_000_000_000;
        let sell_amount = 1_000_000_000;

        // ------------ Genensis block ------------

        let user1 = @0x0;
        let user2 = @0x1;
        let user3 = @0x2;
        let user4 = @0x3;
        let scenario_val = ts::begin(user1);
        let scenario = &mut scenario_val;
        let ctx = tx_context::dummy();
        let clock = clock::create_for_testing(&mut ctx);

        // ------------ Init block ------------

        ts::next_tx(scenario, user1);
        {
            clock::increment_for_testing( &mut clock, GENESIS);
            tx_context::increment_epoch_timestamp(ts::ctx(scenario), GENESIS + 0 * 30000);

            debug::print(&clock);
            hw_c::init_hwcoin_for_test(ts::ctx(scenario));
            drd::init_for_testing(ts::ctx(scenario));
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
            pp::income_pool_supply(&mut pool, &mut treasury_cap, treasury_amount, ts::ctx(scenario));
            ts::return_to_address(user1, treasury_cap);
            ts::return_to_sender(scenario, pool);
        };
        
        // ------------ Buy HW COIN ------------

        ts::next_tx(scenario, user1);
        {
            let pool_val = ts::take_from_address<Pool<SUI>>(scenario, user1);
            let cap = ts::take_from_address<GameOwnerCapability>(scenario, user1);
            //Create game, code equivalent : drand_random_dice::create(10, test_scenario::ctx(scenario)); 

            debug::print(&ctx);
            drd::create_after_round(&cap, pool_val, &clock, 9, ts::ctx(scenario));
            ts::return_to_sender(scenario, cap);
        };

        ts::next_tx(scenario, user1);
        {
            let game_val = ts::take_shared<Game<SUI>>(scenario);
            let game = &mut game_val;
            let pool = drd::game_pool(game);
            pp::add_liquidity(pool, coin::mint_for_testing<SUI>(buy_amount, ts::ctx(scenario)), buy_amount, ts::ctx(scenario));
            
            ts::return_shared(game_val);
        };

        // ------------ Buy Tickets ------------

        ts::next_tx(scenario, user1);
        {
            let game_val = ts::take_shared<Game<SUI>>(scenario);
            let game = &mut game_val;
            drd::play_random_dice(game, coin::mint_for_testing<SUI>(10, ts::ctx(scenario)), ts::ctx(scenario));
            ts::return_shared(game_val);
        };
        
        ts::next_tx(scenario, user2);
        {
            let game_val = ts::take_shared<Game<SUI>>(scenario);
            let game = &mut game_val;
            drd::play_random_dice(game, coin::mint_for_testing<SUI>(10, ts::ctx(scenario)), ts::ctx(scenario));
            ts::return_shared(game_val);
        };

        ts::next_tx(scenario, user3);
        {
            let game_val = ts::take_shared<Game<SUI>>(scenario);
            let game = &mut game_val;
            drd::play_random_dice(game, coin::mint_for_testing<SUI>(10, ts::ctx(scenario)), ts::ctx(scenario));
            ts::return_shared(game_val);
        };

        ts::next_tx(scenario, user4);
        {
            let game_val = ts::take_shared<Game<SUI>>(scenario);
            let game = &mut game_val;
            drd::play_random_dice(game, coin::mint_for_testing<SUI>(10, ts::ctx(scenario)), ts::ctx(scenario));
            ts::return_shared(game_val);
        };

        // ------------ Close ------------

        ts::next_tx(scenario, user2);
        // Taken from the output of
        // curl https://drand.cloudflare.com/8990e7a9aaed2ffed73dbd7092123d6f289930540d7651336225dc172e51b2ce/public/8
        {
            let game_val = ts::take_shared<Game<SUI>>(scenario);
            let game = &mut game_val;
            drd::close(
                game,
                x"b3ed3c540ef5c5407ea6dbf7407ca5899feeb54f66f7e700ee063db71f979a869d28efa9e10b5e6d3d24a838e8b6386a15b411946c12815d81f2c445ae4ee1a7732509f0842f327c4d20d82a1209f12dbdd56fd715cc4ed887b53c321b318cd7",
                x"ada04f01558359fec41abeee43c5762c4017476a1e64ad643d3378a50ac1f7d07ad0abf0ba4bada53e6762582d661a980adf6290b5fb1683dedd821fe192868d70624907b2cef002e3ee197acd2395f1406fb660c91337d505860ab306a4432e"
            );
            ts::return_shared(game_val);
        };

        // ------------ Complete ------------
        
        ts::next_tx(scenario, user3);
        // Taken from the output of
        // curl https://drand.cloudflare.com/8990e7a9aaed2ffed73dbd7092123d6f289930540d7651336225dc172e51b2ce/public/8
        {
            let game_val = ts::take_shared<Game<SUI>>(scenario);
            let game = &mut game_val;
            drd::complete(
                game,
                x"aec34e398bb53efc192ef6b91ad6960689aefa2c8326c521523d922849bb8bc16e76872640e7a1dd656e94772d9fd4ae19a63a10854a0853505bd3c8c5b8fff109ff260b0566b5ac93d2b0d8fecc9b08f7ad5101a253913f55a0c53f45c15c7f",
                x"99c37c83a0d7bb637f0e2f0c529aa5c8a37d0287535debe5dacd24e95b6e38f3394f7cb094bdf4908a192a3563276f951948f013414d927e0ba8c84466b4c9aea4de2a253dfec6eb5b323365dfd2d1cb98184f64c22c5293c8bfe7962d4eb0f5"
            );
            ts::return_shared(game_val);
        };

        // ------------ Redeem ------------

        // User3 is the winner since the mod of the hash results in 2.
        ts::next_tx(scenario, user3);
        {
            let game_val = ts::take_shared<Game<SUI>>(scenario);
            let game = &mut game_val;
            let ticket = ts::take_from_address<Ticket>(scenario, user3);
            drd::redeem(game, &ticket, ts::ctx(scenario));
            drd::delete_ticket(ticket);
            debug::print(pp::pool_reward(drd::game_pool(game)));
            ts::return_shared(game_val);
        };

        // ------------ Sale HW COIN ------------

        ts::next_tx(scenario, user1);
        {
            let game_val = ts::take_shared<Game<SUI>>(scenario);
            let game = &mut game_val;
            let pool = drd::game_pool(game);
            let shwcoin = ts::take_from_sender<Coin<HONGWANG_COIN>>(scenario);
            pp::remove_liquidity(pool, shwcoin, sell_amount, ts::ctx(scenario));
            debug::print(&std::string::utf8(b"After sell coin"));
            debug::print(pool);
            ts::return_shared(game_val);
        };

        // Dismiss all share object.
        ts::next_tx(scenario, user1);
        clock::destroy_for_testing(clock);
        ts::end(scenario_val);
    }

    #[allow(unused_assignment)]
    #[test]
    fun test_share_profit_from_pool(){

        // ------------ Genensis block ------------

        let user1 = @0x0;
        let user2 = @0x1;

        let scenario_val = ts::begin(user1);
        let scenario = &mut scenario_val;
        let ctx = tx_context::dummy();
        let clock = clock::create_for_testing(&mut ctx);

        // ------------ Init block ------------

        ts::next_tx(scenario, user1);
        {
            clock::increment_for_testing( &mut clock, GENESIS);
            drd::init_for_testing(ts::ctx(scenario));
            pp::init_for_testing(ts::ctx(scenario));
        };

        // ------------ Init Pool ------------

        ts::next_tx(scenario, user1);
        {
            let hw_cap = ts::take_from_sender<HW_CAP>(scenario);
            pp::init_pool<SUI>(&hw_cap, ts::ctx(scenario));
            ts::return_to_sender(scenario, hw_cap);
        };
        
        // ------------ Deposit SUI ------------

        ts::next_tx(scenario, user1);
        {
            let pool_val = ts::take_from_address<Pool<SUI>>(scenario, user1);
            let pool = &mut pool_val;
            pp::deposit_from_game(pool, 100);
            ts::return_to_sender(scenario, pool_val);
        };


        // ------------ End Scenario ------------

        clock::destroy_for_testing(clock);
        ts::end(scenario_val);
    }

    #[test]
    fun test_random_dice() {

        use games::hongwang_coin as hw_c;

        // ------------ Genensis block ------------

        let user1 = @0x0;
        let user2 = @0x1;
        let user3 = @0x2;
        let user4 = @0x3;

        let scenario_val = ts::begin(user1);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ts::ctx(scenario));
        clock::increment_for_testing( &mut clock, 42);
        
        // ------------ Init HWCOIN & Drand Dice ------------

        ts::next_tx(scenario, user1);
        hw_c::init_hwcoin_for_test(ts::ctx(scenario));
        drd::init_for_testing(ts::ctx(scenario));

        // ------------ End Scenario ------------

        ts::next_tx(scenario, user1);
        //test_scenario::return_to_sender(scenario, pool);
        clock::destroy_for_testing(clock);
        ts::end(scenario_val);
    }
    
}
