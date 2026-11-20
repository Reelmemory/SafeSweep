# SafeSweep v0 security review

Review checkpoint: **2026-11-18**.

## Trust model

- The guardian may emit the emergency signal but cannot select or change the evacuation destination.
- The safe wallet is immutable once the vault is deployed.
- Only the configured Reactive callback path may execute `sweep()`.
- The callback proxy and Reactive system are trusted network infrastructure for the hackathon deployment.

## Reviewed attack surfaces

### Forged sweep calls

`SafeSweepVault.sweep()` requires both the configured callback proxy (`onlyServiceProvider`) and the injected configured Reactive sender (`onlyCallbackSender`). Tests reject direct calls and callbacks carrying the wrong Reactive identity.

### Destination redirection

The guardian has no destination setter or destination argument. `safeWallet` is immutable, so a compromised guardian key can signal evacuation but cannot redirect funds.

### Replay, duplicate delivery, and reentrancy

`swept` is set before the external native transfer. Repeated or reentrant sweep attempts therefore fail. `SafeSweepReactive` also deduplicates source logs using `(chainId, txHash, logIndex)` so the same origin event requests at most one callback. Tests cover second-sweep rejection, duplicate Reactive log delivery, and a reentrant safe-wallet receiver.

### Constructor and configuration mistakes

Zero callback proxy, Reactive sender, guardian, safe wallet, and zero chain IDs are rejected. Reactive configuration is owner-only and one-shot. The live preflight verifies the expected chain IDs and deployed code at the Reactive system and callback proxy.

### Callback billing vs. protected funds

Reactive's callback proxy can call a recipient's inherited `pay(uint256)` when prepaid callback reserves are exhausted. Because the vault inherits `AbstractCallback`, that payment route is available only to the legitimate callback proxy.

Mitigations for v0:

1. Callback fees are prepaid externally with `callbackProxy.depositTo(vault)` rather than intentionally storing fee funds inside the vault.
2. The vault exposes no public `coverDebt()` wrapper, so arbitrary callers cannot spend protected funds to settle service debt. A dedicated test verifies that a `coverDebt()` call fails while the protected balance remains unchanged.
3. The live demo preflight requires the immutable safe wallet to be an EOA. A successful native-ETH sweep therefore cannot be rejected by destination contract logic; the full protected balance leaves the vault before callback billing occurs.
4. Status checks require zero callback debt before the demo trigger.

A production version should isolate callback fee payment from protected assets completely, for example with a dedicated callback controller / fee-payer contract.

### Failed destination transfer

If the destination rejects ETH, `SweepFailed` reverts the sweep and `swept` rolls back. This behavior is covered by a rejecting-receiver test. The EOA-only live-demo rule prevents this failure mode in the submission flow.

### Forced ETH after retirement

Normal deposits are rejected after `swept == true`. As with any EVM address, ETH may still be forced in through protocol mechanisms that bypass `receive()`. SafeSweep treats an evacuated vault as retired and should not be reused.
