#!/usr/bin/env python3
"""Writes the Earn deployment record `<chainId>.json` from a completed forge broadcast of
script/DeployTestLendVault.s.sol. No keys, no network.

The record has the shape of Launch's deployment records (one flat JSON object, sorted keys, two-space indent, chain id
and blocks as integers): testLendVault, deployBlock, deployer, the manifest inputs (asset, owner, name, symbol), version
and sourceRevision.

It only ever writes from a broadcast that completed: forge's `run-latest.json` with no pending transaction, exactly
exactly one transaction, the CREATE of TestLendVault, with its own receipt (matched by hash) of status 1, the CREATE's receipt naming the same contract address, the broadcast's chain
equal to the manifest's, the asset Arc's USDC, and constructor arguments equal to the manifest's. It then checks the
chain itself, read-only over `--rpc`: the node must be an Arc node (not Anvil, so a rehearsal never becomes a record),
the deployment receipt must be on chain with status 1, the vault must have code and report the manifest's asset and
owner, and it must be seeded: `totalAssets()` at least the manifest's `seedAssets` and the owner holding shares. Forge
cannot run Arc's USDC precompiles, so the seed is sent by `cast` after the broadcast (README, Deployment). Anything else is refused and nothing is written. A dry run (`dry-run/`, no receipts) is refused.

The source revision is HEAD, which must have no uncommitted changes under src/, script/, deployments/ or foundry.toml;
`--allow-unverified-revision` takes a full SHA as given, for a record written from another checkout, to be reviewed by
hand. Addresses are written EIP-55 checksummed (`cast to-check-sum-address`).

  python3 script/write-earn-record.py --broadcast FILE [--manifest FILE] [--out-dir deployments]
                                      [--rpc URL] [--source-revision SHA [--allow-unverified-revision]]
  python3 script/write-earn-record.py --self-test

It never overwrites a record: archive the current one first (as `archive/<chainId>-<deployBlock>.json`). The record is
written to a temporary file and hard-linked into place, which fails if the name exists.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

root = Path(__file__).resolve().parents[1]
VERSION = '0.1.0-testnet'
CONTRACT = 'TestLendVault'
MANIFEST_KEYS = {'chainId', 'asset', 'owner', 'name', 'symbol', 'seedAssets'}
USDC = '0x3600000000000000000000000000000000000000'
DEFAULT_RPC = 'https://rpc.testnet.arc.io'
# Arc's public RPC answers Python's default User-Agent with 403, as the Trade rehearsals found for Anvil.
RPC_HEADERS = {'Content-Type': 'application/json', 'User-Agent': 'curl/8.7.1'}
TX_HASH = re.compile(r'^0x[0-9a-fA-F]{64}$')
SEL_ASSET = '0x38d52e0f'  # asset()
SEL_OWNER = '0x8da5cb5b'  # owner()
SEL_TOTAL_ASSETS = '0x01e1d114'  # totalAssets()
SEL_BALANCE_OF = '0x70a08231'  # balanceOf(address)
SHA = re.compile(r'^[0-9a-f]{40}$')
ADDRESS = re.compile(r'^0x[0-9a-fA-F]{40}$')


class Refused(Exception):
    """The broadcast or the manifest cannot produce a record."""


def _int(value):
    return int(value, 16) if isinstance(value, str) and value.startswith('0x') else int(value)


def checksum(address):
    """EIP-55 casing, as the other Mercurifi records use."""
    return subprocess.run(['cast', 'to-check-sum-address', address], check=True, capture_output=True,
                          text=True).stdout.strip()


def build_record(broadcast, manifest, source_revision, to_checksum=checksum):
    """Returns the record for a completed broadcast, or raises Refused."""
    if set(manifest) != MANIFEST_KEYS:
        raise Refused(f'manifest keys {sorted(manifest)} != {sorted(MANIFEST_KEYS)}')
    if manifest['asset'].lower() != USDC:
        raise Refused('manifest asset is not Arc USDC')
    if not ADDRESS.match(manifest['owner']) or int(manifest['owner'], 16) == 0:
        raise Refused('manifest owner is zero or malformed')
    if not SHA.match(source_revision):
        raise Refused('source revision must be a full lower-case commit SHA')
    if broadcast.get('pending'):
        raise Refused('broadcast has pending transactions')
    if _int(broadcast.get('chain', 0)) != manifest['chainId']:
        raise Refused(f"broadcast chain {broadcast.get('chain')} != manifest chainId {manifest['chainId']}")
    transactions = broadcast.get('transactions', [])
    creates = [t for t in transactions if t.get('transactionType') == 'CREATE']
    if len(transactions) != 1 or len(creates) != 1 or creates[0].get('contractName') != CONTRACT:
        raise Refused(f'expected exactly one transaction, the CREATE of {CONTRACT}')
    receipts = broadcast.get('receipts', [])
    if len(receipts) != len(transactions):
        raise Refused('expected one receipt per transaction (a dry run has none)')
    by_hash = {(r.get('transactionHash') or '').lower(): r for r in receipts}
    for t in transactions:
        receipt = by_hash.get((t.get('hash') or '').lower())
        if receipt is None or not TX_HASH.match(t.get('hash') or ''):
            raise Refused(f"no receipt for transaction {t.get('hash')}")
        if _int(receipt.get('status', 0)) != 1:
            raise Refused(f"transaction {t['hash']} did not succeed")
    tx = creates[0]
    receipt = by_hash[tx['hash'].lower()]
    address = tx.get('contractAddress') or ''
    if not ADDRESS.match(address) or (receipt.get('contractAddress') or '').lower() != address.lower():
        raise Refused('receipt contract address differs from the CREATE')
    args = tx.get('arguments') or []
    expected = [manifest['asset'], manifest['name'], manifest['symbol'], manifest['owner']]
    if [str(a).lower() for a in args] != [str(e).lower() for e in expected]:
        raise Refused(f'constructor arguments {args} != manifest {expected}')
    return {
        'asset': to_checksum(manifest['asset']),
        'chainId': manifest['chainId'],
        'deployBlock': _int(receipt['blockNumber']),
        'deployTx': tx['hash'].lower(),
        'deployer': to_checksum(tx['transaction']['from']),
        'name': manifest['name'],
        'owner': to_checksum(manifest['owner']),
        'seedAssets': manifest['seedAssets'],
        'sourceRevision': source_revision,
        'symbol': manifest['symbol'],
        'testLendVault': to_checksum(address),
        'version': VERSION,
    }


def rpc_caller(url):
    """A read-only JSON-RPC call function for url."""
    def call(method, params):
        body = json.dumps({'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params}).encode()
        request = urllib.request.Request(url, data=body, headers=RPC_HEADERS)
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                answer = json.loads(response.read())
        except urllib.error.URLError as error:
            raise Refused(f'{method}: {error}') from None
        if 'error' in answer:
            raise Refused(f'{method}: RPC error')
        return answer['result']
    return call


def verify_on_chain(record, call):
    """Checks the record against the chain, read-only, or raises Refused."""
    client = call('web3_clientVersion', [])
    if not str(client).startswith('arc/'):
        raise Refused(f'{client} is not an Arc node; a rehearsal never becomes a record')
    if _int(call('eth_chainId', [])) != record['chainId']:
        raise Refused('RPC chain differs from the record')
    receipt = call('eth_getTransactionReceipt', [record['deployTx']])
    if not receipt or _int(receipt['status']) != 1:
        raise Refused('deployment receipt is not on chain with status 1')
    if (receipt.get('contractAddress') or '').lower() != record['testLendVault'].lower():
        raise Refused('on-chain receipt names another contract')
    if _int(receipt['blockNumber']) != record['deployBlock']:
        raise Refused('on-chain receipt block differs')
    vault = record['testLendVault']
    if call('eth_getCode', [vault, 'latest']) in ('0x', '', None):
        raise Refused('the vault has no code on chain')
    for selector, key in ((SEL_ASSET, 'asset'), (SEL_OWNER, 'owner')):
        word = call('eth_call', [{'to': vault, 'data': selector}, 'latest'])
        if len(word) != 66 or '0x' + word[-40:].lower() != record[key].lower():
            raise Refused(f'on-chain {key} differs from the record')
    total = _int(call('eth_call', [{'to': vault, 'data': SEL_TOTAL_ASSETS}, 'latest']))
    if total < record['seedAssets']:
        raise Refused(f"the vault is not seeded: totalAssets {total} < seedAssets {record['seedAssets']}")
    shares = _int(call('eth_call', [{'to': vault, 'data': SEL_BALANCE_OF + '0' * 24 + record['owner'][2:].lower()},
                                    'latest']))
    if shares == 0:
        raise Refused('the owner holds no shares: the seed was not deposited for the owner')


def head_revision():
    """HEAD, refusing uncommitted changes to anything the record describes."""
    dirty = subprocess.run(['git', 'status', '--porcelain', '--', 'src', 'script', 'deployments', 'foundry.toml'],
                           cwd=root, check=True, capture_output=True, text=True).stdout.strip()
    if dirty:
        raise Refused('uncommitted changes under src/, script/, deployments/ or foundry.toml')
    return subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=root, check=True, capture_output=True,
                          text=True).stdout.strip()


def write_once(record, out_dir):
    """Writes `<chainId>.json` into out_dir; refuses to replace an existing record."""
    out_dir.mkdir(parents=True, exist_ok=True)
    target = out_dir / f"{record['chainId']}.json"
    with tempfile.NamedTemporaryFile('w', dir=out_dir, delete=False, suffix='.tmp') as handle:
        json.dump(record, handle, indent=2, sort_keys=True)
        handle.write('\n')
        temp = Path(handle.name)
    try:
        os.link(temp, target)
    except FileExistsError:
        raise Refused(f'{target} exists; archive it first') from None
    finally:
        temp.unlink()
    return target


def self_test():
    manifest = {'chainId': 5042002, 'asset': USDC, 'owner': '0x00000000000000000000000000000000000000a1',
                'name': 'Mercurifi Test Vault', 'symbol': 'mtvUSDC', 'seedAssets': 100000000}
    vault = '0x00000000000000000000000000000000000000b2'
    hashes = ['0x' + c * 64 for c in '1']
    good = {
        'chain': 5042002, 'pending': [],
        'transactions': [
            {'hash': hashes[0], 'transactionType': 'CREATE', 'contractName': CONTRACT, 'contractAddress': vault,
             'arguments': [manifest['asset'], manifest['name'], manifest['symbol'], manifest['owner']],
             'transaction': {'from': '0x00000000000000000000000000000000000000c3'}},
        ],
        'receipts': [{'transactionHash': h, 'status': '0x1', 'contractAddress': vault if i == 0 else None,
                      'blockNumber': '0x10'} for i, h in enumerate(hashes)],
    }
    revision = 'a' * 40
    same = lambda address: address  # noqa: E731 - no cast needed offline
    record = build_record(good, manifest, revision, same)
    assert record['testLendVault'] == vault and record['deployBlock'] == 16 and record['deployTx'] == hashes[0]

    def refused(broadcast=None, manifest_=None, rev=revision):
        try:
            build_record(broadcast or good, manifest_ or manifest, rev, same)
        except Refused:
            return True
        return False

    def edited(path, value):
        copy = json.loads(json.dumps(good))
        target = copy
        for key in path[:-1]:
            target = target[key]
        target[path[-1]] = value
        return copy

    assert refused(broadcast={**good, 'chain': 5042}), 'other chain accepted'
    assert refused(broadcast={**good, 'pending': [{}]}), 'pending accepted'
    assert refused(broadcast={**good, 'receipts': []}), 'dry run accepted'
    assert refused(broadcast=edited(['receipts', 0, 'status'], '0x0')), 'failed deployment accepted'
    extra = edited(['pending'], [])
    extra['transactions'].append({'hash': '0x' + '2' * 64, 'transactionType': 'CALL', 'transaction': {}})
    extra['receipts'].append({'transactionHash': '0x' + '2' * 64, 'status': '0x1', 'blockNumber': '0x10'})
    assert refused(broadcast=extra), 'broadcast with more than the deployment accepted'
    assert refused(broadcast=edited(['receipts', 0, 'transactionHash'], '0x' + 'd' * 64)), 'unlinked receipt accepted'
    assert refused(broadcast=edited(['transactions', 0, 'arguments', 3], '0x' + '0' * 39 + 'd')), 'owner mismatch'
    assert refused(manifest_={**manifest, 'owner': '0x' + '0' * 40}), 'zero owner accepted'
    assert refused(manifest_={**manifest, 'asset': '0x' + '0' * 39 + 'e'}), 'another asset accepted'
    assert refused(rev='HEAD'), 'short revision accepted'

    chain = {'web3_clientVersion': 'arc/v1', 'eth_chainId': '0x4cef52',
             'eth_getTransactionReceipt': {'status': '0x1', 'contractAddress': vault, 'blockNumber': '0x10'},
             'eth_getCode': '0x6080', 'asset': '0x' + '0' * 24 + USDC[2:], 'owner': '0x' + '0' * 24 + manifest['owner'][2:],
             'totalAssets': '0x' + format(manifest['seedAssets'], '064x'), 'ownerShares': '0x' + format(10 ** 14, '064x')}

    def fake(answers):
        def call(method, params):
            if method == 'eth_call':
                data = params[0]['data']
                if data.startswith(SEL_BALANCE_OF):
                    return answers['ownerShares']
                return answers[{SEL_ASSET: 'asset', SEL_OWNER: 'owner', SEL_TOTAL_ASSETS: 'totalAssets'}[data]]
            return answers[method]
        return call

    verify_on_chain(record, fake(chain))
    for change, label in (({'web3_clientVersion': 'anvil/v1.4.3'}, 'anvil rehearsal'), ({'eth_getCode': '0x'}, 'no code'),
                          ({'owner': '0x' + '0' * 64}, 'other owner'), ({'eth_chainId': '0x13b2'}, 'other chain'),
                          ({'eth_getTransactionReceipt': None}, 'missing receipt'),
                          ({'totalAssets': '0x' + '0' * 64}, 'unseeded vault'),
                          ({'totalAssets': '0x' + format(manifest['seedAssets'] - 1, '064x')}, 'short seed'),
                          ({'ownerShares': '0x' + '0' * 64}, 'seed not held by the owner')):
        try:
            verify_on_chain(record, fake({**chain, **change}))
        except Refused:
            continue
        raise AssertionError(f'{label} accepted on chain')
    with tempfile.TemporaryDirectory() as tmp:
        write_once(record, Path(tmp))
        try:
            write_once(record, Path(tmp))
        except Refused:
            pass
        else:
            raise AssertionError('existing record overwritten')
    print('write-earn-record: self-test passed')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--broadcast', type=Path)
    parser.add_argument('--manifest', type=Path)
    parser.add_argument('--out-dir', type=Path, default=root / 'deployments')
    parser.add_argument('--rpc', default=DEFAULT_RPC)
    parser.add_argument('--source-revision')
    parser.add_argument('--allow-unverified-revision', action='store_true')
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.broadcast is None:
        parser.error('--broadcast is required')
    try:
        head = head_revision()
        revision = args.source_revision or head
        if revision != head and not args.allow_unverified_revision:
            raise Refused(f'--source-revision {revision} is not HEAD {head}; pass --allow-unverified-revision to '
                          'name another checkout')
        broadcast = json.loads(args.broadcast.read_text())
        manifest_path = args.manifest or root / 'deployments' / f"manifest-{_int(broadcast.get('chain', 0))}.json"
        record = build_record(broadcast, json.loads(manifest_path.read_text()), revision)
        verify_on_chain(record, rpc_caller(args.rpc))
        target = write_once(record, args.out_dir)
    except Refused as error:
        sys.exit(f'refused: {error}')
    print(f'wrote {target}')


if __name__ == '__main__':
    main()
