param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $Root

function Require-Tool([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Missing '$Name'. Install it and restart PowerShell."
    }
}

function Invoke-Capture {
    param([string]$Exe,[string[]]$Arguments)
    $output = & $Exe @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "$Exe failed (exit code $LASTEXITCODE)`n$output"
    }
    return $output.Trim()
}

function Invoke-Quiet {
    param([string]$Exe,[string[]]$Arguments)
    & $Exe @Arguments *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "$Exe failed (exit code $LASTEXITCODE)"
    }
}

function Wait-Rpc([string]$Rpc) {
    for ($i = 0; $i -lt 60; $i++) {
        try {
            $id = Invoke-Capture "cast" @("chain-id","--rpc-url",$Rpc)
            if ($id) { return }
        } catch {}
        Start-Sleep -Milliseconds 150
    }
    throw "Local RPC did not start: $Rpc"
}

function Parse-DeployedAddress([string]$Text) {
    $m = [regex]::Match($Text, 'Deployed to:\s*(0x[0-9a-fA-F]{40})')
    if (-not $m.Success) { throw "Could not parse deployed contract address.`n$Text" }
    return $m.Groups[1].Value
}

function Parse-TxHash([string]$Text) {
    $patterns = @(
        'transactionHash\s+(0x[0-9a-fA-F]{64})',
        '"transactionHash"\s*:\s*"(0x[0-9a-fA-F]{64})"',
        '(0x[0-9a-fA-F]{64})'
    )
    foreach ($pattern in $patterns) {
        $m = [regex]::Match($Text, $pattern)
        if ($m.Success) { return $m.Groups[1].Value }
    }
    throw "Could not parse transaction hash.`n$Text"
}

function Big([string]$Value) {
    Add-Type -AssemblyName System.Numerics -ErrorAction SilentlyContinue
    return [System.Numerics.BigInteger]::Parse($Value.Trim())
}

Require-Tool "forge"
Require-Tool "cast"
Require-Tool "anvil"

$LasnaPort = 18545
$SepoliaPort = 18546
$LasnaRpc = "http://127.0.0.1:$LasnaPort"
$SepoliaRpc = "http://127.0.0.1:$SepoliaPort"

$LasnaChainId = "5318007"
$SepoliaChainId = "84532"
$ReactiveSystem = "0x8888888888888888888888888888888888888888"
$CallbackProxy = "0x476F44b11F5C942c58f4c8E3d0300E5710743585"

# Standard Anvil account #0. LOCAL REHEARSAL ONLY.
$PrivateKey = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
$Guardian = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
$SafeWallet = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"

$ReactiveReserveWei = "1000000000000000000"
$CallbackReserveWei = "100000000000000000"
$VaultDemoWei = "10000000000000000"

