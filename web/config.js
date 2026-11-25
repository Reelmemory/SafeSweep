export const config = {
  appName: "SafeSweep",
  demoMode: false,
  origin: {
    name: "Base Sepolia",
    chainId: 84532,
    chainIdHex: "0x14a34",
    explorer: "https://sepolia.basescan.org",
  },
  reactive: {
    name: "Reactive Lasna",
    chainId: 5318007,
    explorer: "https://lasna.reactscan.net",
  },
  addresses: {
    vault: "0xc46b8F28703FDAAD9086381F04A992a40C67c410",
    reactive: "0xe74f95108958baa4E5ECBbaa72e294C4fc4CDa96",
    callbackProxy: "0x476F44b11F5C942c58f4c8E3d0300E5710743585",
    system: "0x8888888888888888888888888888888888888888",
  },
  proof: {
    panicTx: "0x1d11119100c6463485a02bd9a9caddc2ecc8473c60c0c25875b6390b375ff1bb",
    reactiveTx: "0x9f48a4ccb2c0c94aee22cd75f4e9f245d27807b25eebafd9eec26b139d91eb59",
    callbackTx: "0x62397313018ba2bff751bc0b718281db47bb9aae6b6bf62fab4de8ae3275bf3f",
    incidentId: "0x0d1f99b21c118c85e6a1fa8f82cb9e73c8296f1804c3bafdbb55a70ce7fe0f33",
    amountWei: "5000000000000000",
    verified: true,
  },
  demo: {
    balanceEth: "0.0000",
    vault: "0xc46b8F28703FDAAD9086381F04A992a40C67c410",
    reactive: "0xe74f95108958baa4E5ECBbaa72e294C4fc4CDa96",
    guardian: "0xDdcEd26B1c66f9964C0934CACC82551BDEE0Dc25",
    safeWallet: "0x061A4F1125D085aaB2B9fA2cb375768158A6F938",
  },
};
