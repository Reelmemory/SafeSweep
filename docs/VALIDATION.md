# SafeSweep local validation

Validation checkpoint: **2026-11-23**.

## Result

- Full Solidity project compilation: **PASS**
- EVM test suite: **28 passed / 0 failed / 0 skipped**
- Two-chain Anvil deployment + evidence rehearsal: **PASS**
- Reactive Omni dependency: pinned to `3ade0dcf1d27e67e5783ef807e73a1b9e0c0cce8`
- Source pragma / submission compiler target: Solidity `^0.8.29` / Foundry config `0.8.29`
- Locally compiled and tested with solc 0.8.29. The reserve isolation regression calls pay from the configured proxy.

## Covered behavior

The passing suite verifies configuration/subscription, owner-only one-shot configuration, native deposits, guardian-only panic, guardian inability to redirect the safe wallet, panic-without-custody movement, callback-proxy authentication, Reactive-sender authentication, direct fee-payment rejection, public `coverDebt()` absence, full native-balance evacuation, replay protection, duplicate origin-log suppression, reentrant safe-wallet behavior, rejecting-destination rollback, retired-vault deposit rejection, panic rejection after sweep, callback request payload construction, unrelated-log fall-through, unauthorized `react()` rejection, and zero-address/zero-chain configuration rejection.

The local rehearsal additionally validates the live deployment launcher, reserve funding, panic hash capture, Reactive callback construction, destination delivery, three-hash proof-manifest verification, final zero vault balance, and `swept == true`. Local hashes remain test artifacts and are not submission evidence.

- The rehearsal used Anvil accounts. Live keystore signing remains an operator step.
