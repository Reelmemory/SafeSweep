# SafeSweep native Windows entry point (PowerShell 5.1+)
param(
    [Parameter(Position=0)]
    [ValidateSet("help","init","check","rehearse","serve-ui","wallet-import","preflight","request-lreact","deploy","status","panic","proof","apply-ui")]
    [string]$Command = "help",
    [Parameter(Position=1)][string]$Argument = "",
    [Parameter(Position=2)][string]$CallbackHash = ""
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
        Write-Host "Live commands use Git for Windows Bash, Windows Foundry and python3."
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

        if (Get-Command py -ErrorAction SilentlyContinue) {
            Run-External "py" @("-3","-m","http.server","$Port","--directory","web")
        } elseif (Get-Command python -ErrorAction SilentlyContinue) {
            Run-External "python" @("-m","http.server","$Port","--directory","web")
        } else {
            throw "Python 3 is required to serve the dashboard."
        }
    }
    "wallet-import" {
        Require-Tool "cast"
        Write-Host "Import only a dedicated testnet wallet. Never paste its key into chat."
        Run-External "cast" @("wallet","import","safesweep-testnet","--interactive")
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
