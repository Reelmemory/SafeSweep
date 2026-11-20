# SafeSweep deployment runbook

SafeSweep v0 uses **Ethereum Sepolia** as both origin and destination and **Reactive Lasna** for the reactive contract.

## Recommended operator flow

Use the project CLI rather than calling the numbered scripts directly:

```bash
./scripts/safesweep.sh init
```

Edit `.env` and set:

- `SEPOLIA_RPC_URL`
- `GUARDIAN_ADDRESS`
- `SAFE_WALLET_ADDRESS`

The recommended signer is an encrypted Foundry keystore account named `safesweep-testnet`. Import a **dedicated testnet-only key** locally:

```bash
./scripts/safesweep.sh wallet-import
```

The private key is entered through Foundry's hidden terminal prompt and is not stored in `.env`.

Then validate the network and signer:

```bash
./scripts/safesweep.sh preflight
```

If that account still needs Lasna lREACT:

```bash
./scripts/safesweep.sh request-lreact
```

Deploy Reactive, deploy the vault, configure the subscription, fund service reserves, and fund the protected demo vault:

```bash
./scripts/safesweep.sh deploy
```

The live deployment is written to `deployments/live-<timestamp>.json`. Deployment deliberately **does not** trigger panic.

When ready to create submission evidence:

```bash
./scripts/safesweep.sh panic
```

After locating the corresponding Lasna Reactive transaction and Sepolia callback transaction, finalize and verify the proof:

```bash
./scripts/safesweep.sh proof 0x<reactive-tx> 0x<callback-tx>
./scripts/safesweep.sh apply-ui
```

The numbered scripts remain available individually for debugging and recovery.

## Current network constants

- Ethereum Sepolia chain ID: `11155111`
- Lasna chain ID: `5318007`
- Reactive system contract: `0x8888888888888888888888888888888888888888`
- Ethereum Sepolia callback proxy: `0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4`
- Ethereum Sepolia lREACT faucet: `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`
- Lasna RPC: `https://lasna-rpc.rnk.dev/`

The callback reserve is funded via the callback proxy's `depositTo(vault)` rather than by leaving fee money in the protected vault. That separation lets the vault sweep its protected balance without depending on those funds for callback billing.

## Deployment order matters

`SafeSweepVault` permanently stores the authorized Reactive contract address, so deploy the Reactive contract first. Then deploy the vault with that address, then call `configure()` on the Reactive contract with the vault address.

Never use a production key for this demo. Use a dedicated testnet-only account and never commit `.env`.
