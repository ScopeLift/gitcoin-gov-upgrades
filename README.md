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

The tests fork Ethereum mainnet, so they need an archive-node RPC endpoint: copy `.env.template`
to `.env` and set `MAINNET_RPC_URL`. The URL typically embeds an API key — keep it secret (`.env`
is gitignored). CI supplies it through the `MAINNET_RPC_URL` repository secret.

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
- `test/` — mainnet fork integration tests simulating the full upgrade and exercising the upgraded
  Governor (see [Testing](#testing)).

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
  --rpc-url "$MAINNET_RPC_URL"
```

Then broadcast and verify (using an encrypted keystore account set up with `cast wallet import`):

```sh
forge script script/DeployGitcoinGovernorWithGuardianMainnet.s.sol:DeployGitcoinGovernorWithGuardianMainnet \
  --rpc-url "$MAINNET_RPC_URL" \
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
  --rpc-url "$MAINNET_RPC_URL"
```

Then broadcast as the proposer (using an encrypted keystore account set up with
`cast wallet import`):

```sh
forge script script/ProposeGovernorUpgradeMainnet.s.sol:ProposeGovernorUpgradeMainnet \
  --rpc-url "$MAINNET_RPC_URL" \
  --account proposer \
  --broadcast
```

> 🚧 **Still under development.** The Franchiser scripts — deployment and delegation — are not yet
> available. Usage instructions will be documented here as they land.

## Testing

The integration tests (`test/*.integration.t.sol`) run against a fork of Ethereum mainnet pinned
to a fixed block, and simulate the entire upgrade the way it will actually happen: the real deploy
script deploys the new Governor onto the fork, the real proposal script submits the upgrade
proposal to the currently active Governor, and delegates vote it through to execution — after
which the suites exercise the upgraded Governor in place:

- `GovernorUpgradeProposal` — the upgrade proposal's lifecycle on the active Governor: passing it
  hands the Timelock to the new Governor; defeating it leaves the current Governor in control.
- `PostUpgradeGovernance` — day-to-day governance after adoption: proposals moving ETH and tokens
  held by the Timelock, updating the Governor's own settings, fractional voting, and Timelock
  expiry.
- `PostUpgradeQuorumBehavior` — the DAO adjusting its own quorum, and the late-quorum protection
  extending voting when quorum is reached near the deadline.
- `PostUpgradeProposalGuardian` — the Proposal Guardian cancelling proposals at every cancelable
  lifecycle stage, the limits of that power, and the DAO replacing the guardian.

Each suite is written against an abstract base that leaves *how the system comes into being* to a
small concrete contract at the bottom of the file. Today each file has a `…MainnetScript` concrete
that deploys via the real deploy script; once the new Governor is live on mainnet, a
`…MainnetDeployed` concrete pointing at the deployed address can rerun the same suites as a
post-deployment acceptance check.

## License

This project is licensed under the [GNU Affero General Public License v3.0](./LICENSE), with the
exception of individual files that carry their own SPDX license identifier — for example, the
MIT-licensed extensions under `src/extensions/`, which retain their original license.
