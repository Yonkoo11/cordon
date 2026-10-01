Status: not filed (draft 2026-10-01; file before 2026-10-01 15:59 UTC)

# Cordon: submission

Cordon is a circuit breaker for Paxos USDG on Robinhood Chain. A lending market asks it, inside the same transaction, whether Paxos' mint controls and attested backing still look right. If they don't, the market values USDG collateral lower. **It is live on Robinhood Chain mainnet, and on a mainnet fork it caught a simulated 300M USDG over-mint, made through Paxos' real minter, in the same block.**

---

## HackQuest form, standard fields

**Project name**
```
Cordon
```

**One-liner**
```
Cordon tells lending markets when to stop accepting USDG.
```

**Tracks:** Overall Prize; Promising Products Track. Chain: Robinhood Chain (mainnet) and Arbitrum Sepolia.

**Description**

On 15 October 2025, Paxos accidentally minted $300 trillion of PYUSD and burned it about 20 minutes later. Aave froze its PYUSD markets by hand. Paxos also issues USDG, and today 692 million USDG sits on Robinhood Chain across 404,091 addresses, in Morpho, Uniswap, Spark and the Robinhood Earn vault.

No lending market can ask, on chain, whether USDG is still backed. Chainlink publishes a USDG price feed on Robinhood Chain and no reserve feed for USDG, or for any Paxos coin. Paxos' monthly KPMG report is about 25 days old by the time it is published.

Cordon checks the issuer's side. Its guard reads Paxos' own contracts on Robinhood Chain and returns HEALTHY, CAUTION or HALT, with the reason attached. It looks at:

- Supply jumps against a rolling baseline. HALT at +25% within an hour, about twice the largest legitimate rise in the chain's history (12,414 mints decoded; max +11.9% per hour once supply passed 300M).
- Changes to the set of addresses allowed to mint, and admin transfers scheduled inside Paxos' 3-hour delay.
- The latest KPMG figures, posted with the report's SHA-256 and labelled as posted rather than read.

A jump stays latched until the excess is burned, which is how the PYUSD incident ended. Our own reporter key cannot clear a check the chain itself failed.

The Morpho adapter wraps a market's existing oracle. On HALT it discounts USDG collateral by a share the market creator sets. It never reverts, so repaying and liquidating keep working.

Eight Morpho markets on Robinhood Chain already lend NVDA, SPY, AAPL, GOOGL, TSLA and VMAG against USDG collateral, and Cordon is built for the people lending into them. It does not help anyone who simply holds USDG, since they hold it either way. It also cannot see other chains or contract upgrades, and the status page lists those limits next to the checks.

---

## HackQuest form, project questions (300 characters each)

**Link to frontend/UI/website of your project** (63 chars)
```
https://yonkoo11.github.io/cordon/ · github.com/Yonkoo11/cordon
```

**List your Core Protocol/ Smart Contract Addresses** (216 chars)
```
Robinhood Chain mainnet: CordonGuard 0x5A832cb202aeBa13E50CFc03FF3D4C51462d0541, CordonMorphoOracle 0x52FB7D121e576D8B0b06dD6fcA6C3D7454e7bf5C. Arbitrum Sepolia: CordonGuard 0x2522423855550e82016103c79F097042Cf2d5a0B
```

**List your Factory/Pool Contracts (if applicable)** (155 chars)
```
Morpho market using Cordon, Robinhood Chain: id 0x3a8f9ccf25583b6216f553d5d8b1a2c981818b2df61febf48d60080e6850c4cc (USDG collateral, NVDA loan, LLTV 62.5%)
```

**List your Token Contract Address (if applicable)** (25 chars)
```
N/A. Cordon has no token.
```

**Which parts of your code have been produced during the Buildathon?** (261 chars)
```
All of it. The repo was created on 2026-10-01: the guard, the Morpho oracle adapter, 28 unit tests (incl. a 2,000-run fuzz test), 3 mainnet-fork tests, deploy scripts and the status page. Every commit is dated inside the window. No code predates the Buildathon.
```

**Which sponsor/partner technologies have you used as part of your project?**
```
[x] Robinhood Chain   [x] Paxos/USDG
```

**Contract Address** (42 chars)
```
0x5A832cb202aeBa13E50CFc03FF3D4C51462d0541
```

---

## What is actually running

- Status page: `https://yonkoo11.github.io/cordon/` (reads Robinhood Chain in the browser; no wallet, no server). Not published yet.
- Deployed: CordonGuard and CordonMorphoOracle on Robinhood Chain mainnet, plus a live Morpho market using the adapter; CordonGuard on Arbitrum Sepolia reading Paxos' test USDG. All verified on Sourcify (exact match). Addresses and transactions: `DEPLOYMENTS.md`.
- What it reads today: CAUTION, with the reason "no supply baseline from the last two hours". Anyone can record a baseline, but nothing records one automatically yet, so the guard drops to CAUTION whenever the last baseline is more than two hours old.

## Proof

| Claim | Evidence |
|---|---|
| Over-mint caught in the same block | `forge test --match-path test/fork/OverMint.t.sol --fork-url https://rpc.mainnet.chain.robinhood.com -vv`: 300M USDG minted by Paxos' real controller 0x2fb0…41a4 → level 2, reason 1, NVDA borrow reverted (`demo/replay.txt`) |
| Healthy markets keep working | same file: level 0, borrow of 161.9 NVDA succeeds |
| Repay and liquidation still work under HALT | same file: repay succeeds; liquidator seizes 1,000 USDG |
| Thresholds come from data | 12,414 SupplyIncreased and 9,047 SupplyDecreased events decoded; reconstructed supply matches the chain (692.4M) |
| Posted backing is the real report | KPMG USDG Redemption Assets Report, 31 Aug 2026: 3,340,650,602 USDG outstanding, $3,350,462,467 assets; PDF SHA-256 0x3847…e37e stored on chain |
| Contract quality | 28 unit tests + 3 fork tests pass; Slither: no High or Medium findings |

## What it does not do yet

- It does not prove Paxos' reserves. The reserve figure is KPMG's, posted by us with the report hash.
- It reads Robinhood Chain only. Supply minted on Ethereum, Solana or X Layer is not in the checks.
- It cannot detect contract upgrades; USDG exposes no way to read them on chain.
- Existing Morpho markets and Uniswap pools fix their oracle or hook at creation, so only new markets can adopt it.
- No curator has adopted it yet.

## Sponsor integration depth

Every `status()` call reads Paxos' USDG token (`totalSupply()`, `supplyControl()`, `pendingDefaultAdmin()`) and Paxos' SupplyControl (`getAllSupplyControllerAddresses()`, `pendingDefaultAdmin()`). Without USDG the guard has nothing to check.

On Robinhood Chain, the guard and the Morpho adapter are deployed on mainnet. The adapter wraps the oracle of a live NVDA market that takes USDG collateral, and we created the same market (same IRM, same 62.5% LLTV) on Robinhood Chain's Morpho deployment using it.

On Arbitrum, a second guard on Arbitrum Sepolia reads Paxos' test USDG.
