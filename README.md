# Mercurifi Earn contracts

The contract set for Mercurifi Earn, separate from Launch, Trade and Agents.

| Contract | Network | Purpose |
| --- | --- | --- |
| [`TestLendVault.sol`](src/TestLendVault.sol) | Arc testnet only | A plain ERC-4626 vault over USDC that stands in for a lending venue, because Arc testnet has no Morpho or Aave. The owner simulates earnings with `fund()` and a mostly-lent-out vault with `setWithdrawLimit()`. |

Earn phase 1 (Lend) adds no Mercurifi contract on mainnet: the app deposits straight into the lending venue. Phase 2 range vaults will land here after their own spec and audit.

```sh
forge test
EARN_TEST_VAULT_OWNER=0x… forge script script/DeployTestLendVault.s.sol --rpc-url https://rpc.testnet.arc.network --broadcast --account <keystore>
```

The deploy script refuses every chain but Arc testnet (5042002). Nothing here is deployed to mainnet.
