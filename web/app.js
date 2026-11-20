import { config } from "./config.js";

const $ = (id) => document.getElementById(id);
const ZERO = "0x0000000000000000000000000000000000000000";
const selectors = {
  guardian: "0x452a9320",
  safeWallet: "0x88cfce56",
  swept: "0x2113eaca",
  panic: "0x1e18bd66",
};

const state = {
  account: null,
  chainId: null,
  guardian: config.demo.guardian,
  safeWallet: config.demo.safeWallet,
  vault: config.addresses.vault !== ZERO ? config.addresses.vault : config.demo.vault,
  reactive: config.addresses.reactive !== ZERO ? config.addresses.reactive : config.demo.reactive,
  balanceEth: config.demo.balanceEth,
  swept: false,
  proof: { ...config.proof },
  demo: config.demoMode || config.addresses.vault === ZERO,
};

function short(address) {
  if (!address || address.length < 10) return "—";
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

function txUrl(kind, hash) {
  if (!hash) return null;
  return kind === "reactive"
    ? `${config.reactive.explorer}/tx/${hash}`
    : `${config.origin.explorer}/tx/${hash}`;
}

function addressUrl(kind, address) {
  if (!address || address === ZERO) return null;
  return kind === "reactive"
    ? `${config.reactive.explorer}/address/${address}`
    : `${config.origin.explorer}/address/${address}`;
}

function activityItem(iconClass, icon, title, subtitle, status, link = null) {
  return `<div class="activity-item">
    <span class="activity-icon ${iconClass}">${icon}</span>
    <div><strong>${title}</strong><span>${subtitle}</span>${link ? `<a class="tx-anchor" href="${link}" target="_blank" rel="noreferrer">View transaction ↗</a>` : ""}</div>
    <time>${status}</time>
  </div>`;
}

function renderActivity() {
  const items = [];
  const balance = Number.parseFloat(state.balanceEth || "0");
  if (balance > 0 || state.swept) {
    items.push(activityItem("deposit", "↓", "Vault funded", state.swept ? "Protected balance was evacuated" : `${state.balanceEth} ETH protected`, state.swept ? "Complete" : "Ready"));
  }

  if (state.proof.panicTx) {
    items.push(activityItem("alert", "!", "PanicTriggered emitted", "Guardian emergency signal recorded on Sepolia", "Origin", txUrl("origin", state.proof.panicTx)));
  }
  if (state.proof.reactiveTx) {
    items.push(activityItem("reactive", "◈", "Reactive callback requested", "Lasna evaluated the event autonomously", "Reactive", txUrl("reactive", state.proof.reactiveTx)));
  }
  if (state.proof.callbackTx) {
    items.push(activityItem("safe", "✓", "Funds swept to safe wallet", "Authenticated callback completed on Sepolia", "Safe", txUrl("origin", state.proof.callbackTx)));
  } else if (state.proof.panicTx && !state.swept) {
    items.push(activityItem("watch", "◉", "Callback pending", "Waiting for Reactive Network delivery", "Pending"));
  } else if (!state.proof.panicTx) {
    items.push(activityItem("watch", "◉", "Reactive listener armed", "Waiting for PanicTriggered", "Live"));
  }

  const footer = !state.proof.panicTx && !state.swept
    ? '<div class="empty-incident"><span>No emergency incident has been triggered.</span></div>'
    : "";
  $("activityList").innerHTML = items.join("") + footer;
}

function toast(message) {
  const node = $("toast");
  node.textContent = message;
  node.classList.add("show");
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => node.classList.remove("show"), 2100);
}

