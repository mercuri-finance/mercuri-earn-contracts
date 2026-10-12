#!/usr/bin/env python3
"""Writes the Earn deployment record `<chainId>.json` from a completed forge broadcast of
script/DeployTestLendVault.s.sol. No keys, no network.

The record has the shape of Launch's deployment records (one flat JSON object, sorted keys, two-space indent, chain id
and blocks as integers): testLendVault, deployBlock, deployer, the manifest inputs (asset, owner, name, symbol), version
and sourceRevision.

It only ever writes from a broadcast that completed: forge's `run-latest.json` with no pending transaction, exactly one
deployment (TestLendVault) as a CREATE with a receipt of status 1 naming the same contract address, the broadcast's
chain equal to the manifest's, and constructor arguments equal to the manifest's. Anything else is refused and nothing
is written. A dry run (`dry-run/`, no receipts) is refused.

  python3 script/write-earn-record.py --broadcast FILE [--manifest FILE] [--out-dir deployments]
                                      --source-revision SHA
  python3 script/write-earn-record.py --self-test

It never overwrites a record: archive the current one first (as `archive/<chainId>-<deployBlock>.json`). The record is
written to a temporary file and hard-linked into place, which fails if the name exists.
"""
import argparse
import json
import os
import re
import sys
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
VERSION = '0.1.0-testnet'
CONTRACT = 'TestLendVault'
MANIFEST_KEYS = {'chainId', 'asset', 'owner', 'name', 'symbol'}
SHA = re.compile(r'^[0-9a-f]{40}$')
ADDRESS = re.compile(r'^0x[0-9a-fA-F]{40}$')


class Refused(Exception):
    """The broadcast or the manifest cannot produce a record."""


def _int(value):
    return int(value, 16) if isinstance(value, str) and value.startswith('0x') else int(value)


def build_record(broadcast, manifest, source_revision):
    """Returns the record for a completed broadcast, or raises Refused."""
    if set(manifest) != MANIFEST_KEYS:
        raise Refused(f'manifest keys {sorted(manifest)} != {sorted(MANIFEST_KEYS)}')
    if not ADDRESS.match(manifest['owner']) or int(manifest['owner'], 16) == 0:
        raise Refused('manifest owner is zero or malformed')
    if not SHA.match(source_revision):
        raise Refused('source revision must be a full lower-case commit SHA')
    if broadcast.get('pending'):
        raise Refused('broadcast has pending transactions')
    if _int(broadcast.get('chain', 0)) != manifest['chainId']:
        raise Refused(f"broadcast chain {broadcast.get('chain')} != manifest chainId {manifest['chainId']}")
    transactions = [t for t in broadcast.get('transactions', []) if t.get('transactionType') == 'CREATE']
    if len(transactions) != 1 or transactions[0].get('contractName') != CONTRACT:
        raise Refused(f'expected exactly one CREATE of {CONTRACT}')
    tx = transactions[0]
    receipts = broadcast.get('receipts', [])
    if len(receipts) != 1:
        raise Refused('expected exactly one receipt (a dry run has none)')
    receipt = receipts[0]
    if _int(receipt.get('status', 0)) != 1:
        raise Refused('deployment receipt status is not 1')
    address = tx.get('contractAddress') or ''
    if not ADDRESS.match(address) or (receipt.get('contractAddress') or '').lower() != address.lower():
        raise Refused('receipt contract address differs from the CREATE')
    args = tx.get('arguments') or []
    expected = [manifest['asset'], manifest['name'], manifest['symbol'], manifest['owner']]
    if [str(a).lower() for a in args] != [str(e).lower() for e in expected]:
        raise Refused(f'constructor arguments {args} != manifest {expected}')
    return {
        'asset': manifest['asset'],
        'chainId': manifest['chainId'],
        'deployBlock': _int(receipt['blockNumber']),
        'deployer': tx['transaction']['from'],
        'name': manifest['name'],
        'owner': manifest['owner'],
        'sourceRevision': source_revision,
        'symbol': manifest['symbol'],
        'testLendVault': address,
        'version': VERSION,
    }


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
    manifest = {'chainId': 5042002, 'asset': '0x3600000000000000000000000000000000000000',
                'owner': '0x00000000000000000000000000000000000000a1', 'name': 'Mercurifi Test Vault',
                'symbol': 'mtvUSDC'}
    vault = '0x00000000000000000000000000000000000000b2'
    good = {
        'chain': 5042002, 'pending': [],
        'transactions': [{'transactionType': 'CREATE', 'contractName': CONTRACT, 'contractAddress': vault,
                          'arguments': [manifest['asset'], manifest['name'], manifest['symbol'], manifest['owner']],
                          'transaction': {'from': '0x00000000000000000000000000000000000000c3'}}],
        'receipts': [{'status': '0x1', 'contractAddress': vault, 'blockNumber': '0x10'}],
    }
    revision = 'a' * 40
    record = build_record(good, manifest, revision)
    assert record['testLendVault'] == vault and record['deployBlock'] == 16, record

    def refused(broadcast=None, manifest_=None, rev=revision):
        try:
            build_record(broadcast or good, manifest_ or manifest, rev)
        except Refused:
            return True
        return False

    assert refused(broadcast={**good, 'chain': 5042}), 'other chain accepted'
    assert refused(broadcast={**good, 'pending': [{}]}), 'pending accepted'
    assert refused(broadcast={**good, 'receipts': []}), 'dry run accepted'
    assert refused(broadcast={**good, 'receipts': [{**good['receipts'][0], 'status': '0x0'}]}), 'failed tx accepted'
    assert refused(manifest_={**manifest, 'owner': '0x' + '0' * 40}), 'zero owner accepted'
    assert refused(rev='HEAD'), 'short revision accepted'
    swapped = json.loads(json.dumps(good))
    swapped['transactions'][0]['arguments'][3] = '0x00000000000000000000000000000000000000d4'
    assert refused(broadcast=swapped), 'owner mismatch accepted'
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
    parser.add_argument('--source-revision')
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.broadcast is None or args.source_revision is None:
        parser.error('--broadcast and --source-revision are required')
    broadcast = json.loads(args.broadcast.read_text())
    manifest_path = args.manifest or root / 'deployments' / f"manifest-{_int(broadcast.get('chain', 0))}.json"
    manifest = json.loads(manifest_path.read_text())
    try:
        target = write_once(build_record(broadcast, manifest, args.source_revision), args.out_dir)
    except Refused as error:
        sys.exit(f'refused: {error}')
    print(f'wrote {target}')


if __name__ == '__main__':
    main()
