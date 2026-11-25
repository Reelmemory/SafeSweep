# Create protection

Open [SafeSweep](https://safesweep-pj.vercel.app) in a browser with an Ethereum wallet extension, or in a wallet's browser that exposes an EIP-1193 provider. EIP-6963 wallet discovery is supported. WalletConnect QR pairing and native mobile deep links are not included.

1. Connect the account that will be your guardian. This account triggers panic.
2. Enter a separate receiving wallet that you control. The setup accepts addresses without deployed contract code. The guardian and receiving address are immutable.
3. Choose the protected amount and execution reserves. Defaults: 0.005 Base Sepolia ETH in the vault, 0.002 ETH in the callback reserve, and 0.5 lREACT in the Reactive execution reserve. Keep additional testnet funds for deployment and transaction gas.
4. Review each of the six transactions and approve it in your wallet. The app switches between Lasna (5318007) and Base Sepolia (84532), and waits for two confirmations before advancing.
5. Export your setup file. The app saves progress in this browser; the export restores it on another browser or device. It includes public addresses and transaction history, never private keys.
6. Once funded and configured, the guardian can trigger panic. Review the vault balance and permanent safe destination before approving. Reactive Network then handles the callback independently of the browser. Keep the page open or return later to follow the three receipts.

The lREACT helper reviews a request to Reactive's documented Base Sepolia faucet: 0.01 testnet ETH for 1 lREACT to the guardian. Delivery is asynchronous. The [Reactive funding guide](https://dev.reactive.network/reactive-mainnet) describes current faucet conditions.

## What is protected

Only native ETH deposited into the deployed Base Sepolia vault is evacuated. Connecting an account does not move or protect its wallet balance, ERC-20s or NFTs. The safe wallet must remain able to receive native ETH. Execution reserves are separate from the protected amount and may need topping up as network fees change.

After evacuation, the vault is retired and rejects new deposits. Use **Create protection** again to deploy a new vault. To protect another guardian account, switch accounts in your wallet and create a separate setup with its own safe destination.

## Interrupted setup

Submitted hashes are saved before confirmation handling. Reload and refresh to resume. If a wallet broadcast a transaction but did not return its hash, copy the hash from wallet activity into the recovery field. The app checks sender, recipient, input, value and nonce before accepting it.

For a sped-up transaction, recover its replacement hash. For a cancellation, enter the confirmed self-transfer cancellation hash and choose **Verify wallet cancellation**. Never clear a request merely because it is taking time. **Clear unsubmitted request** is available only without a known hash, after explicit wallet-activity confirmation and an unchanged account nonce.

An unavailable RPC leaves write controls disabled until chain state can be verified. Exported files are not authoritative about deployed settings: the app checks executable code, immutable addresses and subscription configuration on chain. Keep your latest export; restoring an older file can omit later transaction history. Do not erase browser data during an unresolved transaction.

## Verification boundary

The complete new browser flow is tested against two local Anvil chains, with actual contract deployment, wallet-provider simulation, panic, system reaction and callback delivery. Public deployed contract compatibility and the original public evacuation are checked separately. A fresh setup through a real wallet extension on public testnets remains a user-operated acceptance run; no new public setup was signed by the coding agent.

This is a testnet release. Reserves, RPCs and network infrastructure determine availability and timing; the app does not guarantee delivery latency or independently detect wallet compromise.
