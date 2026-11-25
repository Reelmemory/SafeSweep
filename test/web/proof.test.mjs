import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { config } from "../../web/config.js";
import { canPanic, verifyOrigin, verifyReaction, verifyDestination } from "../../web/proof.mjs";

const proof = JSON.parse(fs.readFileSync(new URL("../../deployments/evidence/base-sepolia-20261124T163546Z-proof.json", import.meta.url)));
const clone = value => structuredClone(value);

test("all three actual public receipts correlate", () => {
  const amount = verifyOrigin(proof.origin_receipt, config, config.demo.guardian);
  assert.equal(amount, 5000000000000000n);
  assert.equal(verifyReaction(proof.reactive_receipt, config), true);
  assert.equal(verifyDestination(proof.callback_receipt, config, config.demo.safeWallet, amount), amount);
});

test("swept state or a hash without a receipt cannot prove delivery", () => {
  for (const receipt of [null, { status: "0x0" }, { ...proof.callback_receipt, logs: [] }]) {
    assert.throws(() => verifyDestination(receipt, config, config.demo.safeWallet, 5000000000000000n));
  }
});

test("wrong safe wallet, incident, reactive identity and amount cannot prove delivery", () => {
  for (const field of ["safe", "incident", "reactive", "amount", "proxy"]) {
    const c = clone(config);
    let safe = config.demo.safeWallet;
    if (field === "safe") safe = "0x" + "12".repeat(20);
    if (field === "incident") c.proof.incidentId = "0x" + "12".repeat(32);
    if (field === "reactive") c.addresses.reactive = "0x" + "12".repeat(20);
    if (field === "amount") c.proof.amountWei = "1";
    if (field === "proxy") c.addresses.callbackProxy = "0x" + "12".repeat(20);
    assert.throws(() => verifyDestination(proof.callback_receipt, c, safe, 5000000000000000n), field);
  }
});

test("tampered callback payload and removed events are rejected", () => {
  const reaction = clone(proof.reactive_receipt);
  reaction.logs[1].data = reaction.logs[1].data.slice(0, -2) + "01";
  assert.throws(() => verifyReaction(reaction, config));
  const callback = clone(proof.callback_receipt);
  callback.logs.find(log => log.address.toLowerCase() === config.addresses.vault.toLowerCase()).removed = true;
  assert.throws(() => verifyDestination(callback, config, config.demo.safeWallet, 5000000000000000n));
});

test("panic requires guardian, correct chain, funded active vault and no existing incident", () => {
  const active = { demo: false, ready: true, swept: false, proof: {}, signing: false, submitted: null,
    balanceWei: "1", chainId: 84532, account: config.demo.guardian, guardian: config.demo.guardian };
  assert.equal(canPanic(active, 84532), true);
  for (const change of [{ demo: true }, { ready: false }, { swept: true }, { proof: { panicTx: "known" } },
    { signing: true }, { submitted: "pending" }, { balanceWei: "0" }, { chainId: 1 }, { account: null },
    { account: config.demo.safeWallet }]) assert.equal(Boolean(canPanic({ ...active, ...change }, 84532)), false);
});
