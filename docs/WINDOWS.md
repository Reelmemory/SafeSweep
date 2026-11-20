# SafeSweep — Windows native setup

No Ubuntu/WSL is required for the dashboard and Solidity checks.

Install Python 3 and Windows Foundry (`forge`, `cast`, `anvil`), ensuring the commands are on your PATH. Open PowerShell in the extracted SafeSweepPJ folder.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\safesweep.ps1 check
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\safesweep.ps1 serve-ui 4173
```

Open http://localhost:4173. `init` and `wallet-import` are also available.

**Not yet Windows-native:** the two-chain rehearsal, live deployment, panic, and evidence commands. The Windows CLI refuses them explicitly; Bash versions remain unchanged. Do not attempt live deployment through this Windows CLI yet.
