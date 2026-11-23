# Windows operator guide

Install Git for Windows, Python 3 and Foundry. In Git Bash confirm that `python3 --version`, `forge --version` and `cast --version` work. PowerShell dispatches live commands through Git for Windows. The local PowerShell rehearsal runs natively.

From a fresh checkout initialize the pinned dependency and create the local configuration.

```powershell
git submodule update --init lib/reactive-lib-omni
.\scripts\safesweep.ps1 init
```

Set GUARDIAN_ADDRESS and SAFE_WALLET_ADDRESS in .env. Keep the encrypted testnet signer on this computer. Use a fresh checkout or review existing .env values against .env.example, particularly reserve and vault amounts. Old amounts override defaults. Leave PRIVATE_KEY empty when using the keystore.

```powershell
.\scripts\safesweep.ps1 deploy
.\scripts\safesweep.ps1 status
.\scripts\safesweep.ps1 panic
.\scripts\safesweep.ps1 proof
.\scripts\safesweep.ps1 apply-ui
.\scripts\safesweep.ps1 serve-ui 4173
```

Proof searches Lasna for the incident and polls the callback registry once. If pending, rerun proof after delivery. Publish the configured web directory on your static host. The generated deployment manifest contains public evidence.
