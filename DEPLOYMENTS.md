# Deployments

All source verified on Sourcify (exact match). Owner, reporter and deployer: 0xf9946775891a24462cD4ec885d0D4E2675C84355.

Guard parameters on both chains: HALT jump 2500 bps, CAUTION jump 1500 bps, fast baseline 1800 to 7200 s, two daily anchors (each advances at most once per day and never during a halt, ignored after 2 days), report stale after 62 days, release notice 21600 s (6 h).

## Robinhood Chain mainnet (chain 4663)

| Contract | Address | Tx (block) |
|---|---|---|
| CordonGuard (USDG 0x5fc5…d168) | 0x469C46486d44eE02BB5A8d4FE341e55d13f5dF25 | 0x50b0f6c1b7e5b2dfa9a2df0ed3a25a2f4b893d98921219759a61af9372ec3175 (77371013) |
| postAttestation, KPMG 2026-08-31 | n/a | 0x2ef9089a8a99fba87fa24f6d8847e82a0623f059014b41b15a70feb998cd8f50 (77371037) |
| first checkpoint | n/a | 0x1a12245f633ba9980220609c8ec7d54c938785809dc8fb0b595439434e41ba00 (77371060) |
| CordonOracleFactory | 0x5fd6b1Bf1871BD987c5c5AC451AaDeC7e70679De | 0x3b33893770df375289e29d7a7e0ac180f0e4c473a141608e61f8f0aab07b2e93 (77371085) |
| CordonMorphoOracle via `factory.create` (base: live NVDA/USDG oracle 0x5481…7A10, discount 5000 bps) | 0xaDE3788c6BD7531dD3C424C3A09527175D4F7F82 | 0x67e4014c43e820abc589f8430e33f3265669bb29d580abaa9b10ccd44c558fdb (77371475) |
| Morpho market: USDG collateral, NVDA loan, LLTV 0.625, IRM 0x2BD3…0fa1 | id 0x10b972d007b83b91ac0846339f829ccdbe06eb03aebe99eef661748e23843af6 | 0xcd2322759ceac21a5b1f3d33b77471fbaa8bccb9f11494d1d5e66b3725ce3e6a (77371499) |

## Arbitrum Sepolia (chain 421614)

| Contract | Address | Tx (block) |
|---|---|---|
| CordonGuard (Paxos test USDG 0xFFC95faa3d63Cde504a05B567C600B78C0b41892); no attestation posted, the KPMG figures describe mainnet | 0xAdEa3FaE6011c2D275868d1c1933B37BE7648269 | 0x595d268774082f4edb1aa3021be4ef887929f6f9c1ac55aacded442ee4d3b188 (314635626) |
| CordonOracleFactory | 0xAf7c0Dcee32C08a4b705e32C8F0E6599f1f3B1d5 | 0x7b96f1af33704691ab0238536e0d450acc0a6aa5cd53f695740b1fd624a02682 (314635664) |

## Superseded (not used)

Second version, deployed 2026-10-01 about 11:46 UTC and replaced the same day. A review showed that the checkpoint which latched a jump could also move the daily anchor up to the inflated supply, and that timing mints around the daily advance allowed about +56% in a day.
- Robinhood Chain: guard 0x1F82E5aB72B6Ec93e852533Ed9D021CbF51969AC, factory 0xA0A564D5C2D8c8E01191Cb70E39322E85B1045EF, oracle 0x4FAFD0C44fB2757703F9e3F7B28564666Edfd860, market 0xb2f1e172da1fc454a25f9405b0d145cccd603fe56c719d0d5f4ddaf5017b91dc
- Arbitrum Sepolia: guard 0xfEbB84BE47b0d440Ba08DaE0f5E3b09B4f989Cf8, factory 0x59a69BAFb6dCc9BF304bBE0583561aDf3B613435


First Cordon version, deployed earlier on 2026-10-01. Its reporter-posted figures could reach HALT, it had no release path for a legitimate large mint, and its owner was fixed at deploy.
- Robinhood Chain: guard 0x5A832cb202aeBa13E50CFc03FF3D4C51462d0541, oracle 0x52FB7D121e576D8B0b06dD6fcA6C3D7454e7bf5C, market 0x3a8f9ccf25583b6216f553d5d8b1a2c981818b2df61febf48d60080e6850c4cc
- Arbitrum Sepolia: guard 0x2522423855550e82016103c79F097042Cf2d5a0B

Same code under the working name "Backed":
- Robinhood Chain: guard 0x60aa769416EfBbc0A6BC9cb454758dE6f76D52B5, oracle 0xac4a29515E0c2407ce0F4093C9143753F1b069F5, market 0x99b038b2578a5f9fc142f5fedbd24c6de0e8a4bc81e51e8d8016d0621145a0e5
- Arbitrum Sepolia: guard 0x3116355dADA421a9b483787b1f1e519331d70dA8
