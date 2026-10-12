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
| Behaviour | — | Round trip, `fund` raises share price, limit caps `maxWithdraw`/`maxRedeem` and decreases on payout, owner-only, two-step ownership | `test/integration/TestLendVault.t.sol` | 6 pass | — |
| Fuzz | 512 runs default, 10,000 under `--stress` | `testFuzz_MaxWithdrawNeverExceedsAssets` | `bash script/check-contracts.sh --stress` (seed `0x5042`) | Pass | No invariant suite: a single-owner test vault with no accounting beyond OpenZeppelin's |
| Deployment script | Manifest-driven, chain and node guards, wiring checks | Same; refuses chains other than 5042002, a zero owner, an asset without code | `test/local/DeployTestLendVault.t.sol` | 4 pass | No loopback fork rehearsal yet: run before the broadcast |
| Record writer | Writes only from a completed broadcast, never overwrites | Same, with `--self-test` | `script/write-earn-record.py --self-test` | Pass | — |
| Gas | `.gas-snapshot` checked | Added | `forge snapshot --check` | Pass | — |
| Static analysis | Slither 0.11.3 baseline in Agents | Not run | — | Pending | Run Slither before a broadcast |
| Independent review | Launch: external review history | AI-assisted whole-branch review of Earn phase 1 | Earn phase 1 final review (backend, web, vault) | No vault findings | Not an audit by a security firm |

The deployment remains unauthorized: the manifest's owner is unset and a broadcast needs the owner's explicit go.
