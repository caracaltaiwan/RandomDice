// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Helper module for working with drand outputs.
/// Currently works with chain 8990e7a9aaed2ffed73dbd7092123d6f289930540d7651336225dc172e51b2ce.
///
/// See examples in drand_based_lottery.move.
///
module games::drand_lib {
    use std::hash::sha2_256;
    use std::vector;
    use std::debug;

    use sui::bls12381;
    use sui::clock;

    /// Error codes
    const EInvalidRndLength: u64 = 0;
    const EInvalidProof: u64 = 1;

    /// The genesis time of chain 8990e7a9aaed2ffed73dbd7092123d6f289930540d7651336225dc172e51b2ce.
    const GENESIS: u64 = 1595431050;
    /// The public key of chain 8990e7a9aaed2ffed73dbd7092123d6f289930540d7651336225dc172e51b2ce.
    const DRAND_PK: vector<u8> =
        x"868f005eb8e6e4ca0a47c8a77ceaa5309a47978a7c71bc5cce96366b5d7a569937c529eeda66c7293784a9402801af31";

    /// Check that a given epoch time has passed by verifying a drand signature from a later time.
    /// round must be at least (epoch_time - GENESIS)/30 + 1).
    public entry fun verify_time_has_passed(epoch_time: u64, sig: vector<u8>, prev_sig: vector<u8>, round: u64) {
        assert!(epoch_time <= GENESIS + 30 * (round - 1), EInvalidProof);
        verify_drand_signature(sig, prev_sig, round);
    }

    /// Check a drand output.
    public entry fun verify_drand_signature(sig: vector<u8>, prev_sig: vector<u8>, round: u64) {
        // Convert round to a byte array in big-endian order.
        let round_bytes: vector<u8> = vector[0, 0, 0, 0, 0, 0, 0, 0];
        let i = 7;
        while (i > 0) {
            let curr_byte = round % 0x100;
            let curr_element = vector::borrow_mut(&mut round_bytes, i);
            *curr_element = (curr_byte as u8);
            round = round >> 8;
            i = i - 1;
        };

        // Compute sha256(prev_sig, round_bytes).
        vector::append(&mut prev_sig, round_bytes);
        let digest = sha2_256(prev_sig);
        // Verify the signature on the hash.
        //debug::print(&sig);
        //debug::print(&DRAND_PK);
        //debug::print(&digest);
        assert!(bls12381::bls12381_min_pk_verify(&sig, &DRAND_PK, &digest), EInvalidProof);
    }

    /// Derive a uniform vector from a drand signature.
    public fun derive_randomness(drand_sig: vector<u8>): vector<u8> {
        sha2_256(drand_sig)
    }

    // Converts the first 16 bytes of rnd to a u128 number and outputs its modulo with input n.
    // Since n is u64, the output is at most 2^{-64} biased assuming rnd is uniformly random.
    public fun safe_selection(n: u64, rnd: &vector<u8>): u64 {
        assert!(vector::length(rnd) >= 16, EInvalidRndLength);
        let m: u128 = 0;
        let i = 0;
        while (i < 16) {
            m = m << 8;
            let curr_byte = *vector::borrow(rnd, i);
            m = m + (curr_byte as u128);
            i = i + 1;
        };
        let n_128 = (n as u128);
        let module_128  = m % n_128;
        let res = (module_128 as u64);
        res
    }

    /// Automatically fetching the latest round.
    public entry fun get_lateset_round(timestamp_ms: u64): u64{
        let clock = timestamp_ms;
        debug::print(&timestamp_ms);
        let round = (clock - GENESIS)  / 30 + 1;
        round
    }

    #[test]
    fun test_random() {
        let _test = sha2_256(x"aec34e398bb53efc192ef6b91ad6960689aefa2c8326c521523d922849bb8bc16e76872640e7a1dd656e94772d9fd4ae19a63a10854a0853505bd3c8c5b8fff109ff260b0566b5ac93d2b0d8fecc9b08f7ad5101a253913f55a0c53f45c15c7f");
        //debug::print<vector<u8>>(&_test);
        //debug::print<vector<u8>>(&sha2_256(x"aec34e398bb53efc192ef6b91ad6960689aefa2c8326c521523d922849bb8bc16e76872640e7a1dd656e94772d9fd4ae19a63a10854a0853505bd3c8c5b8fff109ff260b0566b5ac93d2b0d8fecc9b08f7ad5101a253913f55a0c53f45c15c7f"));
    }

    #[test]
    fun test_round() {
        use std::debug;
        use sui::tx_context;

        //Create and initial clock object
        let ctx = tx_context::dummy();
        let clock = clock::create_for_testing(&mut ctx);

        clock::increment_for_testing( &mut clock, GENESIS + 42 +60);
        
        // Get time from 
        let time = sui::clock::timestamp_ms(&clock);
        debug::print(&get_lateset_round(time));
        clock::destroy_for_testing(clock);
    }
}