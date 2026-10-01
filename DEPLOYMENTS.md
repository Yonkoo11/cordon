# Deployments

All source verified on Sourcify (exact match). Owner, reporter and deployer: 0xf9946775891a24462cD4ec885d0D4E2675C84355.

Guard parameters on both chains: HALT jump 2500 bps, CAUTION jump 1500 bps, fast baseline 1800 to 7200 s, daily anchor (advances once per 1 day, ignored after 2 days), report stale after 62 days, release notice 21600 s (6 h).

## Robinhood Chain mainnet (chain 4663)

| Contract | Address | Tx (block) |
|---|---|---|
| CordonGuard (USDG 0x5fc5…d168) | 0x1F82E5aB72B6Ec93e852533Ed9D021CbF51969AC | 0x1d427a1b6acf22437a9b7750f126ef59cc93da3a2eec64148ccad206f1742593 |
| postAttestation, KPMG 2026-08-31 | n/a | 0x75f33a107ce0cb85561c86f8de80bba20bd492ea3fae569e96d0d9a9a9f910b7 |
| first checkpoint | n/a | 0x214d9de5bc53559e36347d3affc59d18a8631f2da49bd5af85987521b97eb88d |
| CordonOracleFactory | 0xA0A564D5C2D8c8E01191Cb70E39322E85B1045EF | 0xe6448942416e5b667cc27fbb45e19f0207d9b5c3e0be5c42f909b8c1ef699d8f |
| CordonMorphoOracle via `factory.create` (base: live NVDA/USDG oracle 0x5481…7A10, discount 5000 bps) | 0x4FAFD0C44fB2757703F9e3F7B28564666Edfd860 | 0x1f68ba000da296e47730f7785eef6cf32794139b836a450fcda9e647e9cff2a7 |
| Morpho market: USDG collateral, NVDA loan, LLTV 0.625, IRM 0x2BD3…0fa1 | id 0xb2f1e172da1fc454a25f9405b0d145cccd603fe56c719d0d5f4ddaf5017b91dc | 0x279009ceff0d0563ede76a152b81cd2e39d3b060afe78824acd12165127232f7 (77349849) |

## Arbitrum Sepolia (chain 421614)

| Contract | Address | Tx (block) |
|---|---|---|
| CordonGuard (Paxos test USDG 0xFFC95faa3d63Cde504a05B567C600B78C0b41892); no attestation posted, the KPMG figures describe mainnet | 0xfEbB84BE47b0d440Ba08DaE0f5E3b09B4f989Cf8 | 0xa094dca8340a1178da4501c9601a4105f71ee458f90d852d269dcc2a2c03a40b (314627161) |
| CordonOracleFactory | 0x59a69BAFb6dCc9BF304bBE0583561aDf3B613435 | 0x0eec1b7d27ba1032b9d5ab065291d335c3f0198a9e624a238d5caf07783a15be |

## Superseded (not used)

First Cordon version, deployed earlier on 2026-10-01. Its reporter-posted figures could reach HALT, it had no release path for a legitimate large mint, and its owner was fixed at deploy.
- Robinhood Chain: guard 0x5A832cb202aeBa13E50CFc03FF3D4C51462d0541, oracle 0x52FB7D121e576D8B0b06dD6fcA6C3D7454e7bf5C, market 0x3a8f9ccf25583b6216f553d5d8b1a2c981818b2df61febf48d60080e6850c4cc
- Arbitrum Sepolia: guard 0x2522423855550e82016103c79F097042Cf2d5a0B

Same code under the working name "Backed":
- Robinhood Chain: guard 0x60aa769416EfBbc0A6BC9cb454758dE6f76D52B5, oracle 0xac4a29515E0c2407ce0F4093C9143753F1b069F5, market 0x99b038b2578a5f9fc142f5fedbd24c6de0e8a4bc81e51e8d8016d0621145a0e5
- Arbitrum Sepolia: guard 0x3116355dADA421a9b483787b1f1e519331d70dA8
