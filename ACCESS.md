# Access needed before building

Every line is something outside this machine. Every line has a fallback tier that still runs and demos.

## Accounts and keys

- [x] Deploy wallet 0xf9946775891a24462cD4ec885d0D4E2675C84355 (key in env DEPLOYER_PRIVATE_KEY, never read) — needed for: deploying the guard and adapters — how: already held — cost: free — eta: 0 — fallback: deploy from a fresh key funded from https://faucet.testnet.chain.robinhood.com, testnet only, mainnet address left unset
- [x] HackQuest account (Mustapha Alex) — needed for: registration and filing — how: https://arbitrum-singapore.hackquest.io/buildathon/17bfad43-fdef-4432-a8d7-7595b7538c41/register — cost: free — eta: 5 min — fallback: none possible for filing itself; registration is the user's first action (see Submission requirements)

## Credits and funding

- [x] Robinhood Chain mainnet gas — needed for: mainnet guard deploy — how: wallet holds 0.002306 ETH; gas 0.0202 gwei, 3M-gas deploy = 0.00006 ETH (eth_gasPrice 2026-10-01) — cost: under $1 — eta: 0 — fallback: Robinhood testnet deploy (wallet holds 0.00964 ETH there) reading Paxos test USDG 0x7E955252E15c84f5768B83c41a71F9eba181802F, labelled "testnet"
- [x] Arbitrum Sepolia gas — needed for: Arbitrum deployment — how: wallet holds 0.3986 ETH — cost: free — eta: 0 — fallback: Robinhood Chain only, Arbitrum listed as next target

## Installs and local tooling

- [x] Foundry (forge 1.4.4) — needed for: contracts, fork tests — how: installed — cost: free — eta: 0 — fallback: none needed
- [x] Robinhood Chain RPC https://rpc.mainnet.chain.robinhood.com — needed for: fork tests and reads — how: public — cost: free — eta: 0 — fallback: Blockscout API reads for state; fork tests pinned to a saved block via anvil state dump. Note: cast hit intermittent TLS errors 2026-10-01; curl JSON-RPC worked
- [ ] Archive RPC for Robinhood Chain — needed for: replaying past blocks — how: QuickNode (sponsor) — cost: unknown — eta: unknown — fallback: forks at latest block only; demo replays a fresh over-mint, not a past one

## Submission requirements

- [ ] HackQuest registration (3 pages) — needed for: being allowed to submit — how: register URL above — cost: free — eta: 10 min — fallback: none; this is the user's action
- [ ] Public GitHub repo under Yonkoo11 — needed for: "which code was produced during the Buildathon" — how: gh repo create (user's go) — cost: free — eta: 2 min — fallback: private repo shared with the reviewer account HackQuest names for stealth builds
- [ ] Live frontend URL — needed for: required submission field — how: Vercel or GitHub Pages — cost: free — eta: 15 min — fallback: GitHub Pages static page reading the chain from the browser

## Eligibility traps

- [x] Must be deployed on an Arbitrum chain (Arbitrum Sepolia, Arbitrum One or Orbit) — checked against: T&C 3.1 (sources/tc.txt)
- [x] Code must be produced during the buildathon — checked against: CoC "Original Work"; repo created 2026-10-01
- [x] Earlier cutoff in the T&C (2026-10-01 15:59 UTC) than the platform (2026-10-04 15:59 UTC) — checked against: F-001, F-002
- [ ] Token contract field asks for a token address "if applicable": Backed has no token; answer "N/A, no token" — checked against: submission form payload
