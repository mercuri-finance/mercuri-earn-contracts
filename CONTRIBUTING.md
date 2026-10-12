# Contributing

This repository owns the Mercurifi Earn contracts, their tests and release tooling. The contracts are immutable, so a
change to a deployed contract is a new reviewed release and a new deployment. Pull requests are reviewed, but merging one
never authorizes a contract transaction.

## What is welcome

- **Security reports** — privately, through **Security → Report a vulnerability**. See [`SECURITY.md`](SECURITY.md).
- **Issues** for anything else you find: a mismatch between the code and what the README says, a build that does not
  reproduce, a link that does not resolve. Include the commit you built and, for on-chain behaviour, a transaction hash.

## What a change needs

- **Tests.** A change to `src/` comes with its tests; `bash script/check-contracts.sh` must pass, and `--stress`
  before anything that touches funds.
- **Pins.** Every dependency is a submodule pinned by commit. A new pin is deliberate, recorded in `lib-versions.md`
  with its commit and reason.
- **Sources.** `source-manifest.json` records every `src/` file's SHA-256; update it with the reviewed change.

## Building

```sh
git clone --recurse-submodules https://github.com/mercuri-finance/mercuri-earn-contracts.git
cd mercuri-earn-contracts
forge build
bash script/check-contracts.sh
```

`forge build` uses the pinned toolchain in `foundry.toml` and the pinned submodules under `lib/`. The contract gate also
needs Python 3; it checks the source manifest, formatting, NatSpec and the record writer's offline self-test, then runs
the tests and the gas snapshot.
