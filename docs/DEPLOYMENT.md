# SafeSweep v0 deployment plan

Verified against Reactive Network's current Omni documentation on 2026-11-18.

## Networks

| Role | Network | Chain ID | Service address |
| --- | --- | ---: | --- |
| Origin event | Ethereum Sepolia | 11155111 | SafeSweepVault |
| Reactive execution | Reactive Lasna | 5318007 | System `0x8888888888888888888888888888888888888888` |
| Destination callback | Ethereum Sepolia | 11155111 | Proxy `0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4` |

Keeping origin and destination on Sepolia makes the proof easy to follow while still demonstrating the full cross-network Reactive path: Sepolia event -> Lasna reaction -> Sepolia callback.

For the v0 demo, the immutable safe wallet must be an **EOA**. This makes the final native-ETH transfer non-reverting and avoids a failed callback being billed while protected funds remain in the vault. Contract-wallet support is intentionally deferred until after the submission.

## Order

1. Run `scripts/deploy/00-preflight.sh`.
2. Deploy `SafeSweepReactive` on Lasna.
3. Deploy `SafeSweepVault` on Ethereum Sepolia with the Reactive address, callback proxy, guardian, and immutable safe wallet.
4. Call `SafeSweepReactive.configure()` once to subscribe to the vault's panic event and set the Sepolia callback recipient.
5. Fund Reactive execution reserves through `SYSTEM.depositTo(reactive)`.
6. Fund callback reserves through `CALLBACK_PROXY.depositTo(vault)`.
7. Fund the vault with demo Sepolia ETH.
8. Verify balances, reserves, debt, and `swept == false`.
9. Trigger `panic(bytes32)` using the guardian key.
10. Capture the origin transaction, Reactive transaction, and callback/destination transaction.

## Why callback reserves are separate

The vault's native balance is the protected balance. Callback fees are therefore funded into the callback proxy's accounting reserve for the vault instead of intentionally leaving fee money inside the vault. The sweep can move the protected balance to the safe wallet while the proxy has a separate source for callback billing.

## Callback gas

SafeSweep requests `350,000` gas for the callback. Current Reactive debugging guidance says callback requests below `100,000` are ignored; the SafeSweep limit is comfortably above that floor. The final deployed value should still be checked against actual callback execution and proxy overhead.

## Failure checks before the demo

- Reactive contract debt must be zero.
- Vault callback debt must be zero.
- Both service reserves must be nonzero.
- Vault must have code at the exact configured Sepolia address.
- The vault's immutable `_CALLBACK_SENDER` must equal the deployed Reactive address.
- The vault's `_SERVICE_PROVIDER` must equal the Sepolia callback proxy.
- `configured()` must be true on the Reactive contract.
- `swept()` must be false before the demo.
