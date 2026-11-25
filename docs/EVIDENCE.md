# Public evacuation evidence

Verified on 2026-11-25 using authenticated dRPC for Base Sepolia and the public Lasna RPC. No public transaction was sent during this investigation.

| Evidence | Result |
|---|---|
| Panic | `0x1d11119100c6463485a02bd9a9caddc2ecc8473c60c0c25875b6390b375ff1bb`, Base block 63083237 |
| Reactive execution | `0x9f48a4ccb2c0c94aee22cd75f4e9f245d27807b25eebafd9eec26b139d91eb59`, Lasna block 9151244 |
| Destination callback | `0x62397313018ba2bff751bc0b718281db47bb9aae6b6bf62fab4de8ae3275bf3f`, Base block 63083245 |
| Incident | `0x0d1f99b21c118c85e6a1fa8f82cb9e73c8296f1804c3bafdbb55a70ce7fe0f33` |
| Safe wallet | `0x061A4F1125D085aaB2B9fA2cb375768158A6F938` |
| Protected / swept | 5000000000000000 wei / 5000000000000000 wei |
| Beneficiary balance before / after callback block | 0 / 5000000000000000 wei |
| Final vault state | balance 0; swept true |
| Callback delivery registry | Empty, despite independently confirmed destination delivery |

[Manifest](../deployments/base-sepolia-20261124T163546Z.json) · [Raw proof report](../deployments/evidence/base-sepolia-20261124T163546Z-proof.json)

## Root cause

The earlier discovery script stopped after `getCallbacks(reactiveTxHash)` returned an empty array. It never searched Base for `FundsSwept`. The old verifier also required that registry entry even when all three receipts existed. This made supplemental delivery bookkeeping a mandatory condition and produced a false negative.

The lookup identifier and six-field return ABI were correct. The [official economy documentation](https://dev.reactive.network/economy) specifies the reactive transaction hash and says validators write these records after delivery. Empty means no recorded callback, not an execution failure. We have not established why Lasna's registry omitted this delivered callback.

The [RNK RPC reference](https://dev.reactive.network/rnk-rpc-methods) specifies a decimal block number for `rnk_getCallBackLogs`. At block 9151244 the actual Omni response contains the system's `CallbackRequest(uint256,address,address,uint8,bytes)` event. Its indexed fields are destination chain, requesting Reactive contract and recipient. Do not decode those topics using the legacy `Callback` layout shown in older examples.

## Reproduce on Windows

Privately set `BASE_SEPOLIA_RPC_URL` in `.env` or the environment. Environment settings take precedence. Use dRPC for reliable archival Base reads; never publish the authenticated URL.

```powershell
.\scripts\safesweep.ps1 proof -Manifest deployments\base-sepolia-20261124T163546Z.json
.\scripts\safesweep.ps1 apply-ui deployments\base-sepolia-20261124T163546Z.json
```

These commands require Python 3 and Foundry `cast`; no Bash, WSL, wallet or signing key is needed. Proof writes the manifest and a separate report atomically. It resets `proof_verified` before each attempt and marks unsuccessful verification as unconfirmed.

## Verification rules

1. Validate chain IDs, receipt status/hash and canonical block hashes.
2. Match the vault's indexed guardian and incident in `PanicTriggered`.
3. Match Lasna's `SweepRequested` to the exact origin transaction, incident and vault.
4. Match the system `CallbackRequest` and its entire ABI-encoded configuration: Base chain, vault, gas limit, `sweep(address,bytes32)` selector, injected-address placeholder and incident.
5. Query delivery bookkeeping using the reactive transaction hash. If absent, scan the destination using the full `FundsSwept` topic filter. Queries span at most 200 blocks and shrink on provider errors. Default total scan is bounded to 10,000 blocks; a miss reports the covered range and is not labelled a failed delivery. `base_scan_start_block` and Python's `--max-blocks` allow an intentional extended search.
6. Require the successful callback-proxy transaction and a vault-emitted `FundsSwept` for the exact safe wallet, incident and Reactive identity. A hash or `swept()` alone never passes.
7. Require at least 12 Base confirmations, positive protected amount, swept amount at least equal to the panic amount, immutable configuration matches, zero final vault balance and `swept=true` at one pinned snapshot.
8. Confirm the beneficiary's block balance increase. Concurrent beneficiary spending can make this check inconclusive; investigate a transfer trace instead of claiming a failure or weakening the check.

The report stores raw receipts, the callback-generation response, the registry result and pinned balance evidence without RPC URLs. Fixtures replay this actual deployment offline and corrupt individual fields to test rejection.

Local Anvil receipts are rehearsal artifacts, never public submission evidence. The earlier Ethereum Sepolia attempt remains unrelated and unverified.
