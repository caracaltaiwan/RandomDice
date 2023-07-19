// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module games::hongwang_coin {
    use std::option;
    use sui::coin;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    /// The amount of Mist per Sui token based on the the fact that mist is
    /// 10^-9 of a Sui token
    const MIST_PER_SUI: u64 = 1_000_000_000;

    /// The total supply of Sui denominated in whole Sui tokens (10 Billion)
    const TOTAL_SUPPLY_SUI: u64 = 10_000_000_000;

    /// The total supply of Sui denominated in Mist (10 Billion * 10^9)
    const TOTAL_SUPPLY_MIST: u64 = 10_000_000_000_000_000_000;

    /// The type identifier of coin. The coin will have a type
    /// tag of kind: `Coin<package_object::mycoin::MYCOIN>`
    /// Make sure that the name of the type matches the module's name.
    struct HWCOIN has drop {}

    /// Module initializer is called once on module publish. A treasury
    /// cap is sent to the publisher, who then controls minting and burning
    fun init(witness: HWCOIN, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness, 
            6, 
            b"HWCOIN", 
            b"", 
            b"", 
            option::none(), ctx);
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, tx_context::sender(ctx))
    }
}
