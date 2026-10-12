# Dependencies (public Git submodules, pinned by commit)

| Path | Package | Version |
| --- | --- | --- |
| `lib/openzeppelin-contracts` | OpenZeppelin/openzeppelin-contracts | v5.4.0, `c64a1edb67b6e3f4a15cca8909c9482ad33a02b0` |
| `lib/forge-std` | foundry-rs/forge-std | `5e3854938622a1bc23906020aedc8ce6df61be59` (1.16.2 and later) |

Clone with `git clone --recurse-submodules`, or run `git submodule update --init --recursive` in a checkout;
`git submodule status` shows the pins. They are the same commits the Mercurifi Agent Accounts contracts pin, so every
Mercurifi contract set on Arc builds against one OpenZeppelin release.

## Reproducible source identity

| Item | Identity |
| --- | --- |
| `src/` (vault, interface) | sha256 in `source-manifest.json`, checked by `script/check-local-source.py` |

Build with Solidity 0.8.26, Cancun, via-IR and the per-path optimizer profiles in `foundry.toml`. The executable used
for the release evidence identifies itself as Foundry 1.4.3-Homebrew, build timestamp `2025-10-22T03:58:23Z`; it
reports `VERGEN_IDEMPOTENT_OUTPUT` instead of an upstream commit. Its SHA-256 is
`7a91e6efdcbb02203367c2c8c7e54928b7d1f3c6e636f7393c73b6201a9020c6`.