$Temp = Join-Path ([System.IO.Path]::GetTempPath()) ("safesweep-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force $Temp | Out-Null

$LasnaOut = Join-Path $Temp "lasna.out.log"
$LasnaErr = Join-Path $Temp "lasna.err.log"
$SepoliaOut = Join-Path $Temp "sepolia.out.log"
$SepoliaErr = Join-Path $Temp "sepolia.err.log"

$LasnaProcess = $null
$SepoliaProcess = $null

try {
    Write-Host "== boot local target chains =="
    $LasnaProcess = Start-Process -FilePath "anvil" `
        -ArgumentList @("--chain-id",$LasnaChainId,"--port","$LasnaPort","--silent") `
        -RedirectStandardOutput $LasnaOut -RedirectStandardError $LasnaErr -PassThru -WindowStyle Hidden

    $SepoliaProcess = Start-Process -FilePath "anvil" `
        -ArgumentList @("--chain-id",$SepoliaChainId,"--port","$SepoliaPort","--silent") `
        -RedirectStandardOutput $SepoliaOut -RedirectStandardError $SepoliaErr -PassThru -WindowStyle Hidden

    Wait-Rpc $LasnaRpc
    Wait-Rpc $SepoliaRpc

    Write-Host "== install local Reactive system + callback proxy mocks =="
    $mockSystemOutput = Invoke-Capture "forge" @(
        "create","test/mocks/MockSystem.sol:MockSystem",
        "--rpc-url",$LasnaRpc,"--private-key",$PrivateKey,"--broadcast"
    )
    $MockSystem = Parse-DeployedAddress $mockSystemOutput

    $mockProxyOutput = Invoke-Capture "forge" @(
        "create","test/mocks/MockCallbackProxy.sol:MockCallbackProxy",
        "--rpc-url",$SepoliaRpc,"--private-key",$PrivateKey,"--broadcast"
    )
    $MockProxy = Parse-DeployedAddress $mockProxyOutput

    $SystemCode = Invoke-Capture "cast" @("code",$MockSystem,"--rpc-url",$LasnaRpc)
    $ProxyCode = Invoke-Capture "cast" @("code",$MockProxy,"--rpc-url",$SepoliaRpc)

    Invoke-Quiet "cast" @("rpc","anvil_setCode",$ReactiveSystem,$SystemCode,"--rpc-url",$LasnaRpc)
    Invoke-Quiet "cast" @("rpc","anvil_setCode",$CallbackProxy,$ProxyCode,"--rpc-url",$SepoliaRpc)

    Write-Host "== deploy SafeSweep Reactive contract =="
    $reactiveOutput = Invoke-Capture "forge" @(
        "create","src/SafeSweepReactive.sol:SafeSweepReactive",
        "--rpc-url",$LasnaRpc,"--private-key",$PrivateKey,"--broadcast"
    )
    $Reactive = Parse-DeployedAddress $reactiveOutput

    Write-Host "== deploy protected SafeSweep vault =="
    $vaultOutput = Invoke-Capture "forge" @(
        "create","src/SafeSweepVault.sol:SafeSweepVault",
        "--rpc-url",$SepoliaRpc,"--private-key",$PrivateKey,"--broadcast",
        "--constructor-args",$CallbackProxy,$Reactive,$Guardian,$SafeWallet
    )
    $Vault = Parse-DeployedAddress $vaultOutput

    Write-Host "== configure Reactive subscription =="
    Invoke-Capture "cast" @(
        "send",$Reactive,
        "configure(uint256,address,uint256,address)",
        $SepoliaChainId,$Vault,$SepoliaChainId,$Vault,
        "--rpc-url",$LasnaRpc,"--private-key",$PrivateKey
    ) | Out-Null

    $configured = Invoke-Capture "cast" @("call",$Reactive,"configured()(bool)","--rpc-url",$LasnaRpc)
    if ($configured.Trim() -ne "true") { throw "Reactive contract did not configure correctly." }

    Write-Host "== fund execution reserves + protected vault =="
    Invoke-Capture "cast" @(
        "send",$ReactiveSystem,"depositTo(address)",$Reactive,
        "--value",$ReactiveReserveWei,"--rpc-url",$LasnaRpc,"--private-key",$PrivateKey
    ) | Out-Null

    Invoke-Capture "cast" @(
        "send",$CallbackProxy,"depositTo(address)",$Vault,
        "--value",$CallbackReserveWei,"--rpc-url",$SepoliaRpc,"--private-key",$PrivateKey
    ) | Out-Null

    Invoke-Capture "cast" @(
        "send",$Vault,"--value",$VaultDemoWei,
        "--rpc-url",$SepoliaRpc,"--private-key",$PrivateKey
    ) | Out-Null

    $vaultBalance = Invoke-Capture "cast" @("balance",$Vault,"--rpc-url",$SepoliaRpc)
    if ((Big $vaultBalance) -ne (Big $VaultDemoWei)) {
        throw "Vault funding mismatch. Expected $VaultDemoWei wei, got $vaultBalance."
    }

    Write-Host "== guardian panic =="
    $Incident = (Invoke-Capture "cast" @("keccak","safesweep-windows-local-rehearsal")).Trim()
    $SafeBefore = Big (Invoke-Capture "cast" @("balance",$SafeWallet,"--rpc-url",$SepoliaRpc))

    $panicOutput = Invoke-Capture "cast" @(
        "send",$Vault,"panic(bytes32)",$Incident,
        "--rpc-url",$SepoliaRpc,"--private-key",$PrivateKey
    )
    $PanicTx = Parse-TxHash $panicOutput

    Write-Host "== simulate Reactive Network event delivery =="
    $Topic0 = (Invoke-Capture "cast" @("call",$Reactive,"PANIC_TOPIC_0()(uint256)","--rpc-url",$LasnaRpc)).Split()[0]
    $GuardianUint = (Invoke-Capture "cast" @("to-dec",$Guardian)).Trim()

    Invoke-Quiet "cast" @("rpc","anvil_impersonateAccount",$ReactiveSystem,"--rpc-url",$LasnaRpc)
    Invoke-Quiet "cast" @("rpc","anvil_setBalance",$ReactiveSystem,"0x3635C9ADC5DEA00000","--rpc-url",$LasnaRpc)

    $LogTuple = "($SepoliaChainId,$Vault,$Topic0,$GuardianUint,$Incident,0,0x,0,3,0,$PanicTx,0)"
    $reactOutput = Invoke-Capture "cast" @(
        "send",$Reactive,
        "react((uint256,address,uint256,uint256,uint256,uint256,bytes,uint256,uint256,uint256,uint256,uint256))",
        $LogTuple,
        "--rpc-url",$LasnaRpc,"--from",$ReactiveSystem,"--unlocked"
    )
    $ReactiveTx = Parse-TxHash $reactOutput

    $callbackCount = (Invoke-Capture "cast" @(
        "call",$ReactiveSystem,"callbackCount()(uint256)","--rpc-url",$LasnaRpc
    )).Split()[0]
    if ($callbackCount -ne "1") { throw "Expected exactly one callback request; got $callbackCount." }

    $callbackRecipient = (Invoke-Capture "cast" @(
        "call",$ReactiveSystem,"lastCallbackRecipient()(address)","--rpc-url",$LasnaRpc
    )).Trim()
    if ($callbackRecipient.ToLowerInvariant() -ne $Vault.ToLowerInvariant()) {
        throw "Callback recipient mismatch."
    }

    Write-Host "== simulate destination callback proxy =="
    $callbackOutput = Invoke-Capture "cast" @(
        "send",$CallbackProxy,
        "deliver(address,address,bytes32)",$Vault,$Reactive,$Incident,
        "--rpc-url",$SepoliaRpc,"--private-key",$PrivateKey
    )
    $CallbackTx = Parse-TxHash $callbackOutput

    Invoke-Capture "cast" @(
        "send",$ReactiveSystem,"setDeliveredCallbackTx(uint256)",$CallbackTx,
        "--rpc-url",$LasnaRpc,"--private-key",$PrivateKey
    ) | Out-Null

    $SafeAfter = Big (Invoke-Capture "cast" @("balance",$SafeWallet,"--rpc-url",$SepoliaRpc))
    $VaultAfter = Big (Invoke-Capture "cast" @("balance",$Vault,"--rpc-url",$SepoliaRpc))
    $Swept = (Invoke-Capture "cast" @("call",$Vault,"swept()(bool)","--rpc-url",$SepoliaRpc)).Trim()
    $Delta = $SafeAfter - $SafeBefore

    if ($Delta -ne (Big $VaultDemoWei)) { throw "Safe wallet received $Delta wei; expected $VaultDemoWei." }
    if ($VaultAfter -ne [System.Numerics.BigInteger]::Zero) { throw "Vault still holds $VaultAfter wei." }
    if ($Swept -ne "true") { throw "Vault swept() returned '$Swept'." }

    Write-Host "== verify three-link callback record =="
    $callbackRecord = Invoke-Capture "cast" @(
        "call",$ReactiveSystem,
        "getCallbacks(uint256)((uint256,address,uint256,uint256,uint256,bytes)[])",
        $ReactiveTx,"--rpc-url",$LasnaRpc
    )
    if ([string]::IsNullOrWhiteSpace($callbackRecord) -or $callbackRecord.Trim() -eq "[]") {
        throw "Reactive callback record was not created."
    }

    Write-Host "== verify correlated local receipts with the production verifier =="
    Invoke-Quiet "cast" @("rpc","anvil_mine","0xc","--rpc-url",$SepoliaRpc)
    $LocalManifest = Join-Path $Temp "local-rehearsal.json"
    @{
        project = "SafeSweep"; evidence_kind = "local-rehearsal"
        origin = @{ chain_id = 84532 }; reactive_network = @{ chain_id = 5318007 }
        vault_contract = $Vault; reactive_contract = $Reactive
        guardian = $Guardian; safe_wallet = $SafeWallet
        callback_proxy = $CallbackProxy; reactive_system = $ReactiveSystem
        panic_tx = $PanicTx; incident_id = $Incident
    } | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $LocalManifest
    $PreviousBaseRpc = $env:BASE_SEPOLIA_RPC_URL
    $PreviousLasnaRpc = $env:LASNA_RPC_URL
    try {
        $env:BASE_SEPOLIA_RPC_URL = $SepoliaRpc
        $env:LASNA_RPC_URL = $LasnaRpc
        & (Join-Path $Root "scripts\safesweep.ps1") proof $ReactiveTx $CallbackTx -Manifest $LocalManifest
    } finally {
        $env:BASE_SEPOLIA_RPC_URL = $PreviousBaseRpc
        $env:LASNA_RPC_URL = $PreviousLasnaRpc
    }

    Write-Host ""
    Write-Host "SafeSweep Windows local rehearsal: PASS" -ForegroundColor Green
    Write-Host "  Reactive:      $Reactive"
    Write-Host "  Vault:         $Vault"
    Write-Host "  Panic tx:      $PanicTx"
    Write-Host "  Reactive tx:   $ReactiveTx"
    Write-Host "  Callback tx:   $CallbackTx"
    Write-Host "  Swept amount:  $Delta wei"
    Write-Host "  Vault balance: $VaultAfter"
    Write-Host "  swept:         $Swept"
    Write-Host ""
    Write-Host "These are local Anvil transaction hashes, not submission evidence."
}
finally {
    if ($LasnaProcess -and -not $LasnaProcess.HasExited) {
        Stop-Process -Id $LasnaProcess.Id -Force -ErrorAction SilentlyContinue
    }
    if ($SepoliaProcess -and -not $SepoliaProcess.HasExited) {
        Stop-Process -Id $SepoliaProcess.Id -Force -ErrorAction SilentlyContinue
    }
    $ResolvedTemp = [System.IO.Path]::GetFullPath($Temp)
    $TempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (!$ResolvedTemp.StartsWith($TempRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path $ResolvedTemp -Leaf) -notlike 'safesweep-*') {
        throw "Refusing cleanup outside the SafeSweep temporary directory."
    }
    Remove-Item -LiteralPath $ResolvedTemp -Recurse -Force -ErrorAction SilentlyContinue
}
