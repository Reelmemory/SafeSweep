export const config = {
  appName: "SafeSweep",
  demoMode: true,
  origin: {
    name: "Ethereum Sepolia",
    chainId: 11155111,
    chainIdHex: "0xaa36a7",
    explorer: "https://sepolia.etherscan.io",
  },
  reactive: {
    name: "Reactive Lasna",
    chainId: 5318007,
    explorer: "https://lasna.reactscan.net",
  },
  addresses: {
    vault: "0x0000000000000000000000000000000000000000",
    reactive: "0x0000000000000000000000000000000000000000",
    callbackProxy: "0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4",
    system: "0x8888888888888888888888888888888888888888",
  },
  proof: {
    panicTx: null,
    reactiveTx: null,
    callbackTx: null,
  },
  demo: {
    balanceEth: "0.0100",
    vault: "0x6F3A2b4D0F5C4A7b3a46A8F391F4e20F5aA218D1",
    reactive: "0x91D8B017c5D23D4dCc2a3D36a0D40b76fF02fFe2",
    guardian: "0x7B4A3c68d14726f37B4453cAb4F4d652a8cAd91A",
    safeWallet: "0x42E0C807f42130fE42dF00d5aD09b799A7b09884",
  },
};
