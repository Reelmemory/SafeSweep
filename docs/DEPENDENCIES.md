# Dependency pins

SafeSweep intentionally pins external smart-contract dependencies for reproducible hackathon builds.

## Reactive Network Omni library

- Repository: `Reactive-Network/reactive-lib-omni`
- Commit: `3ade0dcf1d27e67e5783ef807e73a1b9e0c0cce8`
- Commit date: 2026-05-21
- Solidity: `^0.8.29`
- Vendored path: `lib/reactive-lib-omni/`

The vendored files are the complete Solidity source surface of that commit (`src/base` and `src/interfaces`).
The upstream repository also references `forge-std` for its own development, but SafeSweep's current tests do not depend on forge-std.

Do not replace this pin with `master` during the submission build. Update only after compiling and rerunning the full suite against the new commit.
