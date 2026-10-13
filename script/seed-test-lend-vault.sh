#!/usr/bin/env bash
# Seeds the test vault just deployed by script/DeployTestLendVault.s.sol: approves and deposits the manifest's
# `seedAssets` of USDC for the manifest's owner. Forge runs a script in its own EVM, which cannot execute Arc's USDC
# precompiles, so the seed is sent by `cast` instead, straight after the broadcast. Holds no key: pass the same
# `--account <keystore>` (or `--ledger`) the broadcast used; every other argument is passed to `cast send`.
#
#   bash script/seed-test-lend-vault.sh --account <keystore> [--rpc-url URL]
set -euo pipefail
cd "$(dirname "$0")/.."

chain_id=5042002
rpc=https://rpc.testnet.arc.io
signer=()
while [ $# -gt 0 ]; do
  case "$1" in
    --rpc-url) rpc="$2"; shift 2 ;;
    *) signer+=("$1"); shift ;;
  esac
done
[ ${#signer[@]} -gt 0 ] || { echo "pass --account <keystore> or --ledger" >&2; exit 2; }

manifest="deployments/manifest-$chain_id.json"
broadcast="broadcast/DeployTestLendVault.s.sol/$chain_id/run-latest.json"
[ -f "$broadcast" ] || { echo "no broadcast at $broadcast" >&2; exit 1; }
[ "$(cast chain-id --rpc-url "$rpc")" = "$chain_id" ] || { echo "RPC is not chain $chain_id" >&2; exit 1; }

read -r asset owner seed vault < <(python3 - "$manifest" "$broadcast" <<'EOF'
import json, sys
manifest, broadcast = (json.load(open(path)) for path in sys.argv[1:])
creates = [t for t in broadcast['transactions'] if t.get('transactionType') == 'CREATE']
assert len(creates) == 1 and creates[0]['contractName'] == 'TestLendVault', 'expected one TestLendVault CREATE'
print(manifest['asset'], manifest['owner'], manifest['seedAssets'], creates[0]['contractAddress'])
EOF
)

[ "$(cast code "$vault" --rpc-url "$rpc")" != "0x" ] || { echo "no vault code at $vault" >&2; exit 1; }
[ "$(cast call "$vault" 'totalAssets()(uint256)' --rpc-url "$rpc")" = "0" ] || {
  echo "$vault already holds assets; not seeding again" >&2
  exit 1
}

echo "Seeding $vault with $seed (6 decimals) for $owner"
cast send "$asset" 'approve(address,uint256)' "$vault" "$seed" --rpc-url "$rpc" "${signer[@]}"
cast send "$vault" 'deposit(uint256,address)' "$seed" "$owner" --rpc-url "$rpc" "${signer[@]}"
echo "totalAssets: $(cast call "$vault" 'totalAssets()(uint256)' --rpc-url "$rpc")"
echo "owner shares: $(cast call "$vault" 'balanceOf(address)(uint256)' "$owner" --rpc-url "$rpc")"
