# SafeSweep dashboard

Static HTML/CSS/ES modules; no application dependencies or build step. `config.js` contains only public addresses and proof identifiers. Never place authenticated RPC URLs or keys here.

The dashboard reads the vault through public Base RPC without requiring a wallet. It independently fetches and checks all three canonical receipts, the incident fields and callback payload before showing **Evacuation verified**. A swept flag without a matching receipt is displayed as **Vault reports swept**. RPC outages fail closed and disable panic.

An injected EIP-1193 wallet is used only for connection and optional guardian panic on an active funded vault. The deployed demo vault is retired, so panic remains disabled. An operator applies a newly verified manifest to publish proof hashes for a different deployment.

```powershell
.\scripts\safesweep.ps1 apply-ui deployments\base-sepolia-20261124T163546Z.json
.\scripts\safesweep.ps1 serve-ui 4173
```

Publish `index.html`, `styles.css`, `app.js`, `proof.mjs`, `config.js` and `proof.json` as static files. The proof report is captured evidence; the success badge additionally checks live receipts.

Browser regression runner: `node scripts/web/check-browser.cjs` (requires Playwright and Edge). Add `--live` for public RPC verification. `SAFESWEEP_PLAYWRIGHT` can point to an existing Playwright installation; `SAFESWEEP_BROWSER` selects a browser channel. Wallet tests use a stub and send no public transactions.
