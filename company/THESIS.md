# Backed — company thesis

Status: draft
Started: 2026-10-01

> Method and the D0-D5 ladder: ~/.claude/skills/company-thesis/SKILL.md
> Lines starting with ">" are guidance and are ignored by company-check.sh.
> A block counts as filled when it has one line that is not a quote, not blank, not TODO.

## 1. Who exactly

> Someone you could contact today, a real count with where it came from, what they do instead
> right now, and what that costs them in money, minutes or risk.

- Pitch: an issuer-level circuit breaker for Paxos USDG. Contracts that take USDG in exchange for something else ask it, in the same transaction, whether Paxos' controls and posted backing still look right.
- Who: the teams running contracts that take USDG for other value on Robinhood Chain and Arbitrum: Morpho market creators and curators with USDG as collateral (Steakhouse Financial, curator of the Robinhood Earn USDG vault, is the first contact), Uniswap v4 pools pairing USDG with another asset, wrappers that mint a product on USDG (Spark's spUSDG, Maple's syrupUSDG), and GMX GLV pools in USDG on Arbitrum. Depositors in a USDG-denominated vault are not protected by a guard (they hold USDG either way) and are not the audience.
- How many: on Robinhood Chain the top holders include Lighter escrow 97.5M USDG, Morpho 59.4M, Uniswap PoolManager 52.7M, a Veda BoringVault 29.2M, Spark Vault 14.1M and a Steakhouse vault 2.9M; 404,101 addresses hold USDG there (Blockscout API, 2026-10-01). Live supply: Robinhood Chain 692.5M, Arbitrum 13.1M, Ethereum 321.0M, X Layer 1,423.0M, Ink 62.6M, Mantle 0.5M (cast totalSupply, 2026-10-01).
- What they do today: price feeds only. Chainlink publishes USDG/USD market price on Robinhood Chain, Arbitrum, Ethereum and X Layer, and no USDG reserve feed on any of them (Chainlink reference data directory, 2026-10-01). Backing is checked by reading Paxos' monthly KPMG report, a PDF published about 25 days after the period it covers (period end 2026-08-31, published 2026-09-25, per Pharos).
- What it costs them: a price feed moves after a backing or bridge problem is already in the market; a vault that keeps accepting USDG in that window takes the loss for its depositors. Steakhouse's own alert system lists "Proof of reserves" as a source it monitors.

## 2. Demand evidence

> D0 asserted · D1 a stranger's words in public · D2 a named requester · D3 a conversation
> D4 a commitment without money · D5 money or use.
> One line per piece of evidence, newest first:
>   - D2 2026-09-16 <who asked and for what> — <link or person + date>
> The stated Level must be backed by an evidence line at that level.

Level: D1

- D1 2026-10-01 Steakhouse, curator of the Robinhood Earn USDG vault, lists under "Issuer Quality and Trust": "Source: Proof of reserves, financial disclosures" and the example alert "Changes in proof of reserves" — https://www.steakhouse.financial/docs/risk-management/monitoring/alert-system
- D1 2026-10-01 Steakhouse's alert system also names "Large reserve movements by the issuer (withdrawing a significant percentage of reserves within a short timeframe)" as a governance alert — same page
- D1 2026-10-01 Aave adopted a proof-of-reserve executor that freezes an asset when its reserve feed fails; the pattern is wanted by lenders, but it needs a feed, and USDG has none — https://github.com/aave-dao/aave-proof-of-reserve
- No D2 yet: nobody has asked for a USDG feed by name.

## 3. Distribution

> Channels ranked, then the ones that have actually been used. A channel is not distribution
> until a message has left:
>   - Sent: 2026-09-16 <where> — <link> — <what came back, including "no reply yet">

Ranked:
1. Steakhouse Financial risk team (curates the Robinhood Earn USDG vault; their docs name proof of reserves as a monitored source). Contact through their docs site and X.
2. Spark / Sky forum (spUSDG), where collateral and oracle changes are proposed in public.
3. Paxos developer relations: an independent feed of their own coin is something they can point to, or replace with an official one.
4. Arbitrum and Robinhood Chain builder channels, and the Open House Discord.

No Sent: line yet.

## 4. Why this team, why now

> Two sentences. Specific: a shipped project, a deployed contract, domain work, an unusual data
> source, a platform change that only landed this quarter.

USDG became the main dollar on Robinhood Chain this quarter (692.5M there against 13.1M on Arbitrum, measured 2026-10-01) and Robinhood Earn put retail savings into a USDG vault, while no reserve feed exists for it on any chain. We already run contracts on Robinhood Chain mainnet (Quorum's claim registry) and write exploit proofs for a living, which is the skill a guard contract needs.

## 5. After the deadline

> Three dated items, minimum. This is the part that shows the project continues whether or not
> it places, and it is the part no previous project here has ever written down.
>   - 2026-09-30 <the next real thing>

- 2026-10-08 send the live feed and guard to Steakhouse's risk team and the Spark forum; record replies here
- 2026-10-15 ask Paxos developer relations whether they will sign the attested numbers, which removes the trusted-reporter problem
- 2026-10-31 decide: keep going if one curator reads the feed or asks for a change, else write the post-mortem

## 6. Kill test

> One line: the observation that would make you stop, and the date you will look.

If by 2026-10-31 no curator holding USDG has replied, or Chainlink lists a USDG reserve feed, stop and write the post-mortem.
