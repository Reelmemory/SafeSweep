# SafeSweep demo runbook

## Core 30–60 second demo

The judge should understand the Reactive value before hearing product extensions.

### 0–10s — establish the starting state

Open the SafeSweep dashboard and the vault explorer page side by side.

- Vault is funded with demo Base Sepolia ETH.
- `swept == false`.
- Safe wallet is the immutable pre-approved destination.
- Reactive listener is configured on Lasna.

Say: **“This vault is protected while the owner is offline. There is no keeper or monitoring bot.”**

### 10–20s — emit the origin event

Connect the guardian wallet and trigger `panic(incidentId)`.

Show the confirmed Base Sepolia transaction and `PanicTriggered` event.

Say: **“The guardian only raises the alarm. This transaction does not move the funds.”**

### 20–40s — show Reactive doing the work

Switch to the Reactive transaction / callback evidence.

Show that `SafeSweepReactive.react()` observed the origin log and requested the authenticated callback.

Say: **“Reactive Network sees the event on Base Sepolia, evaluates it on Lasna, and requests the callback automatically. No second human transaction happens here.”**

### 40–60s — prove the destination result

Show the callback/destination transaction on Base Sepolia, then refresh the dashboard.

- Vault balance is `0`.
- `swept == true`.
- Safe wallet balance increased by the evacuated amount.
- Dashboard timeline shows `Origin Event → Reactive → Callback → Funds Safe`.

Say: **“That is the full proof: origin event, Reactive execution, destination callback, and the funds are safe.”**

## Under-3-minute submission script

### 0:00–0:20 — problem and one-line pitch

“Wallet compromises are often discovered after the owner is already too late. SafeSweep is a keeperless emergency fund-evacuation layer: when a high-signal panic event happens, Reactive Network automatically sweeps the remaining vault balance to an immutable safe wallet.”

### 0:20–0:40 — architecture

Show the architecture diagram.

“The guardian cannot redirect funds. The safe destination and authorized Reactive sender are immutable. The guardian only emits `PanicTriggered`. SafeSweepReactive subscribes to that event, deduplicates the origin log, and requests an authenticated callback into the vault.”

### 0:40–1:35 — live Reactive loop

1. Show the funded Base Sepolia vault and `swept == false`.
2. Trigger guardian panic.
3. Open the confirmed origin transaction.
4. Show the Reactive transaction/callback request on Lasna.
5. Show the Base Sepolia callback transaction.
6. Refresh the dashboard and show the empty retired vault plus the safe-wallet increase.

Narration:

“This first hash is the origin event. This second transaction is Reactive doing the autonomous work on Lasna. This third hash is the destination callback. The vault is now empty, marked swept, and rejects future deposits.”

### 1:35–2:05 — why Reactive matters

“Without Reactive, this needs an always-on bot, keeper, or a human who notices the compromise and sends another transaction. Here the reaction path is on-chain and autonomous after the trigger.”

### 2:05–2:30 — safety properties

“Direct sweep calls fail. The callback must come through the configured proxy and from the configured Reactive contract. The sweep is one-shot, duplicate origin logs are suppressed, reentrancy cannot sweep twice, and a rejecting destination rolls the whole sweep back.”

### 2:30–2:50 — proof and close

Show the README proof section or deployment manifest with all three public hashes.

“SafeSweep is intentionally small: one trigger, one asset, one immutable destination, one Reactive loop. Set it, forget it, and when it matters, the funds move themselves.”

## Evidence capture checklist

Before recording the final video, have these tabs ready:

- SafeSweep dashboard.
- Base Sepolia vault address.
- Base Sepolia safe-wallet address.
- Lasna Reactive contract address.
- Origin panic transaction.
- Reactive transaction/callback record.
- Destination callback transaction.
- README proof section.

Do not use local Anvil transaction hashes in the submission. Only real Lasna/Base Sepolia hashes count as evidence.
