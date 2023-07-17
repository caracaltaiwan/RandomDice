//create game 
sui client call --package 0xf10e952d082d0f728112064b445958622f40d8a3ea72d8179224be95632bd21b --module drand_based_lottery --function create_after_round --gas-budget 100000000 --gas 0x8c635e82e65f2bd6e4299e79c7c50fdb57615dcc79dcf341580e44a195ad0cb8 --args 0x6 1


//stake token
sui client call --package 0x778ce991da269b80aa515c0e3c87db83afdca00458f4e4c40ea5d06d4f4c35aa --module profits_pool --function lock_coin_for_staking --gas-budget 100000000 --gas 0xdf6c4a7ee36181720fa3f873dccc845b40d4a2fda8c6de587a4e1b60b3ce5826 --args 0x5c04b53c6afeb0d6650cc60e6622dac9a90efac04de782844c8930b41a5f7f78 0x5e4f8598b6e68ea2b75d77ae94887400e0a0807de5ea144d2125b2972928acd6 9