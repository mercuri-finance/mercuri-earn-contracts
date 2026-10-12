# Security

## Reporting a vulnerability

Use GitHub's private reporting: **Security → Report a vulnerability** on this repository. The report is visible only to
the maintainers until a fix is deployed and disclosed. Please do not open a public issue for anything that could be
exploited.

Include the contract and function, the chain (Arc testnet 5042002), a transaction or a Foundry test that shows the
behaviour, and what you think the impact is. You will get an acknowledgement within 48 hours and updates as the fix
moves.

## Scope

The contracts in `src/` (`TestLendVault` and its interface) and the deployment script and record writer in `script/`,
on Arc testnet. The dependencies under `lib/` are upstream code; report defects in them upstream as well.

Out of scope: the web app, the API and the hosting, which are not in this repository; the third-party lending vaults
Earn lists on Arc mainnet, which belong to their protocols and curators; and findings that require a compromised owner
key.

## Trust and governance

| Component | Mutability | Who controls what |
| --- | --- | --- |
| `TestLendVault` | Immutable: no proxy, upgrade, delegatecall or selfdestruct | Holders deposit, withdraw and redeem their own shares. The owner (two-step transfer) can add assets with `fund` and cap payouts with `setWithdrawLimit`; it has no function that moves holders' assets. |

## Pause and recovery

There is no pause. The owner can set the withdraw limit to zero, which stops every withdrawal; that simulates a fully
lent-out vault and is the point of the contract on testnet. Raising the limit restores withdrawals.

## Replacement

The vault is immutable. A change is a new deployment, a new record and a change to the Earn venue registry; holders
withdraw from the old vault. Nothing here is deployed to mainnet, and the deployment script refuses mainnet.

## What already exists

The vault is OpenZeppelin's ERC-4626 (5.4.0) with six virtual share decimals, plus the owner's two functions. The review
is in [`docs/reports/`](docs/reports).
