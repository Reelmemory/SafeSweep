# Deployment manifests

`ship-live.sh` writes a timestamped JSON manifest here after a successful real Lasna/Sepolia deployment.

The manifest contains **public on-chain information only**: chain IDs, contract addresses, guardian, safe wallet, and later the three proof transaction hashes. It never contains the deployment private key.

For the final submission, commit the successful live manifest after the panic → Reactive → callback transaction hashes have been filled in.
