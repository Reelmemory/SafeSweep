# SafeSweep local validation

Validation checkpoint: **2026-11-25**.

## Result

- Full Solidity project compilation: **PASS**
- EVM test suite: **28 passed / 0 failed / 0 skipped**
- Two-chain Anvil deployment + evidence rehearsal: **PASS**
- Python evidence/manifest regressions: **21 passed**, including replay of the actual public receipts with an empty registry and rejection of stale/mislabelled proof exports.
- JavaScript proof/control regressions: **5 passed**.
- Browser fixture checks: desktop 1440px, tablet 768px, mobile 390px; no horizontal overflow or page errors.
- Browser public-RPC checks: all three layouts displayed verified evacuation from live receipts.
- Hosted production URL: `https://safesweep-pj.vercel.app`; all three layouts passed against the deployed assets.
- Captioned demonstration: 59.96 seconds, 1280×800 WebM, no audio; inspected a rendered frame and verified the recorded page's receipt checks.
- Wallet-provider simulation: guardian connect, wrong chain, wrong account, disconnect and rejected connection; zero sends.
- Public proof: 0.005 ETH delivered at Base block 63083245; safe wallet delta confirmed; vault zero and swept true.
- Reactive Omni dependency: pinned to `3ade0dcf1d27e67e5783ef807e73a1b9e0c0cce8`
- Source pragma / submission compiler target: Solidity `^0.8.29` / Foundry config `0.8.29`
- Locally compiled and tested with solc 0.8.29. The reserve isolation regression calls pay from the configured proxy.

## Covered behavior

The passing suite verifies configuration/subscription, owner-only one-shot configuration, native deposits, guardian-only panic, guardian inability to redirect the safe wallet, panic-without-custody movement, callback-proxy authentication, Reactive-sender authentication, direct fee-payment rejection, public `coverDebt()` absence, full native-balance evacuation, replay protection, duplicate origin-log suppression, reentrant safe-wallet behavior, rejecting-destination rollback, retired-vault deposit rejection, panic rejection after sweep, callback request payload construction, unrelated-log fall-through, unauthorized `react()` rejection, and zero-address/zero-chain configuration rejection.

The Windows rehearsal additionally validates local deployment, reserve funding, panic hash capture, Reactive callback construction, destination delivery and the production receipt verifier after mining 12 confirmations. MockSystem emits the real Omni CallbackRequest ABI. Local hashes remain test artifacts and are not submission evidence.

- The rehearsal used Anvil accounts. Live keystore signing remains an operator step.
