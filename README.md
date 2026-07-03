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

- `script/` — deployment and governance-proposal scripts (see [Scripts](#scripts)). The Governor
  deploy and upgrade-proposal scripts are in place; Franchiser scripts are still being built.

The test suite (`test/`) is still being built.

## Scripts

### Deploy the upgraded Governor

`script/DeployGitcoinGovernorWithGuardian.s.sol` holds the reusable deployment mechanics, and
`script/DeployGitcoinGovernorWithGuardianMainnet.s.sol` supplies the mainnet configuration: the GTC
token and Compound Timelock addresses (fixed since 2021), plus governance parameters that mirror the
active "GTC Governor Bravo" so the upgrade preserves current behavior. The new late-quorum vote
extension, the initial proposal guardian, and the Governor name carry `TODO`s to confirm with
stakeholders before deploying.

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

### Propose the Governor upgrade

`script/ProposeGovernorUpgrade.s.sol` holds the reusable proposal mechanics, and
`script/ProposeGovernorUpgradeMainnet.s.sol` supplies the mainnet configuration. Run by a delegate,
it submits a two-action proposal to the currently active Governor: the Timelock names the new
Governor as its pending admin (`setPendingAdmin`), and the new Governor claims the role
(`__acceptAdmin`). Before broadcasting, the script validates that both Governors are wired to the
same Timelock, that the old Governor is the Timelock's current admin, and that the proposer's
voting weight meets the proposal threshold.

The new Governor's address, the proposer, and the final proposal text carry `TODO`s. The script
reverts until the first two are set — the proposal cannot be submitted before the new Governor is
deployed and a proposer is confirmed.

Dry-run first to simulate the proposal and review the transaction it would send:

```sh
forge script script/ProposeGovernorUpgradeMainnet.s.sol:ProposeGovernorUpgradeMainnet \
  --rpc-url "$ETH_RPC_URL"
```

Then broadcast as the proposer (using an encrypted keystore account set up with
`cast wallet import`):

```sh
forge script script/ProposeGovernorUpgradeMainnet.s.sol:ProposeGovernorUpgradeMainnet \
  --rpc-url "$ETH_RPC_URL" \
  --account proposer \
  --broadcast
```

> 🚧 **Still under development.** The Franchiser scripts — deployment and delegation — are not yet
> available. Usage instructions will be documented here as they land.

## License

This project is licensed under the [GNU Affero General Public License v3.0](./LICENSE), with the
exception of individual files that carry their own SPDX license identifier — for example, the
MIT-licensed extensions under `src/extensions/`, which retain their original license.
