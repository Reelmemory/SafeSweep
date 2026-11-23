# SafeSweep v0 security review

Review checkpoint: **2026-11-18**.

## Trust model

- The guardian may emit the emergency signal but cannot select or change the evacuation destination.
- The safe wallet is immutable once the vault is deployed.
- Only the configured Reactive callback path may execute `sweep()`.
- The callback proxy and Reactive system are trusted network infrastructure for the hackathon deployment.

## Reviewed attack surfaces

### Forged sweep calls

`SafeSweepVault.sweep()` requires both the configured callback proxy  and the injected configured Reactive sender . Tests reject direct calls and callbacks carrying the wrong Reactive identity.

### Destination redirection

The guardian has no destination setter or destination argument. `safeWallet` is immutable, so a compromised guardian key can signal evacuation but cannot redirect funds.

### Replay, duplicate delivery, and reentrancy

`swept` is set before the external native transfer. Repeated or reentrant sweep attempts therefore fail. `SafeSweepReactive` also deduplicates source logs using `(chainId, txHash, logIndex)` so the same origin event requests at most one callback. Tests cover second-sweep rejection, duplicate Reactive log delivery, and a reentrant safe-wallet receiver.

### Constructor and configuration mistakes

Zero callback proxy, Reactive sender, guardian, safe wallet, and zero chain IDs are rejected. Reactive configuration is owner-only and one-shot. The live preflight verifies the expected chain IDs and deployed code at the Reactive system and callback proxy.

### Callback billing vs. protected funds

The vault authenticates the callback proxy and injected sender. Any nonzero fee request reverts, including requests from the proxy. Top up prepaid reserves with depositTo(vault) before panic. The vault has no coverDebt wrapper. The Reactive contract keeps its separate debt-settlement method.

### Failed destination transfer

If the destination rejects ETH, `SweepFailed` reverts the sweep and `swept` rolls back. This behavior is covered by a rejecting-receiver test. The EOA-only live-demo rule prevents this failure mode in the submission flow.

### Forced ETH after retirement

Normal deposits are rejected after `swept == true`. As with any EVM address, ETH may still be forced in through protocol mechanisms that bypass `receive()`. SafeSweep treats an evacuated vault as retired and should not be reused.
