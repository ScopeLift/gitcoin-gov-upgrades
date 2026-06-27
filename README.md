# Gitcoin Governance Upgrades

Contracts and scripts to harden [Gitcoin DAO](https://www.gitcoin.co/)'s on-chain governance. The
project upgrades the DAO's Governor to an OpenZeppelin v5 implementation that adds security
features — a Proposal Guardian, late-quorum protection, and a DAO-settable quorum — and deploys the
Franchiser contracts so the DAO can delegate idle treasury tokens to active participants. Together
these raise the cost of, and harden governance against, an economic attack on the treasury.

> ⚠️ **Under active development.** Contracts, scripts, and their interfaces are incomplete and
> subject to change. Nothing here is audited or deployed yet.

## Development

This is a [Foundry](https://book.getfoundry.sh/) project. With Foundry installed:

```sh
forge build                       # compile contracts
forge test                        # run the test suite
FOUNDRY_PROFILE=lite forge test   # faster local iteration (optimizer off)
```

Formatting and linting use [scopelint](https://github.com/ScopeLift/scopelint), a superset of
`forge fmt`:

```sh
scopelint fmt     # format Solidity and foundry.toml
scopelint check   # verify formatting and conventions (also run in CI)
```

## Repository contents

- `src/GitcoinGovernorWithGuardian.sol` — the upgraded Governor, composing OpenZeppelin v5 modules
  with the custom extensions below.
- `src/extensions/` — custom Governor extensions: `GovernorVotesComp` (sources votes from the
  COMP-style GTC token) and `GovernorSettableFixedQuorum` (a fixed quorum the DAO can update).
- `src/interfaces/` — supporting interfaces (e.g. `IComp`).
- `AGENTS.md` — project context, architecture, and conventions for contributors and coding agents.
- `foundry.toml` — Foundry build profiles and formatting configuration.

- `script/` — deployment scripts (see [Scripts](#scripts)). The Governor deploy script is in place;
  governance-proposal and Franchiser scripts are still being built.

The test suite (`test/`) is still being built.

## Scripts

### Deploy the upgraded Governor

`script/DeployGitcoinGovernorWithGuardian.s.sol` holds the reusable deployment mechanics, and
`script/DeployGitcoinGovernorWithGuardianMainnet.s.sol` supplies the mainnet configuration: the GTC
token and Compound Timelock addresses (fixed since 2021), plus governance parameters that mirror the
active "GTC Governor Bravo" so the upgrade preserves current behavior. The new late-quorum vote
extension and the Governor name carry `TODO`s to confirm with stakeholders before deploying.

Dry-run first to simulate the deployment and print the transaction it would send, and review that
before broadcasting:

```sh
forge script script/DeployGitcoinGovernorWithGuardianMainnet.s.sol:DeployGitcoinGovernorWithGuardianMainnet \
  --rpc-url "$ETH_RPC_URL"
```

Then broadcast and verify (using an encrypted keystore account set up with `cast wallet import`):

```sh
forge script script/DeployGitcoinGovernorWithGuardianMainnet.s.sol:DeployGitcoinGovernorWithGuardianMainnet \
  --rpc-url "$ETH_RPC_URL" \
  --account deployer \
  --broadcast \
  --verify
```

> 🚧 **Still under development.** The governance-proposal scripts — Governor adoption, Franchiser
> deployment, and Franchiser delegation — are not yet available. Usage instructions will be
> documented here as they land.

## License

This project is licensed under the [GNU Affero General Public License v3.0](./LICENSE), with the
exception of individual files that carry their own SPDX license identifier — for example, the
MIT-licensed extensions under `src/extensions/`, which retain their original license.
