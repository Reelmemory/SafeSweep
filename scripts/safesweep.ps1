# SafeSweep native Windows entry point (PowerShell 5.1+)
param(
    [Parameter(Position=0)]
    [ValidateSet("help","init","check","rehearse","serve-ui","wallet-import","preflight","request-lreact","deploy","status","panic","proof","apply-ui")]
    [string]$Command = "help",
    [Parameter(Position=1)][string]$Argument = "",
    [Parameter(Position=2)][string]$CallbackHash = "",
    [string]$Manifest = ""
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root

function Require-Tool([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Missing '$Name'. Install it and restart PowerShell."
    }
}

function Run-External([string]$Exe, [string[]]$Arguments) {
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe failed (exit code $LASTEXITCODE)" }
}

function Get-Python {
    if ($env:SAFESWEEP_PYTHON) { return $env:SAFESWEEP_PYTHON }
    foreach ($Name in @("python", "python3", "py")) {
        $Tool = Get-Command $Name -ErrorAction SilentlyContinue
        if ($Tool) {
            try {
                $Version = & $Tool.Source --version 2>&1
                if ($LASTEXITCODE -eq 0 -and "$Version" -match '^Python 3\.') { return $Tool.Source }
            } catch { }
        }
    }
    throw "Install Python 3 or set SAFESWEEP_PYTHON to its executable path."
}

function Get-Manifest {
    if ($Manifest) { return $Manifest }
    if ($env:SAFESWEEP_DEPLOYMENT_MANIFEST) { return $env:SAFESWEEP_DEPLOYMENT_MANIFEST }
    $Latest = Get-ChildItem (Join-Path $Root "deployments\base-sepolia-*.json") |
        Where-Object { $_.BaseName -notlike '*-proof' } | Sort-Object Name -Descending | Select-Object -First 1
    if (!$Latest) { throw "No Base Sepolia deployment manifest found." }
    return $Latest.FullName
}

switch ($Command) {
    "help" {
        Write-Host "SafeSweep native Windows CLI"
        Write-Host "  .\scripts\safesweep.ps1 init"
        Write-Host "  .\scripts\safesweep.ps1 check"
        Write-Host "  .\scripts\safesweep.ps1 rehearse"
        Write-Host "  .\scripts\safesweep.ps1 serve-ui 4173"
        Write-Host "  .\scripts\safesweep.ps1 wallet-import"
        Write-Host ""
        Write-Host "Local contract checks and the full two-chain rehearsal are Windows-native."
        Write-Host "  .\scripts\safesweep.ps1 proof [-Manifest path.json]"
        Write-Host "  .\scripts\safesweep.ps1 apply-ui [manifest.json]"
        Write-Host "Proof and dashboard configuration run natively with Python 3 and Foundry cast."
        Write-Host "Transaction/deployment commands use Git for Windows Bash."
    }
    "init" {
        if (-not (Test-Path ".env")) {
            Copy-Item ".env.example" ".env"
            Write-Host "Created .env. Do not commit it."
        } else {
            Write-Host ".env already exists; unchanged."
        }
    }
    "check" {
        Require-Tool "forge"
        Run-External "forge" @("fmt","--check")
        Run-External "forge" @("build")
        Run-External "forge" @("test","-vv")
        Run-External (Get-Python) @("-m","unittest","discover","-s","test/evidence","-v")
        Require-Tool "node"
        Run-External "node" @("--test","test/web/proof.test.mjs")
        Run-External "node" @("--check","web/app.js")
        Write-Host "SafeSweep checks passed."
    }
    "rehearse" {
        Require-Tool "forge"
        Require-Tool "cast"
        Require-Tool "anvil"
        $Script = Join-Path $PSScriptRoot "local\rehearse.ps1"
        if (-not (Test-Path $Script)) {
            throw "Missing Windows rehearsal script: $Script"
        }
        & $Script
    }
    "serve-ui" {
        $Port = 4173
        if (!$Argument) { $Argument = "4173" }
        if ($Argument -notmatch '^\d+$') { throw "Port must be numeric." }
        $Port = [int]$Argument
        if ($Port -lt 1 -or $Port -gt 65535) { throw "Invalid port." }

        Run-External (Get-Python) @("-m","http.server","$Port","--directory","web","--bind","127.0.0.1")
    }
    "wallet-import" {
        Require-Tool "cast"
        Write-Host "Import only a dedicated testnet wallet. Never paste its key into chat."
        Run-External "cast" @("wallet","import","safesweep-testnet","--interactive")
    }
    "proof" {
        Require-Tool "cast"
        $Parameters = @("scripts/evidence/verify.py", (Get-Manifest))
        if ($Argument -or $CallbackHash) {
            if (!$Argument -or !$CallbackHash) { throw "Supply both reactive and callback hashes, or neither." }
            $Parameters += @($Argument, $CallbackHash)
        }
        Run-External (Get-Python) $Parameters
    }
    "apply-ui" {
        $Path = if ($Argument) { $Argument } else { Get-Manifest }
        Run-External (Get-Python) @("scripts/web/apply-manifest.py", $Path)
    }
    default {
        $Git = (Get-Command git -ErrorAction Stop).Source
        $Bash = Join-Path (Split-Path (Split-Path $Git)) "bin\bash.exe"
        if (!(Test-Path $Bash)) { throw "Install Git for Windows with Git Bash or run scripts/safesweep.sh from Git Bash." }
        $Parameters = @("scripts/safesweep.sh", $Command)
        if ($Argument) { $Parameters += $Argument }
        if ($CallbackHash) { $Parameters += $CallbackHash }
        Run-External $Bash $Parameters
    }
}
