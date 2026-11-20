# SafeSweep local validation

Validation checkpoint: **2026-11-18**.

## Result

- Full Solidity project compilation: **PASS**
- EVM test suite: **27 passed / 0 failed / 0 skipped**
- Two-chain Anvil deployment + evidence rehearsal: **PASS**
- Reactive Omni dependency: pinned to `3ade0dcf1d27e67e5783ef807e73a1b9e0c0cce8`
- Source pragma / submission compiler target: Solidity `^0.8.29` / Foundry config `0.8.29`
- Sandbox validation compiler: bundled Solar `0.8.38` from Foundry nightly `1.9.1-nightly` (`6264e50149d8991fb40930e73bd924218f30b711`)

The sandbox uses the bundled Solar compiler because outbound compiler downloads are unavailable in this runtime. The repository remains pinned to Solidity 0.8.29 for normal Foundry/CI builds.

## Covered behavior

The passing suite verifies configuration/subscription, owner-only one-shot configuration, native deposits, guardian-only panic, guardian inability to redirect the safe wallet, panic-without-custody movement, callback-proxy authentication, Reactive-sender authentication, direct fee-payment rejection, public `coverDebt()` absence, full native-balance evacuation, replay protection, duplicate origin-log suppression, reentrant safe-wallet behavior, rejecting-destination rollback, retired-vault deposit rejection, panic rejection after sweep, callback request payload construction, unrelated-log fall-through, unauthorized `react()` rejection, and zero-address/zero-chain configuration rejection.

The local rehearsal additionally validates the live deployment launcher, reserve funding, panic hash capture, Reactive callback construction, destination delivery, three-hash proof-manifest verification, final zero vault balance, and `swept == true`. Local hashes remain test artifacts and are not submission evidence.

- Operator CLI + encrypted-keystore-compatible signer abstraction validated through the two-chain rehearsal.
