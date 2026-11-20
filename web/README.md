# SafeSweep dashboard

Dependency-free frontend for the hackathon demo. It works in two modes:

- **Demo state** before the live deployment addresses exist.
- **Live state** after `web/config.js` is updated with the real Sepolia vault and Lasna Reactive addresses and `demoMode` is set to `false`.

The live view reads `guardian()`, `safeWallet()`, `swept()`, and the vault native balance directly through an injected EIP-1193 wallet. A verified guardian on Ethereum Sepolia can submit `panic(bytes32)` from the dashboard.

Serve locally with:

```bash
python3 -m http.server 4173 -d web
```

After `ship-live.sh` creates a deployment manifest, switch the dashboard from demo mode to real addresses with:

```bash
./scripts/web/apply-manifest.py deployments/live-<timestamp>.json
```

Run the same command again after the manifest receives the three proof transaction hashes; the activity panel will surface explorer links automatically.
