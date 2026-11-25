# SafeSweep v0 security review

Review checkpoint: **2026-11-25**. Deployed contract code was not changed during the evidence repair.

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

### Evidence and dashboard trust boundaries

Successful-looking state is not sufficient proof. Both the verifier and dashboard require the incident-correlated vault event in a successful callback-proxy receipt. Wrong chain, beneficiary, Reactive identity, payload, removed logs and failed receipts are rejected. The verifier also checks the beneficiary balance increase. Empty registry bookkeeping is reported separately from destination execution.

### Remaining v0 limitations

The guardian is an explicit manual alarm, not an automatic compromise detector. A compromised guardian can trigger early evacuation or emit repeated panic incidents before delivery, consuming execution reserves. The destination remains immutable, so the guardian cannot steal the funds through redirection. Reserve availability, RPC availability and Reactive infrastructure remain operational dependencies; there is no guaranteed latency or cancellation mechanism. Adding panic latching or changing these rules would require a separately approved new contract deployment.

The browser uses public RPCs and depends on their availability and honest responses. This is an engineering review and testnet demonstration, not an external security audit or a mainnet certification.

## Self-service browser setup

Each setup deploys the unchanged contracts using the connected guardian's wallet. The frontend validates chain IDs, supported executable bytecode (masking compiler immutable slots and metadata), owner/guardian/safe/proxy/listener addresses, subscription fields, reserve availability and service debt. The safe address must differ from the guardian and have no code when checked. These checks do not prove ownership of that address or prevent it from acquiring code later.

The browser stores public setup state and pending actions, never signing keys. An origin-wide Web Lock serializes wallet writes across tabs. Sender/network are rechecked before submission; recovery requires the expected sender, recipient, calldata, value and nonce plus canonical successful receipts. State is persisted before submission and immediately after a returned hash, with two confirmations before advancing. A confirmed zero-value self-transfer at the same nonce can resolve a wallet cancellation. Deeper reorganizations and edits or loss of local storage remain recovery risks; exports should be retained. An old backup may omit later history. Public provider availability and integrity are dependencies.

The UI blocks duplicate panic, deposits during an incident and reuse of a swept vault. These are UI safeguards, not new on-chain restrictions: the unchanged contract still permits repeated guardian panic before callback delivery. The app is explicitly testnet-only and protects vault deposits, not arbitrary assets held by the connected wallet.
