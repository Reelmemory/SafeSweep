# SafeSweep submission evidence

SafeSweep's judging proof is the three-link chain:

1. **Origin / Base Sepolia** — guardian calls `panic(bytes32)` and the vault emits `PanicTriggered`.
2. **Reactive / Lasna** — `SafeSweepReactive.react()` handles that origin log and requests the callback.
3. **Destination / Base Sepolia** — the callback proxy calls `SafeSweepVault.sweep()`, the vault emits `FundsSwept`, and the protected balance reaches the immutable safe wallet.

## Capture flow

After `ship-live.sh` succeeds, run:

```bash
./scripts/deploy/07-panic.sh
```

The script confirms the transaction and writes `panic_tx` plus `incident_id` into the latest deployment manifest.

Run `./scripts/safesweep.sh proof` for automatic discovery. Alternatively use Reactscan or Reactive Network's tracing tooling to identify the Lasna reactive transaction generated from the origin panic. The Reactive system records callbacks by that reactive transaction hash. Once the destination callback transaction is known, finalize the proof:

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

## Earlier Ethereum Sepolia attempt

The handoff identifies vault `0xCE122e247504bEcd2F62f1170aF59AEC721a8fe6` and Lasna contract `0xc46b8F28703FDAAD9086381F04A992a40C67c410`. The Lasna receipt at block 8775518 contains SweepRequested. No destination sweep was established for this run.

Lasna transaction: `0x3a0718add3a9d30b04de332dde4912032fd95ec28f77771e86a6caac116cd1f0`.

The indexed origin hash in that request is `0x37bcd365e15b3659efe0485a4f84d3586cb4b71d8504faedcd3d8804b1a7d4c5`.
