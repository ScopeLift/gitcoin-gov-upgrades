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
- `lib/franchiser-expiry` — the Franchiser contracts, consumed as a git submodule of
  [ScopeLift's fork](https://github.com/ScopeLift/franchiser-expiry) of the Uniswap Foundation's
  [franchiser-expiry](https://github.com/uniswapfoundation/franchiser-expiry). The fork updates
  the build toolchain to match this repo (OpenZeppelin v5, solc 0.8.35) without changing the
  contracts' logic.
- `AGENTS.md` — project context, architecture, and conventions for contributors and coding agents.
- `foundry.toml` — Foundry build profiles and formatting configuration.

- `script/` — deployment and governance-proposal scripts (see [Scripts](#scripts)) for both the
  Governor upgrade and the Franchiser system.
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

### Deploy the Franchiser system

`script/DeployFranchiser.s.sol` holds the reusable deployment mechanics, and
`script/DeployFranchiserMainnet.s.sol` supplies the mainnet configuration — just the GTC token,
since the Franchiser contracts have no owner, admin, or other parameters. The script deploys the
`FranchiserExpiryFactory` (whose constructor also deploys the canonical `Franchiser` implementation
that every delegation is cloned from) and the read-only `FranchiserLens` for inspecting delegations.

Dry-run first and review the two transactions it would send:

```sh
forge script script/DeployFranchiserMainnet.s.sol:DeployFranchiserMainnet \
  --rpc-url "$MAINNET_RPC_URL"
```

Then broadcast and verify (using an encrypted keystore account set up with `cast wallet import`):

```sh
forge script script/DeployFranchiserMainnet.s.sol:DeployFranchiserMainnet \
  --rpc-url "$MAINNET_RPC_URL" \
  --account deployer \
  --broadcast \
  --verify
```

### Propose Franchiser delegations

`script/ProposeFranchiserDelegation.s.sol` holds the reusable proposal mechanics, and
`script/ProposeFranchiserDelegationMainnet.s.sol` supplies the configuration for a delegation
round. Run by a delegate, it submits a two-action proposal to the Governor: the Timelock approves
the factory for the round's total amount, and the factory pulls the tokens into one Franchiser per
delegatee (`fundMany`), delegating each balance to its delegatee until the round's expiration.

Unlike the one-time upgrade proposal, this script is reused: each round edits the delegatees,
amounts, expiration, and proposal text in the mainnet configuration, and commits the edit so the
repository keeps a history of every round. Funding a delegatee who already has a live position
tops it up and overwrites the position's expiration — a zero amount adjusts the expiration alone.

Before broadcasting, the script validates the round: the factory and Governor share the same
token, the Timelock holds the total being delegated, the proposer clears the proposal threshold,
no delegatee is duplicated or the zero address, and the expiration outlives the full proposal
pipeline (voting delay and period plus the potential late-quorum extension, Timelock delay, and
grace period), since funding reverts if the expiration has passed by execution.

```sh
# Dry-run, then broadcast as the proposer:
forge script script/ProposeFranchiserDelegationMainnet.s.sol:ProposeFranchiserDelegationMainnet \
  --rpc-url "$MAINNET_RPC_URL"

forge script script/ProposeFranchiserDelegationMainnet.s.sol:ProposeFranchiserDelegationMainnet \
  --rpc-url "$MAINNET_RPC_URL" \
  --account proposer \
  --broadcast
```

### Propose Franchiser recalls

`script/ProposeFranchiserRecall.s.sol` and `script/ProposeFranchiserRecallMainnet.s.sol` unwind
delegations **before** they expire — the DAO's lever if a delegatee goes inactive or rogue. The
proposal carries one action, `factory.recallMany`, returning each position's tokens (including any
the delegatee sub-delegated) to a recipient, ordinarily the Timelock — any other recipient sends
treasury funds elsewhere, so the dry run prints a prominent warning for each one. Like the
delegation script, each recall edits and commits the mainnet configuration, and the script
validates the positions exist before proposing. Expired positions don't need a proposal — see the
next section.

```sh
# Dry-run, then broadcast as the proposer:
forge script script/ProposeFranchiserRecallMainnet.s.sol:ProposeFranchiserRecallMainnet \
  --rpc-url "$MAINNET_RPC_URL"

forge script script/ProposeFranchiserRecallMainnet.s.sol:ProposeFranchiserRecallMainnet \
  --rpc-url "$MAINNET_RPC_URL" \
  --account proposer \
  --broadcast
```

### Recall expired Franchiser positions

`script/RecallExpiredFranchisers.s.sol` and `script/RecallExpiredFranchisersMainnet.s.sol` sweep
expired positions back to the Timelock with `factory.recallManyExpired`. This is **not** a
governance action: recalling an expired position is permissionless and the tokens always return
to the position's owner, so anyone can run it from any funded account. The configured delegatee
list is a candidate set — the script checks each candidate on-chain and recalls only the positions
that exist and have expired — so the intended maintenance is to keep every delegatee the DAO has
ever funded on the list.

```sh
# Dry-run, then broadcast from any account:
forge script script/RecallExpiredFranchisersMainnet.s.sol:RecallExpiredFranchisersMainnet \
  --rpc-url "$MAINNET_RPC_URL"

forge script script/RecallExpiredFranchisersMainnet.s.sol:RecallExpiredFranchisersMainnet \
  --rpc-url "$MAINNET_RPC_URL" \
  --account keeper \
  --broadcast
```

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

The Franchiser suites run the same full upgrade in `setUp` — matching the production sequence,
where Franchiser adoption follows the Governor upgrade — then deploy the Franchiser system with
the real deploy script and drive the operations scripts end-to-end:

- `PostUpgradeFranchiserDeploy` — the deployed factory, `Franchiser` implementation, and lens are
  wired to GTC and to each other.
- `PostUpgradeFranchiserDelegation` — delegation rounds passing (and failing) through governance:
  fresh and already-delegated delegatees, multi-delegatee rounds, top-ups that overwrite a
  position's expiration, zero-amount expiration adjustments, snapshot timing, and the delegation
  script's validation rules.
- `PostUpgradeFranchiserRecall` — early recalls returning tokens and weight to the Timelock,
  clawing back sub-delegated tokens, the snapshot weight a recall cannot reach, and negative
  tests that neither delegatees nor third parties can move delegated tokens.
- `PostUpgradeFranchiserExpiry` — the permissionless sweep returning expired positions, its
  on-chain candidate filtering, the weight that persists until a sweep actually runs, and the
  guard protecting live positions.

Each suite is written against an abstract base that leaves *how the system comes into being* to a
small concrete contract at the bottom of the file. Today each file has a `…MainnetScript` concrete
that deploys via the real deploy scripts; once the new Governor and the Franchiser system are live
on mainnet, `…MainnetDeployed` concretes pointing at the deployed addresses can rerun the same
suites as a post-deployment acceptance check.

## License

This project is licensed under the [GNU Affero General Public License v3.0](./LICENSE), with the
exception of individual files that carry their own SPDX license identifier — for example, the
MIT-licensed extensions under `src/extensions/`, which retain their original license.
