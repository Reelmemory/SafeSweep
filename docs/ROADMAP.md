# SafeSweep shipping roadmap

This is the canonical build order. Completed items are struck through.

1. ~~Define the SafeSweep concept, problem, pitch, Reactive loop, demo scope, and submission requirements.~~
2. ~~Lock the v0 scope to one high-signal trigger: explicit guardian panic.~~
3. ~~Choose the v0 asset model: native currency only.~~
4. ~~Choose the v0 safety model: immutable pre-approved safe wallet.~~
5. ~~Define the architecture: panic → event → Reactive logic → callback → sweep → safe wallet.~~
6. ~~Create the sandbox project workspace and preserve `project.md` as the source of truth.~~
7. ~~Create the initial Foundry project configuration.~~
8. ~~Create `.env.example` and basic repository housekeeping files.~~
9. ~~Implement `SafeSweepVault.sol`.~~
10. ~~Implement `SafeSweepReactive.sol`.~~
11. ~~Write the initial architecture document and deployment sequence.~~
12. ~~Write the initial README.~~
13. ~~Make the contracts compile against the current Reactive Omni library.~~
14. ~~Install/pin the exact Reactive contract dependency and version.~~
15. ~~Add contract unit tests.~~
16. ~~Test vault funding and normal balance handling.~~
17. ~~Test that only the guardian can trigger panic.~~
18. ~~Test that panic itself cannot directly steal or redirect funds.~~
19. ~~Test callback-proxy authentication.~~
20. ~~Test Reactive-contract authentication.~~
21. ~~Test successful full-balance sweep to the safe wallet.~~
22. ~~Test replay/second-sweep protection.~~
23. ~~Add mocks needed for local Reactive/callback testing.~~
24. ~~Run the complete local test suite and fix every failing case.~~
25. ~~Add deployment scripts for `SafeSweepReactive`.~~
26. ~~Add deployment scripts for `SafeSweepVault`.~~
27. ~~Choose and document the exact origin testnet for the demo.~~
28. ~~Confirm current Lasna deployment requirements, callback proxy, chain IDs, and funding requirements.~~
29. ~~Create the deployment/configuration workflow connecting the vault and Reactive contract.~~
30. Deploy `SafeSweepReactive` to Lasna.
31. Deploy `SafeSweepVault` to the selected origin testnet.
32. Configure the Reactive subscription to the deployed vault.
33. Fund the Reactive contract for execution.
34. Fund the vault with demo funds.
35. Fund/configure the callback mechanism.
36. Run the first real guardian panic transaction.
37. Verify the `PanicTriggered` origin event on-chain.
38. Verify Reactive receives/processes the event.
39. Verify the destination callback executes.
40. Verify the vault balance is evacuated to the safe wallet.
41. Capture the origin transaction hash.
42. Capture the Reactive transaction/callback proof.
43. Capture the destination sweep transaction hash.
44. Verify all three hashes form the full provable Reactive loop.
45. ~~Build the SafeSweep frontend/dashboard.~~
46. ~~Create the main protected-vault overview screen.~~
47. ~~Show vault balance, guardian, safe wallet, protection state, and network information.~~
48. ~~Build the guardian panic interaction.~~
49. ~~Build the Reactive activity/status timeline.~~
50. ~~Show Origin Event → Reactive → Callback → Funds Safe visually.~~
51. ~~Add transaction explorer links for each stage.~~
52. ~~Add successful-sweep state and incident explanation.~~
53. Connect the frontend to the deployed smart contracts.
54. ~~Add wallet connection.~~
55. ~~Handle wrong-network, rejected-transaction, empty-vault, and callback-pending states.~~
56. ~~Create the polished responsive visual design.~~
57. ~~Run the frontend locally and provide ongoing visual/live previews.~~
58. Deploy the frontend to a public preview URL.
59. Perform an end-to-end test through the actual UI.
60. ~~Security-review the v0 contracts and attack surfaces.~~
61. ~~Check that the guardian can trigger evacuation but cannot alter the destination.~~
62. ~~Check that an attacker cannot directly invoke a valid sweep.~~
63. ~~Check constructor/configuration mistakes and zero-address cases.~~
64. ~~Check reentrancy, replay, callback authentication, and one-shot state handling.~~
65. ~~Clean up contract code and comments for judging.~~
66. ~~Improve the README so the opening immediately demonstrates Reactive's value.~~
67. ~~Add architecture diagrams and exact deployment instructions.~~
68. Add deployed addresses and network details to the README.
69. Add the three real transaction hashes to the README.
70. ~~Add reproducible setup, build, test, and deployment commands.~~
71. ~~Prepare the 30–60 second core demo flow.~~
72. ~~Write the full under-3-minute demo script.~~
73. Record/capture the demo evidence.
74. Prepare screenshots/explorer proof for backup judging evidence.
75. Do a final repository cleanup.
76. Confirm the public repo contains contracts, scripts, tests, docs, and no secrets.
77. Confirm deployed contract addresses are documented.
78. Confirm transaction hashes are documented.
79. Confirm the demo video is under three minutes.
80. ~~Confirm the README explains what Reactive enables that a normal contract cannot autonomously do.~~
81. ~~Confirm submission track: `Set It and Forget It`.~~
82. Run the final submission checklist from `project.md`.
83. Submit SafeSweep.
84. Only after submission, consider optional extensions.

## Current gate

The contract verification gate is clear: the full project compiles locally and the EVM suite passes **27/27 tests with 0 failures**. Dependency pinning, mocks, deployment Steps 25-29, and the demo-mode dashboard are complete. A two-chain Anvil rehearsal proves the deployment scripts and sweep path end-to-end. The active on-chain gate remains **Step 30: deploy `SafeSweepReactive` to real Lasna**; frontend Step 53 remains open until those real addresses are applied to the dashboard. Local transaction hashes are not submission proof.
