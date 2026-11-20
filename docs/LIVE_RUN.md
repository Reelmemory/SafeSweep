# SafeSweep live run — minimal operator checklist

The code path is already validated locally. The remaining live job is to create real Lasna/Sepolia evidence.

## One-time setup

```bash
./scripts/safesweep.sh init
./scripts/safesweep.sh wallet-import
```

Edit `.env` with a Sepolia RPC, the guardian address, and a separate EOA safe-wallet address. Use only a dedicated testnet wallet.

## Before deploying

```bash
./scripts/safesweep.sh preflight
```

If the deployment account needs Lasna lREACT:

```bash
./scripts/safesweep.sh request-lreact
```

## Deploy and fund

```bash
./scripts/safesweep.sh deploy
```

This deploys SafeSweepReactive on Lasna, deploys SafeSweepVault on Sepolia, configures the subscription/callback target, funds service reserves, funds the protected Sepolia ETH demo balance, and writes a deployment manifest.

## Create the incident proof

```bash
./scripts/safesweep.sh panic
```

The panic command records the Sepolia origin transaction in the deployment manifest. Reactive Network should then autonomously produce the Lasna reaction and Sepolia callback.

Once the Reactive and callback hashes are known:

```bash
./scripts/safesweep.sh proof 0x<reactive-tx> 0x<callback-tx>
./scripts/safesweep.sh apply-ui
```

A successful proof requires all three receipts, `swept == true`, vault balance `0`, and a Reactive callback record containing the destination transaction hash.

## Submission evidence

Keep these three real public hashes together:

1. Sepolia guardian panic transaction.
2. Lasna Reactive transaction.
3. Sepolia destination callback/sweep transaction.

Do not use the local Anvil hashes from `./scripts/safesweep.sh rehearse` as submission evidence.
