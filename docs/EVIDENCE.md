# SafeSweep submission evidence

SafeSweep's judging proof is the three-link chain:

1. **Origin / Sepolia** — guardian calls `panic(bytes32)` and the vault emits `PanicTriggered`.
2. **Reactive / Lasna** — `SafeSweepReactive.react()` handles that origin log and requests the callback.
3. **Destination / Sepolia** — the callback proxy calls `SafeSweepVault.sweep()`, the vault emits `FundsSwept`, and the protected balance reaches the immutable safe wallet.

## Capture flow

After `ship-live.sh` succeeds, run:

```bash
./scripts/deploy/07-panic.sh
```

The script confirms the transaction and writes `panic_tx` plus `incident_id` into the latest deployment manifest.

Use Reactscan or Reactive Network's tracing tooling to identify the Lasna reactive transaction generated from the origin panic. The Reactive system records callbacks by that reactive transaction hash. Once the destination callback transaction is known, finalize the proof:

```bash
./scripts/evidence/record-proof.sh \
  0x<reactive-transaction-hash> \
  0x<destination-callback-transaction-hash>
```

That verifier checks all three receipts, checks that the vault is `swept == true` with zero remaining balance, queries the Reactive system's callback record, and writes the Reactive and callback hashes into the deployment manifest.

## Official Reactive debugging references

- https://dev.reactive.network/debugging
- https://dev.reactive.network/economy
- https://dev.reactive.network/rnk-rpc-methods

Local Anvil hashes must never be used as submission evidence.
