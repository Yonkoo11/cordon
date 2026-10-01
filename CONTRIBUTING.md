# Contributing to Cordon

Issues and pull requests are welcome.

- Build and test: `forge test --no-match-path "test/fork/*"` must pass; run the fork suite against Robinhood Chain with `forge test --match-path test/fork/OverMint.t.sol --fork-url https://rpc.mainnet.chain.robinhood.com` before changing anything in `src/`.
- A new check in `CordonGuard` needs a reason bit, a unit test for the bit, and a line on the status page saying whether it is read from the chain or posted.
- Never commit keys. Deploy scripts read `DEPLOYER_PRIVATE_KEY` from the environment.
- Security issues: open a GitHub security advisory rather than a public issue.
