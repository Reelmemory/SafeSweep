# Windows operator guide

Install Git for Windows, Python 3, Node.js and Foundry. Initialize the pinned library with `git submodule update --init lib/reactive-lib-omni`. If Windows' Python aliases are unavailable, set `SAFESWEEP_PYTHON` to your installed Python executable.

The existing public vault is already evacuated and retired. The normal workflow is read-only:

```powershell
.\scripts\safesweep.ps1 check
.\scripts\safesweep.ps1 proof -Manifest deployments\base-sepolia-20261124T163546Z.json
.\scripts\safesweep.ps1 apply-ui deployments\base-sepolia-20261124T163546Z.json
.\scripts\safesweep.ps1 serve-ui 4173
```

Save `BASE_SEPOLIA_RPC_URL` privately in `.env` (dRPC is recommended for archival reads), with `LASNA_RPC_URL=https://lasna-rpc.rnk.dev/`. The proof parser reads only RPC configuration and manifest location, never signer credentials. Existing environment variables take precedence over `.env`.

`proof`, `apply-ui`, `check` and `rehearse` run natively. The optional deployment and transaction commands still use Git for Windows Bash. They are not needed for this deployment.

`rehearse` starts two local Anvil chains, uses disposable local accounts, sends local transactions, runs the same receipt verifier, then stops both processes. Its hashes are not public evidence.

For a deliberately separate future deployment, review `.env.example` and the deployment guide. Use an encrypted dedicated testnet keystore; leave `PRIVATE_KEY` empty when using a keystore. Do not reuse the retired vault or run panic again to demonstrate the completed incident.
