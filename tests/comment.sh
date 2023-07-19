//create game //create_after_round (Clock, u64) 
sui client call --package 0x4bd7d44c64731aea6ae984b2f7b13ae749b0cb81f2b75d865b41f7fcb9572807 --module drand_random_dice --function create_after_round --gas-budget 100000000 --gas 0x63c01a374eaf8be29e5b1aef7882d8d53c40ef2595e0224b5cd4e1cc11d52311 --args 0x6 1

//buy participate //participate (Game, Coin<SUI>)
sui client call --package 0x4bd7d44c64731aea6ae984b2f7b13ae749b0cb81f2b75d865b41f7fcb9572807 --module drand_random_dice --function participate --gas-budget 100000000 --gas 0x63c01a374eaf8be29e5b1aef7882d8d53c40ef2595e0224b5cd4e1cc11d52311 --args 0xf181f1794d4033f090d6cb1b8a11acdb0695e9fda95a58c4ef5d9869d64e8f7a 0xba80dee166eb34b561653c9a0067cd564988f218422806a8618997b35864b467

//collect profits  //collect_profits (GameOwnerCapability, Game, Pool)
sui client call --package 0x4bd7d44c64731aea6ae984b2f7b13ae749b0cb81f2b75d865b41f7fcb9572807 --module drand_random_dice --function collect_profits --gas-budget 100000000 --gas 0x63c01a374eaf8be29e5b1aef7882d8d53c40ef2595e0224b5cd4e1cc11d52311 --args 0x8b4154e5d7c3d626651fd27f1f6b95d71c9346a6cfb753f8603fb798daabe5ed 0xf181f1794d4033f090d6cb1b8a11acdb0695e9fda95a58c4ef5d9869d64e8f7a 0xad552babfc0f453e00861499009e5306667cd81b87b8d7b0ddf5d859270cb828

//stake token //lock_coin_for_staking (Pool, Coin<SUI>, amount)
sui client call --package 0xd0b733ce4e693cbdbf29051c28a80d72f1f0148aeaeecd821c99d33065fc3dae --module profits_pool --function lock_coin_for_staking --gas-budget 100000000 --gas 0x63c01a374eaf8be29e5b1aef7882d8d53c40ef2595e0224b5cd4e1cc11d52311 --args 0xad552babfc0f453e00861499009e5306667cd81b87b8d7b0ddf5d859270cb828 0x8bd294cc4dfbca0a6fd3774e2f16979914ce9ca5a5d8ae8f498cc562f2a8444f 9

//upgrade package
sui client upgrade --gas-budget 100000000 --gas 0x63c01a374eaf8be29e5b1aef7882d8d53c40ef2595e0224b5cd4e1cc11d52311 --upgrade-capability 0xccae12e2d2dde5f671f15522d35202193a2470ea03f0256e8d47c9e0471db96f