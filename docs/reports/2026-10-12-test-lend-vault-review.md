# TestLendVault review and release evidence (12 October 2026)

Candidate: `src/TestLendVault.sol` and `src/interfaces/ITestLendVault.sol` at the sha256 values in
`source-manifest.json`; `script/DeployTestLendVault.s.sol`, `script/EarnDeployBase.sol`, `script/write-earn-record.py`.
Toolchain: Foundry 1.4.3-Homebrew (SHA-256 `7a91e6ef…020c6`), Solidity 0.8.26, Cancun, via-IR, 200 runs for `src/**`,
no metadata hash; OpenZeppelin 5.4.0 `c64a1edb`, forge-std `5e38549`.

The vault is a testnet-only stand-in, not a production contract: it holds testnet USDC, which has no value, and Earn
adds no contract on mainnet. The evidence below is scaled to that.

| Requirement (`docs/agents/contracts.md`) | Baseline | Candidate | Evidence | Result | Open gap |
| --- | --- | --- | --- | --- | --- |
| Classification and powers | Launch: proxies and immutables, documented | Immutable; owner (two-step) can `fund` and `setWithdrawLimit`, cannot move holders' assets | `SECURITY.md`, NatSpec header | Documented | — |
| Conventions | Launch/Agents: custom errors, interfaces with NatSpec, `^0.8.26`, pinned submodules | Same; events in `ITestLendVault`, `@inheritdoc`, custom errors in the deployment base | `forge fmt --check`, `script/check-natspec.py` (13 ABI entries, 0 failures) | Pass | — |
| Source identity | `source-manifest.json` per repo | Added | `script/check-local-source.py` | Pass | — |
| Behaviour | — | Round trip, `fund` raises share price, deposits raise and payouts lower the limit (saturating), redeem at the limit, owner-only, two-step ownership, renounce disabled | `test/integration/TestLendVault.t.sol` | 11 pass | — |
| Fuzz and invariants | 512 runs default, 10,000 under `--stress`; Agents runs 1,024 × 256 invariants | `testFuzz_MaxWithdrawNeverExceedsAssets`; invariants: limit equals its model, payouts bounded, share price never falls, assets equal the balance | `bash script/check-contracts.sh --stress` (seeds `0x5042`, `0x5042002`): 262,144 calls per invariant, 0 reverts | Pass | — |
| Deployment script | Manifest-driven, chain and node guards, wiring checks | Same; refuses chains other than 5042002, a zero owner, any asset but Arc's 6-decimal USDC, a zero seed; deploys only, and `seed-test-lend-vault.sh` seeds the vault by `cast send` straight after (forge cannot execute Arc's USDC precompiles, so a seed inside the script reverts in forge's own EVM before anything is sent; found on the first real broadcast attempt, 13 Oct 2026, nothing sent) | `test/local/DeployTestLendVault.t.sol` (6 pass); loopback Anvil rehearsal at chain 5042002; Anvil fork of Arc testnet at block 66951731 with the deployer `0xAEE5…4F8E` unlocked: the script against Arc's real USDC (1 CREATE, status 1), then the seed script (approve and deposit, status 1, 153,045 gas) and its refusal to seed twice; the writer accepted the broadcast and refused the Anvil node. Anvil cannot run Arc's USDC precompiles (`0x1800…0001` blocklist, `0x1800…0000` native transfer), so the seed step ran `MockUsdc` at the USDC address; the real seed is checked on Arc by `write-earn-record.py` | Pass | — |
| Record writer | Writes only from a completed broadcast, never overwrites | Same; links every receipt to its transaction, pins the asset, verifies HEAD and a clean tree, writes EIP-55 addresses, and checks the deployment on Arc read-only (refuses an Anvil node) | `--self-test`; the rehearsal's real broadcast file accepted, then refused on chain as Anvil | Pass | — |
| Gas | `.gas-snapshot` checked | Added | `forge snapshot --check` | Pass | — |
| Static analysis | Slither 0.11.3 baseline in Agents | Slither 0.11.3, `lib`, `test` and `script` filtered | 0 results across 100 detectors | Pass | Not yet wired into `check-contracts.sh` |
| Independent review | Launch: external review history | AI-assisted security audit of the vault and tooling (13 October 2026) | Findings and fixes below | 4 Low, 8 Info; all fixed or documented | Not an audit by a security firm |

The deployment remains unauthorized: the manifest's owner is unset and a broadcast needs the owner's explicit go.

## Audit findings (13 October 2026) and their resolution

| ID | Finding | Resolution |
| --- | --- | --- |
| L-01 | Depositing then withdrawing used up the global limit at no cost | Deposits add to a set limit (saturating); `test_DepositRaisesTheLimit`, invariant `LimitMatchesTheModel` |
| L-02 | A donation moves the share price the backend reads | The deployer seeds the vault in the two transactions straight after the deployment (forge cannot seed inside the script on Arc), and the record writer refuses an unseeded vault; the six-decimal share offset makes a donation in that gap unprofitable, and the backend alarms on share-price jumps |
| L-03 | Renouncing ownership with a zero limit froze holders' assets | `renounceOwnership` reverts `RenounceDisabled`; `test_RenounceIsDisabled` |
| L-04 | A local Anvil rehearsal produced a record indistinguishable from a deployment | The writer checks the deployment on Arc and refuses a non-Arc node |
| I-01 | The deployment test depended on the committed zero owner | Tests read fixtures in `test/fixtures/` |
| I-02 | Asset and decimals not pinned | The script and the writer require Arc USDC; the script requires 6 decimals |
| I-03 | Writer: receipts not linked, revision unchecked, mixed casing | Receipts matched by hash; HEAD of a clean tree unless `--allow-unverified-revision`; EIP-55 addresses |
| I-04 | Thin test evidence | Redeem-at-limit test and the invariant campaign under `--stress` |
| I-05 | NatSpec overstated the limit model and omitted the freeze power | Rewritten; the freeze power is stated |
| I-06 | Max deposit left nothing for gas (web app) | The web app keeps Launch's 0.03 USDC gas reserve on a USDC Max deposit |
| I-07 | `setWithdrawLimit` sets an absolute value | Documented: it is the owner's own bookkeeping on a test vault |
| I-08 | The node guard admits a remote Anvil | The writer refuses any non-Arc node, so no record can come from one |

## Testnet deployment (13 Oct 2026)

| Item | Value |
| --- | --- |
| Vault | `0x830AEC6958cdD2f74A5EFC415E03aeDDD736309f`, block 66952177, tx `0x7340f6d40cefb776453050f584aa2a7eb3f12ee4a37b9e0b130ce379a9f67aed` |
| Source | `732949a6f0a5358a11384cb587f388dbd3d0bde2`; runtime code equals the local build with immutables masked (4,745 bytes) |
| Owner | Launch testnet timelock `0x41129B5215cA24b29a4cABcaE26d3569744DEe2E` |
| Seed | 10 USDC by `seed-test-lend-vault.sh` straight after; `totalAssets` 10,000,000, owner shares 10,000,000,000,000 |
| Record | `deployments/5042002.json`, written by `write-earn-record.py`, checked on Arc |

