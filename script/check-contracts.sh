#!/usr/bin/env bash
# Earn candidate checks. Local only: no .env loading, signing or broadcasting.
#
#   bash script/check-contracts.sh            # the gate
#   bash script/check-contracts.sh --stress   # plus the 10,000-run fuzz pass and the deep invariant campaign
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ $# -gt 1 || (${1:-} != "" && ${1:-} != "--stress") ]]; then
  echo 'usage: bash script/check-contracts.sh [--stress]' >&2
  exit 2
fi

mkdir -p test-export
# The deployed sources must be exactly the reviewed ones.
python3 script/check-local-source.py
# Every check below reads out/. Start from an empty one so no stale artifact can satisfy a check.
forge clean
forge fmt --check
forge build
python3 script/check-natspec.py
# The Earn record: only from a completed DeployTestLendVault broadcast, never overwritten.
python3 script/write-earn-record.py --self-test
forge test --fuzz-seed 0x5042
# Earn gas: deterministic tests only.
forge snapshot --check --no-match-contract 'Fork|Invariant' --no-match-test '^testFuzz_' --fuzz-seed 0x5042

if [[ ${1:-} == "--stress" ]]; then
  # Every invariant suite runs in the deep campaign below, so the 10,000-run fuzz step leaves it out.
  FOUNDRY_FUZZ_RUNS=10000 forge test --no-match-contract 'InvariantsTest' --fuzz-seed 0x5042
  # Vault invariants, 1,024 runs at depth 256, their own counterexample directory.
  campaign_dir=$(mktemp -d -t mercuri-earn-invariant)
  echo "Earn invariant counterexamples, if any: $campaign_dir"
  FOUNDRY_INVARIANT_RUNS=1024 FOUNDRY_INVARIANT_DEPTH=256 \
    FOUNDRY_INVARIANT_FAIL_ON_REVERT=true \
    FOUNDRY_INVARIANT_FAILURE_PERSIST_DIR="$campaign_dir" \
    forge test --match-path 'test/invariant/TestLendVaultInvariants.t.sol' --fuzz-seed 0x5042002
fi
