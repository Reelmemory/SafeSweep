# SafeSweep local validation

Validation checkpoint: **2026-11-25**.

## Result

- Full Solidity project compilation: **PASS**
- EVM test suite: **28 passed / 0 failed / 0 skipped**
- Two-chain Anvil deployment + evidence rehearsal: **PASS**
- Python evidence/manifest regressions: **21 passed**, including replay of the actual public receipts with an empty registry and rejection of stale/mislabelled proof exports.
- JavaScript proof/control/setup regressions: **18 passed**.
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

## Self-service browser release

The Connect wallet picker is covered with two announced wallet providers, duplicate-provider suppression, Escape dismissal, rejected wallet switches preserving the previous connection, successful switching, stale events from the previous provider, no-wallet guidance and legacy browser-wallet injection. Desktop and mobile picker screenshots use simulated providers. The full setup/evacuation rehearsal also uses the picker after page reloads.

Recovery regressions cover explicit rejection inside nested provider errors, unknown errors preserving no-hash state, disabled clear without user attestation, read-only clear with matching unused nonce, RPC failure leaving the request intact, inline recovery feedback surviving refresh, and successful clear restoring setup controls. Wallet rechecks use `eth_chainId` and only request a network switch when necessary. These tests do not emulate MetaMask's site-reputation scanner or establish that a security warning is a false positive.

`npm run test:protection` runs two isolated Anvil chains and a real browser. It deploys each user's contracts through the injected wallet interface, submits all six setup transactions, reloads with a pending hash, recovers a broadcast whose wallet response was lost, rejects wrong accounts/chains and signatures, exports/imports setup, checks modified bytecode/immutable destinations/service debt, and completes panic → reaction → callback with exactly 0.005 ETH received and a retired empty vault. Desktop, tablet and mobile layouts have no horizontal overflow or page errors. Local mocks stand in for network relay infrastructure; their hashes are never public proof.

The new engine also has unit regressions for malformed amounts/imports, receipt substitution, bounded 200-block scans, preparation errors and confirmed wallet cancellation. CI runs contract tests, evidence tests, frontend unit tests and the two-chain browser rehearsal. Public compatibility checks use `node scripts/web/check-public-protection.mjs` and never send a transaction. A fresh public setup signed by a real wallet extension has not been performed for this release.

The published root app passed that same full rehearsal with public RPC URLs intercepted and all simulated wallet transactions sent exclusively to local Anvil. Thirteen hosted HTML/CSS/JS/JSON/license assets matched the tested local files byte-for-byte by SHA-256; `deployments/dashboard.json` records their hashes and the Vercel deployment. The preserved `/demo.html` separately passed live public-receipt checks at 1440px, 768px and 390px with no page errors. Hosted testing caught and fixed a restore-before-initialization race; restore remains disabled until contract definitions load. CI uses Ubuntu 24.04 to match pinned Playwright's supported browser dependencies.