function render() {
  $("balanceValue").textContent = state.balanceEth;
  $("guardianShort").textContent = short(state.guardian);
  $("safeWalletShort").textContent = short(state.safeWallet);
  $("guardianCopy").dataset.copy = state.guardian;
  $("safeWalletCopy").dataset.copy = state.safeWallet;
  $("vaultShort").textContent = state.demo ? "Pending live deploy" : short(state.vault);
  $("vaultSub").textContent = state.demo ? "Demo address shown above" : "Protected contract";
  $("reactiveShort").textContent = state.demo ? "Pending live deploy" : short(state.reactive);
  $("demoChip").textContent = state.demo ? "Demo state" : "Live deployment";

  const vaultExplorer = $("vaultExplorer");
  const reactiveExplorer = $("reactiveExplorer");
  if (!state.demo) {
    vaultExplorer.href = addressUrl("origin", state.vault);
    reactiveExplorer.href = addressUrl("reactive", state.reactive);
    vaultExplorer.classList.remove("hidden");
    reactiveExplorer.classList.remove("hidden");
  } else {
    vaultExplorer.classList.add("hidden");
    reactiveExplorer.classList.add("hidden");
  }

  const emptyVault = Number.parseFloat(state.balanceEth || "0") === 0 && !state.swept;
  const pending = Boolean(state.proof.panicTx) && !state.swept;

  if (state.swept) {
    $("protectionEyebrow").textContent = "Funds evacuated";
    $("heroState").textContent = "Swept";
    $("heroSubstate").textContent = "Vault retired safely";
    $("panicButton").disabled = true;
    $("panicHint").textContent = "This vault has already been evacuated";
    document.querySelectorAll(".loop-step").forEach((node) => node.classList.add("active"));
  } else {
    const isGuardian = state.account && state.guardian && state.account.toLowerCase() === state.guardian.toLowerCase();
    if (pending) {
      $("protectionEyebrow").textContent = "Emergency signal received";
      $("heroState").textContent = "Evacuation pending";
      $("heroSubstate").textContent = "Waiting for Reactive callback";
      $("panicButton").disabled = true;
      $("panicHint").textContent = "Panic is already on-chain · callback pending";
      document.querySelector('[data-step="panic"]').classList.add("active");
    } else if (emptyVault) {
      $("protectionEyebrow").textContent = "Protection armed";
      $("heroState").textContent = "Vault empty";
      $("heroSubstate").textContent = "Fund the vault to activate protection";
      $("panicButton").disabled = true;
      $("panicHint").textContent = "There are no protected funds to evacuate";
    } else {
      $("protectionEyebrow").textContent = "Protection armed";
      $("heroState").textContent = "Monitoring";
      $("heroSubstate").textContent = "Reactive listener ready";
      $("panicButton").disabled = state.demo || !isGuardian || state.chainId !== config.origin.chainId;
      $("panicHint").textContent = state.demo
        ? "Live deployment required to trigger"
        : !state.account
          ? "Connect the guardian wallet to enable"
          : state.chainId !== config.origin.chainId
            ? "Switch wallet to Ethereum Sepolia"
            : isGuardian
              ? "Guardian verified · on-chain transaction required"
              : "Connected wallet is not the configured guardian";
    }
  }

  renderActivity();

  if (state.account) {
    $("connectButton").textContent = short(state.account);
  }
}

async function copyAddress(event) {
  const value = event.currentTarget.dataset.copy;
  if (!value) return;
  await navigator.clipboard.writeText(value);
  toast("Address copied");
}

async function rpc(method, params = []) {
  if (!window.ethereum) throw new Error("No injected wallet found");
  return window.ethereum.request({ method, params });
}

function decodeAddress(hex) {
  if (!hex || hex === "0x") return null;
  return `0x${hex.slice(-40)}`;
}

function decodeBool(hex) {
  return BigInt(hex || "0x0") !== 0n;
}

function weiToEth(weiHex) {
  const wei = BigInt(weiHex);
  const whole = wei / 10n ** 18n;
  const fraction = (wei % 10n ** 18n).toString().padStart(18, "0").slice(0, 4);
  return `${whole}.${fraction}`;
}

async function readContract(selector) {
  return rpc("eth_call", [{ to: state.vault, data: selector }, "latest"]);
}

async function refreshLiveState() {
  if (state.demo || !window.ethereum) {
    render();
    return;
  }
  try {
    const [balance, guardianHex, safeHex, sweptHex] = await Promise.all([
      rpc("eth_getBalance", [state.vault, "latest"]),
      readContract(selectors.guardian),
      readContract(selectors.safeWallet),
      readContract(selectors.swept),
    ]);
    state.balanceEth = weiToEth(balance);
    state.guardian = decodeAddress(guardianHex);
    state.safeWallet = decodeAddress(safeHex);
    state.swept = decodeBool(sweptHex);
    render();
  } catch (error) {
    console.error(error);
    toast("Could not refresh contract state");
  }
}

async function connectWallet() {
  try {
    const accounts = await rpc("eth_requestAccounts");
    state.account = accounts[0] || null;
    state.chainId = Number(BigInt(await rpc("eth_chainId")));
    render();
    await refreshLiveState();
    toast(state.demo ? "Wallet connected · demo UI" : "Wallet connected");
  } catch (error) {
    console.error(error);
    toast(error?.message || "Wallet connection rejected");
  }
}

async function makeIncidentId() {
  const material = `${state.account}-${Date.now()}-${crypto.randomUUID()}`;
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(material));
  return `0x${[...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("")}`;
}

async function triggerPanic() {
  if (state.demo || !state.account) return;
  try {
    const incidentId = await makeIncidentId();
    const data = `${selectors.panic}${incidentId.slice(2)}`;
    const txHash = await rpc("eth_sendTransaction", [{ from: state.account, to: state.vault, data }]);
    state.proof.panicTx = txHash;
    toast("Panic signal submitted");
    render();
    const loop = $("loopTrack");
    loop.classList.add("progress");
    document.querySelector('[data-step="panic"]').classList.add("active");
  } catch (error) {
    console.error(error);
    toast(error?.message || "Panic transaction rejected");
  }
}

$("connectButton").addEventListener("click", connectWallet);
$("guardianCopy").addEventListener("click", copyAddress);
$("safeWalletCopy").addEventListener("click", copyAddress);
$("refreshButton").addEventListener("click", async () => {
  await refreshLiveState();
  toast("State refreshed");
});
$("panicButton").addEventListener("click", triggerPanic);

if (window.ethereum) {
  window.ethereum.on?.("accountsChanged", ([account]) => {
    state.account = account || null;
    render();
  });
  window.ethereum.on?.("chainChanged", (chainHex) => {
    state.chainId = Number(BigInt(chainHex));
    render();
    refreshLiveState();
  });
}

render();
