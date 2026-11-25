# SafeSweep web app

Static HTML/CSS/ES modules. `index.html` creates and manages individual users' testnet vaults. `demo.html` preserves the original public evacuation dashboard. No server signs transactions or holds keys; each write goes through an injected EIP-1193 wallet. EIP-6963 discovers multiple providers. QR pairing is not included.

## Build and serve

```sh
npm ci
forge build
npm run build:web
python3 -m http.server 4173 -d web
```

The browser build exports ABI, creation/runtime bytecode and immutable locations from Solidity 0.8.29 artifacts to `contracts.json`, and vendors pinned ethers 6.17.0 with its license. Commit generated assets together with source changes. Serve over HTTPS outside localhost; cross-tab wallet coordination requires Web Locks.

Publish only the static files listed in `scripts/web/release-files.mjs`. No authenticated RPC endpoints, `.env` or signing keys belong in the web directory. The app uses public Base Sepolia and Lasna RPCs.

## Setup and recovery

See [Create protection](../docs/CREATE-PROTECTION.md). A setup is a versioned JSON record saved in localStorage and exported by the user. It includes immutable addresses, chosen amounts, pending action/nonce/hash, transaction history and incident scan cursors. Imports verify deployed bytecode and contract bindings. No private keys are stored. Progress cannot be automatically recovered from a lost browser without the export; retain it after setup and significant actions.

The UI requires verified reserves and zero service debt before deposits or panic. All three incident receipts and their payloads must correlate before **Evacuation verified** appears, with 13 Base confirmations and an empty retired vault. Each log request spans at most 200 blocks, with bounded work and persisted cursors. RPC failure disables writes.

## Tests

- `npm test`: pure proof, validation and recovery regressions.
- `npm run test:protection`: real browser + two isolated Anvil chains; six setup transactions through a simulated wallet, recovery, import, guards and full evacuation. Requires Anvil, built artifacts and Playwright.
- `node scripts/web/check-public-protection.mjs`: read-only runtime/configuration and receipt validation of the existing public demo using the new engine.
- `npm run test:browser`: original `/demo.html` proof and guardian regressions. Add `-- --live` for real RPC reads.

`SAFESWEEP_PLAYWRIGHT` selects an existing Playwright installation. `SAFESWEEP_BROWSER=chromium` uses installed bundled Chromium for the protection test; otherwise Edge is the default. `SAFESWEEP_PROTECTION_URL` runs the local-chain rehearsal against deployed frontend assets. It still intercepts public RPC reads and routes simulated wallet writes exclusively to local Anvil.

To update the original demo evidence only, use `scripts/web/apply-manifest.py`. It updates `config.js` and `proof.json`; it does not alter users' independent setup records.
