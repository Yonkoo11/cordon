# Deployments

All source verified on Sourcify (exact match). Deployer and reporter: 0xf9946775891a24462cD4ec885d0D4E2675C84355.

## Robinhood Chain mainnet (chain 4663)

| Contract | Address | Tx (block) |
|---|---|---|
| CordonGuard (USDG 0x5fc5…d168) | 0x5A832cb202aeBa13E50CFc03FF3D4C51462d0541 | 0xe5f0c49b5b767005b52a61eca0ef0b30446192107a95a0949da33ca116ec370f (77155919) |
| postAttestation, KPMG 2026-08-31 | — | 0xcaf4db9b5063292e736ce1d4bbc3aa777c619c19c3574db34322646db8815086 (77155949) |
| first checkpoint | — | 0xda9d7ef6b3cb1d8cea6a38cd3ef46c78ed7e368b64e4bca76f2ac0a8b8ea5aab (77155978) |
| CordonMorphoOracle (base: live NVDA/USDG oracle 0x5481…7A10, discount 5000 bps) | 0x52FB7D121e576D8B0b06dD6fcA6C3D7454e7bf5C | 0x35a512a79a25ebe24b3cd559a8324e0b9f5ada290b8f05a0947f61e6ff499757 (77156160) |
| Morpho market: USDG collateral, NVDA loan, LLTV 0.625, IRM 0x2BD3…0fa1 | id 0x3a8f9ccf25583b6216f553d5d8b1a2c981818b2df61febf48d60080e6850c4cc | 0x61d1776f9ce90d589d6dcd047df60b7a2a290041f4cf0aea43c90e650d909eb9 (77156190) |

## Arbitrum Sepolia (chain 421614)

| Contract | Address | Tx (block) |
|---|---|---|
| CordonGuard (Paxos test USDG 0xFFC95faa3d63Cde504a05B567C600B78C0b41892); no attestation posted, the KPMG figures describe mainnet | 0x2522423855550e82016103c79F097042Cf2d5a0B | 0x55fb01d1ba25b7426f8e3e65f93d5bbae6e6f3f4d6c926532fda0a3b1fc0f893 (314548909) |

## Superseded (same code under the working name "Backed", deployed earlier on 2026-10-01; not used)

- Robinhood Chain: guard 0x60aa769416EfBbc0A6BC9cb454758dE6f76D52B5, oracle 0xac4a29515E0c2407ce0F4093C9143753F1b069F5, market 0x99b038b2578a5f9fc142f5fedbd24c6de0e8a4bc81e51e8d8016d0621145a0e5
- Arbitrum Sepolia: guard 0x3116355dADA421a9b483787b1f1e519331d70dA8
