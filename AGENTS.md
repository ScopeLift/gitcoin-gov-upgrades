# AGENTS.md

Guidance for AI agents (and humans) working in this repository.

## What this project is

ScopeLift is delivering two related workstreams for **Gitcoin DAO**:

1. **Governor upgrade** — replace Gitcoin's active on-chain Governor with a new Governor built on
   OpenZeppelin Contracts v5, adding security features that defend against an economic attack on
   governance.
2. **Franchiser deployment** — deploy contracts that let the DAO delegate idle treasury tokens to
   active participants, raising the cost of such an attack. _(Implementation details still being
   defined — see [Franchiser workstream](#franchiser-workstream).)_

## Why this project exists (the threat model)

If the GTC token value declines relative to the treasury the DAO administers, the cost to acquire
enough voting power to pass a malicious proposal risks falling below the value an attacker could drain.
Once `cost-to-attack < value-at-stake`, an economic attack on governance becomes profitable, and
therefore a real risk. The two workstreams address this from different angles:

- The **Franchiser makes an attack costlier** — delegating treasury tokens to active participants puts
  more voting weight in legitimate hands, so an attacker must acquire more to overcome it.
- The **Governor upgrade makes a successful attack implausible** and an attack that cannot succeed is one
  nobody mounts. Its three security features:
  - **Proposal Guardian (the #1 mechanism)** — a trusted address (e.g. a security-council multisig)
    assigned by the DAO can cancel a malicious proposal at any point in its lifecycle.
  - **Prevent Late Quorum** — guarantees a minimum window between reaching quorum and voting close,
    defeating last-minute quorum-sniping.
  - **Settable Quorum** — lets the DAO raise its own quorum by proposal, tightening the margin.

## Governance history & on-chain context

All Gitcoin governance contracts live on **Ethereum mainnet**.

- **2021** — Gitcoin launched the DAO as a source-fork of Compound's **Governor Alpha**, paired with
  a Compound `Timelock` and the COMP-style **GTC token**.
- **August 2023** — ScopeLift migrated Gitcoin off Governor Alpha to a Governor built on **OZ
  Contracts v4.8.0** (the currently active Governor). The Timelock and GTC token were retained.
- **Now** — this engagement migrates that Governor again: **OZ v4.8.0 → OZ v5.6.1**, keeping the same
  Timelock and token, while adding the security features above.

| Contract                         | Address                                      | Status                          |
| -------------------------------- | -------------------------------------------- | ------------------------------- |
| Active Governor (OZ v4.8.0)      | `0x9D4C63565D5618310271bF3F3c01b2954C1D1639` | Being **replaced** by this work |
| GTC token (COMP-style)           | `0xDe30da39c46104798bB5aA3fe8B9e0e1F348163F` | Fixed — unchanged since 2021    |
| Gitcoin DAO Timelock (Compound)  | `0x57a8865cfB1eCEf7253c27da6B4BC3dAEE5Be518` | Fixed — unchanged since 2021    |

**Prior upgrade repo** (Governor Alpha → OZ v4.8.0, Aug 2023):
<https://github.com/gitcoinco/Alpha-Governor-Upgrade>. Strong precedent for deploy scripts, the
migration proposal, and mainnet fork tests this time around.

> **Hard invariant:** the Compound Timelock and GTC token are fixed and will not change. Backward
> compatibility with them is a permanent requirement, not a transitional concern. The Governor is the
> only moving piece; everything beneath it stays put.

## Architecture

### The upgraded Governor

`src/GitcoinGovernorWithGuardian.sol` composes the OZ v5 Governor from these modules:

| Module                       | Source                | Purpose                                                      |
| ---------------------------- | --------------------- | ----------------------------------------------------------- |
| `GovernorCountingFractional` | OZ                    | Fractional vote counting.                                   |
| `GovernorVotesComp`          | **custom** (`src/extensions/`) | Sources voting weight from the COMP-style GTC token via `getPriorVotes`; block-number clock (ERC-6372). |
| `GovernorPreventLateQuorum`  | OZ                    | Enforces a minimum voting window after quorum is reached.   |
| `GovernorTimelockCompound`   | OZ                    | Executes through the existing Compound Timelock.            |
| `GovernorSettings`           | OZ                    | Voting delay, voting period, proposal threshold.            |
| `GovernorSettableFixedQuorum`| **custom** (`src/extensions/`) | Absolute (not percentage) quorum, checkpointed, settable by governance. |
| `GovernorProposalGuardian`   | OZ                    | Proposal Guardian cancel authority.                         |

The two custom extensions exist specifically to bridge the modern OZ Governor to Gitcoin's
Compound-era infrastructure (`GovernorVotesComp`) and to express quorum as a fixed count the DAO can
tune (`GovernorSettableFixedQuorum`).

Because OZ v5's Governor uses heavily multiple inheritance, the main contract carries a block of
`override(...)` functions that resolve ambiguity between inherited modules (`state`,
`proposalDeadline`, `_executor`, `_validateCancel`, `_queueOperations`, etc.). When adding or
removing a module, expect to update this override set.

### Franchiser workstream

The Franchiser contracts let a token holder delegate voting power to a delegatee who can in turn
sub-delegate it. Gitcoin uses the **"Expiry" variant** originally maintained by the Uniswap
Foundation, consumed as a git submodule at `lib/franchiser-expiry` pinned to the `repo-updates`
branch of **ScopeLift's fork**: <https://github.com/ScopeLift/franchiser-expiry>. The fork updates
the upstream toolchain to match this repo — OpenZeppelin pinned to the **same v5.6.1 commit** as
`lib/openzeppelin-contracts`, solc 0.8.35, `via_ir` off — while leaving the contract logic
untouched (the only source change is `Address.isContract` → `code.length`, an API OZ v5 removed).
Remappings resolve the fork's `openzeppelin-contracts/` imports to this repo's OZ copy, and
`solmate/` to the fork's nested submodule.

**Compatibility.** The Franchiser interacts with **only the voting token** — it touches no
Governor, Timelock, or other governance contract. At runtime it calls only `delegate`,
`balanceOf`, `transfer`/`transferFrom`, `allowance`, and `permit`, each verified present in GTC's
deployed bytecode. The upstream `IVotingToken` interface (`IERC20 + IERC20Permit + IVotes`)
declares functions GTC does not have (`getVotes`, `getPastVotes`, `DOMAIN_SEPARATOR`), but nothing
in the contracts calls them, and the interface is **deliberately left as-is**: Solidity does not
enforce interfaces at runtime, and keeping it means a zero source diff from the audited upstream
(the fork carries a ChainSecurity audit; it covered the 0.8.15/`via_ir` build, so the logic-level
findings carry over but the compiled bytecode differs). The `permitAndFund` entry points go unused
here — the funder is the Timelock, which cannot produce signatures.

**Operations model.** The factory has no owner or admin; its only parameter is the token. Each
position is a `Franchiser` clone keyed by `(owner, delegatee)`, where the owner is the Timelock.
Funding and early recall are Timelock actions, i.e. governance proposals: `approve` + `fundMany`
to delegate (re-funding a live position tops it up and **overwrites its expiration**; a zero
amount adjusts the expiration alone), `recallMany` to unwind early. Once a position's expiration
passes, `recallExpired` is **permissionless** and always returns the tokens to the owner, so
expired delegations unwind without a proposal. Sub-delegation is the delegatee's own prerogative
(up to 8 sub-delegatees at the root, halving each nesting level).

**Scripts** (each an abstract base plus a mainnet concrete, like the Governor's):

- `DeployFranchiser[Mainnet]` — deploys the `FranchiserExpiryFactory` (its constructor deploys the
  canonical `Franchiser` implementation) and the read-only `FranchiserLens`.
- `ProposeFranchiserDelegation[Mainnet]` — a delegation round; **reused** by editing and
  committing the round's delegatees/amounts/expiration, so git holds the delegation history.
  Validates wiring, treasury balance, proposer threshold, and that the expiration outlives the
  proposal pipeline (voting delay + period, Timelock delay, grace period).
- `ProposeFranchiserRecall[Mainnet]` — early unwind of live positions, recipients ordinarily the
  Timelock.
- `RecallExpiredFranchisers[Mainnet]` — permissionless sweep of expired positions; its delegatee
  list is a candidate set filtered on-chain, so a superset (every delegatee ever funded) is safe.

## Deliverables

The two workstreams ship **in sequence: the Governor upgrade first, then the Franchiser.** As a
precaution while the upgrade is underway, the DAO's treasury is currently held by a security-council
multisig rather than the Timelock, reducing exposure during the transition. The treasury is intended
to return to the Timelock once the upgraded Governor — with its Proposal Guardian — is adopted.
Because the Franchiser can only delegate tokens the DAO actually holds in the Timelock, Franchiser
adoption necessarily follows the Governor upgrade.

For **each** workstream, this project delivers:

1. **Deploy scripts** — deploy the contracts with deployment parameters that are configurable and
   tracked in git history. (Their internal structure is an implementation detail decided elsewhere,
   not specified here.)
2. **Proposal scripts** — runnable by a Gitcoin DAO delegate to put a proposal on-chain. The
   proposals produced:
   1. **Governor adoption** (one-time) — a proposal executed through the existing Timelock that
      transfers governance authority from the current Governor to the upgraded one (the
      Compound-style path used in the 2023 upgrade). The treasury returns to the Timelock once this
      is in place.
   2. **Franchiser delegation** (reusable) — a parameterizable script a delegate runs to propose
      delegating DAO treasury tokens, held by the Timelock, through the Franchiser to one or more
      delegatees. The DAO brings the Franchiser into use with its first such delegation and reuses
      the script as it adjusts its delegations over time.

The prior upgrade repo,
[`Alpha-Governor-Upgrade`](https://github.com/gitcoinco/Alpha-Governor-Upgrade), followed many of
these patterns and is the reference point and **minimum bar** for structure and rigor. This project
aims to match it and to go further on testing and simulation depth.

## Testing strategy

All tests are **mainnet fork tests** that exercise the real scripts and contracts end-to-end — not
mocks or bespoke test-only setup:

- **Run the actual deploy scripts, then the actual proposal scripts.** Tests drive the same code
  paths a delegate would, rather than reconstructing setup by hand.
- **Simulate the full adoption process, in the real sequence** (Governor adoption first, then
  Franchiser). Delegate addresses vote the adoption proposals through to both **passing and
  failing**; after the proposals complete, assert the expected resulting state.
- **Exercise the upgraded system in place, after adoption** — testing does not stop once the
  proposals execute:
  - New governance proposals run on the **upgraded Governor**.
  - Delegates that received **Franchiser delegations** vote with their updated weights.
  - Every existing and new Governor capability is exercised, including: setting a new quorum
    (`GovernorSettableFixedQuorum`); timing votes so **late-quorum protection** triggers and extends
    voting; and the **Proposal Guardian** cancelling proposals at **every stage** of the proposal
    lifecycle.
- **Fuzz wherever feasible.**
- **Keep tests modular and context-portable.** The same suite should be runnable in more than one
  context:
  - _Now:_ obtain the contracts under test by executing the real **deploy scripts** against a fork.
  - _Later:_ run the **same tests against the already-deployed contracts**, forking from a later
    block once they are on-chain.
  - Achieve this by abstracting how the system-under-test is acquired (fresh deploy vs. bound to
    existing addresses) behind a shared setup, so individual test bodies don't depend on which.

## Build, test, and lint

This is a [Foundry](https://book.getfoundry.sh/) project using the ScopeLift template.

```bash
forge build                          # compile (default/production profile)
forge test                           # run tests (default profile)
FOUNDRY_PROFILE=lite forge test      # fast local iteration (optimizer off, light fuzzing)
FOUNDRY_PROFILE=ci forge test        # deep fuzz/invariant runs, as CI runs them
scopelint fmt                        # format Solidity + foundry.toml (superset of `forge fmt`)
scopelint check                      # verify formatting & best practices (superset of `forge fmt --check`)
scopelint spec                       # generate human-readable specs from test names
```

Profiles (see `foundry.toml`):

- **default** — production solc settings (optimizer on, 10M runs).
- **ci** — same solc settings as default, with deep fuzz (5000) and invariant (1000) runs.
- **lite** — optimizer off, minimal fuzzing; for fast local iteration only.
- **coverage** — for `forge coverage` runs.

Keep the **default** and **ci** solc settings in sync — they are the production build settings; never
change solc config for `ci` alone. Use `scopelint`, not bare `forge fmt`; it's a superset and is what
CI enforces. The mainnet fork tests read the `mainnet` RPC alias from `foundry.toml`, backed by
`MAINNET_RPC_URL` in `.env` (copy `.env.template`; the URL embeds an API key and must stay
secret). CI supplies it via the `MAINNET_RPC_URL` repository secret.

## Conventions

- **Solidity:** `solc 0.8.35`, EVM version `prague`. OpenZeppelin Contracts pinned at **v5.6.1**.
- **Naming/style:** function parameters and internal/local variables are **underscore-prefixed**
  (`_proposalId`, `_caller`). Follow the repo's `foundry.toml` `[fmt]` config (100-col lines, 2-space
  indent, double quotes, `attributes_first` headers, thousands underscores).
- **NatSpec:** document contracts, functions, params, returns, events, and errors. Use `@inheritdoc`
  for overrides; the override-resolution functions are documented with a short `@dev` explaining they
  disambiguate inherited modules.
- **Tests:** structured for `scopelint spec` (test contracts/functions named after the unit under
  test). None exist yet — the Governor's behavior and the migration both need coverage, including
  mainnet fork tests.
- **Keep docs current.** `README.md` is intentionally lightweight and reflects the project's
  in-progress status. As scripts, tests, and contracts mature, update the README in the **same change**
  that introduces them — document a script's usage when the script lands, and drop the "under
  development" flags as those sections become real. Treat README updates as part of the work, not a
  follow-up.
- **Licensing:** the project is licensed **AGPL-3.0** (`LICENSE`), matching the Governor's SPDX
  header. Vendored or adapted third-party files keep their original license and SPDX identifier (e.g.
  the MIT extensions in `src/extensions/`, BSD-3-Clause for `IComp`). Preserve each file's SPDX
  identifier; don't relicense vendored code.

## Current status

- `GitcoinGovernorWithGuardian` and its two custom extensions are written.
- The Governor **deploy script** (`DeployGitcoinGovernorWithGuardian[Mainnet].s.sol`) and the
  **upgrade proposal script** (`ProposeGovernorUpgrade[Mainnet].s.sol`) are in place. Both carry
  `TODO`s to confirm with stakeholders before running (Governor name, vote extension, proposal
  guardian; new Governor address, proposer, proposal text).
- The **mainnet fork integration suite** (`test/*.integration.t.sol`) is in place: it deploys the
  new Governor with the real deploy script, submits the upgrade proposal with the real proposal
  script, and exercises the upgrade lifecycle, post-upgrade governance, quorum behavior
  (settable + late-quorum), and the Proposal Guardian. Shared helpers live in `test/helpers/`;
  each suite has a `…MainnetScript` provenance concrete, with room for a `…MainnetDeployed`
  concrete after the real deployment. Proposals are voted through by an electorate of **real
  delegates** whose live weights are read from the fork in `setUp`. The suite pins `FORK_BLOCK`
  in `test/helpers/GitcoinGovernorUpgradeTestBase.sol` — when bumping it, re-verify the
  `PROPOSER` delegate still clears the proposal threshold and the electorate still clears quorum
  (`setUp` asserts both weights loudly, and quorum-boundary tests assert their own weight
  preconditions).
- The Franchiser contracts are in place as the `lib/franchiser-expiry` submodule (ScopeLift fork,
  `repo-updates` branch), and all four **Franchiser script pairs** are written:
  `DeployFranchiser[Mainnet]`, `ProposeFranchiserDelegation[Mainnet]`,
  `ProposeFranchiserRecall[Mainnet]`, and `RecallExpiredFranchisers[Mainnet]`. The deploy script
  dry-runs clean against a mainnet fork; the proposal and sweep concretes carry `TODO`s (factory
  and new-Governor addresses, proposer, per-round delegations) and revert until those are set.
- The **Franchiser fork integration suites** (`test/PostUpgradeFranchiser*.integration.t.sol`)
  are in place: each runs the full Governor upgrade in `setUp` (the production sequence), deploys
  the Franchiser system with the real deploy script via a `_fetchOrDeployFranchiser` provenance
  hook, and drives the operations scripts through constructor-injected test configs in
  `test/helpers/`. Coverage spans delegation rounds (fresh/existing delegatees, top-ups and
  expiration overwrites, zero-amount adjustments, defeats), early recalls (including
  sub-delegation clawback and the in-flight-snapshot property — a recall cannot strip weight from
  proposals already snapshotted), expiry sweeps (permissionless, candidate filtering, weight
  persists until swept), and the scripts' validation reverts. Shared helpers live in
  `test/helpers/FranchiserUpgradeTestBase.sol`.
- Up next: confirm the outstanding `TODO`s with Gitcoin stakeholders, deploy the new Governor,
  and run the upgrade proposal (see [Deliverables](#deliverables)).
- CI runs `forge build`, `forge test`, and `scopelint check`. Coverage and Slither jobs are scaffolded
  but commented out in `.github/workflows/ci.yml`.

## References

- OpenZeppelin Governance: <https://docs.openzeppelin.com/contracts/5.x/governance>
- Foundry Book: <https://book.getfoundry.sh/>
- scopelint: <https://github.com/ScopeLift/scopelint>
- Prior Gitcoin upgrade (2023): <https://github.com/gitcoinco/Alpha-Governor-Upgrade>
