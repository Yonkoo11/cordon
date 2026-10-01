# Integrating Cordon

This is for curators and protocol teams who take Paxos USDG as collateral on Robinhood Chain (chain 4663) and want new borrowing to stop when USDG's issuer side breaks.

## Addresses (Robinhood Chain, chain 4663)

| Contract | Address |
|---|---|
| CordonGuard (watches USDG `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`) | `0x1F82E5aB72B6Ec93e852533Ed9D021CbF51969AC` |
| CordonOracleFactory | `0xA0A564D5C2D8c8E01191Cb70E39322E85B1045EF` |
| Morpho | `0x9D53d5E3bd5E8d4Cbfa6DB1ca238AEA02E651010` |

All are verified on Sourcify. Arbitrum Sepolia test deployments are listed in [`DEPLOYMENTS.md`](DEPLOYMENTS.md).

## Morpho: guard a market

Morpho fixes a market's oracle when the market is created, so you cannot add Cordon to an existing market. You create a twin market with the same loan token, interest rate model and LLTV, using a wrapper around the existing oracle.

1. Call `CordonOracleFactory.create(baseOracle, discountBps)`. It returns the wrapper, deploying it on first use. The address is deterministic: `predict(baseOracle, discountBps)` gives it in advance, and `wrapperOf(baseOracle, discountBps)` finds an existing one.
2. Call `Morpho.createMarket({loanToken, collateralToken: USDG, oracle: wrapper, irm, lltv})`.
3. Point your vault's supply queue at the new market.

[`use.html`](https://yonkoo11.github.io/cordon/use.html) does steps 1 and 2 from a browser wallet. It lists every Morpho market on Robinhood Chain that takes USDG as collateral, and marks the ones that already use Cordon.

**Check what you integrate.** A wrapper is only Cordon's if `wrapper.guard()` is the guard address above. Wrappers made through the factory always are.

## What the wrapper does

- **Normally:** `price()` returns the base oracle's price.
- **When `guard.isHalted()` is true:** `price()` returns `basePrice × (10000 − discountBps) / 10000`.
- **If the guard call reverts or runs out of gas:** it returns the base price.

It never reverts, so repaying, withdrawing and liquidating always work.

### Choosing a discount

Let `L` be the market's LLTV and `d` the discount.

- **New borrows** stop for any position whose normal loan-to-value is above `L × (1 − d)`.
- **Liquidations:** every position above that line becomes liquidatable, at the market's normal incentive.

| d | LLTV 62.5%: new borrows and liquidation line on HALT |
|---|---|
| 10% | 56.25% |
| 20% | 50.0% |
| 50% (factory maximum) | 31.25% |

A larger discount gives more protection against borrowing with unbacked USDG. It also liquidates more ordinary borrowers if HALT turns out to be a false alarm (see "Known trade-offs"). The factory caps `d` at 50%: a discount close to 100% prices the collateral near zero, which breaks Morpho liquidations sized by repaid shares. For most markets we suggest 10 to 20%.

## Any other protocol

Read the guard directly. Both calls are `view`.

```solidity
CordonGuard guard = CordonGuard(0x1F82E5aB72B6Ec93e852533Ed9D021CbF51969AC);
if (guard.isHalted()) revert UsdgHalted();          // the only signal that should move money
(CordonGuard.Level level, uint256 reasons) = guard.status(); // for dashboards and alerts
```

`isHalted()` reads only the supply checks, so a change to any other Paxos read cannot switch HALT off. `status()` reads everything and can revert if Paxos changes those contracts. Use it for monitoring, not for gating funds.

### Reason bits

Only bit 0 can produce HALT. Everything else is CAUTION, which no adapter acts on.

| Bit | Meaning | Source | Level |
|---|---|---|---|
| 0 | Supply rose more than 25% above the hourly baseline (30 min to 2 h old) or the daily anchor (up to 2 days old), or a jump is latched | chain | HALT |
| 1 | Supply rose 15 to 25% above the hourly baseline | chain | CAUTION |
| 2 | No hourly baseline in range | chain | CAUTION |
| 3 | The set of addresses allowed to mint USDG changed | chain | CAUTION |
| 4 | A USDG or SupplyControl admin transfer is scheduled | chain | CAUTION |
| 5 | The latest posted report shows reserves below tokens outstanding | our reporter | CAUTION |
| 6 | No report for a period that ended in the last 62 days | our reporter | CAUTION |
| 7 | Supply on this chain is above the posted all-chain total | our reporter | CAUTION |

## Keys and what they can do

| Role | Holder today | Can | Cannot |
|---|---|---|---|
| Owner | `0xf9946775891a24462cD4ec885d0D4E2675C84355` (one key; `transferOwnership` then `acceptOwnership` moves it to a Safe) | accept a new minter set (clears bit 3); change the reporter; schedule, cancel and execute a release | cause HALT; release a HALT sooner than 6 h after scheduling, or after supply grew since scheduling |
| Reporter | same key | post monthly KPMG figures with the report's SHA-256, for periods that have already ended | cause HALT |
| Keeper | anyone; a GitHub Actions job runs every 10 minutes from `0x17e8385CF200E07d97788368CC7A78094807AE6B` | call `checkpoint()` | anything else |

### Releasing a HALT

Releasing is how a legitimate large mint gets cleared, for example a 200M LayerZero bridge-in, which would be +29% on today's supply.

1. The owner calls `scheduleRelease()`. It records the current supply and emits `ReleaseScheduled(supply, executableAt)`.
2. Six hours later, `executeRelease()` clears the latch. It works only if supply has not grown since step 1, and it resets the daily anchor to current supply.
3. A HALT also clears by itself if the excess is burned. That is how the PYUSD error was resolved.

Watch `ReleaseScheduled` on the guard. A release you disagree with gives you 6 hours to pause your own market.

## Known trade-offs

- **Someone with enough USDG can trigger HALT without an over-mint.**
  - **How:** bridge out about 25% of the chain's supply (about 171M USDG today), take a checkpoint, then bridge it back in.
  - **What it lasts:** HALT holds until they bridge out again or a release executes.
  - **What it can gain them:** only liquidations of positions between `L × (1 − d)` and `L`.
  - **Why we accept it:** catching an over-mint in the same block, before anyone can borrow against it, matters more to us. A small discount limits what this costs your borrowers.
- **Slow over-minting is bounded, not blocked.** The daily anchor stops anyone walking supply up past 25% in a day. Up to 25% a day is still possible without HALT, and bits 1 and 2 will show CAUTION along the way.
- **Long gaps.** If no checkpoint runs for more than 2 days, both references expire and a mint in that gap is not compared against anything. The status shows bit 2 (CAUTION) the whole time.
- **One chain only.** Supply minted on other chains is invisible to this guard.
- **Upgrades are not detected.** The USDG contract exposes no implementation getter on chain.
- **Not audited.** There are 46 unit tests (including two 2,000-run fuzz tests) and 4 mainnet-fork tests, and Slither reports no High or Medium findings. That is not an audit.
