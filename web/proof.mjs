// Canonical event hashes: indexed modifiers affect topic layout, not topic0.
export const topics = {
  panic: "0x50440308ed8801ee8f31d9a0886cd946dd315b378605aa1befe4714e3a94c692",
  request: "0x24a60e06984d7b28e7201fe0fd616b0c75dbb3267bec85ee492f0532a78987d5",
  callback: "0xef94dbc611c4b95bf4b8ba34b413972180c2faf26fbb480befacedd83e07b133",
  sweep: "0xbdfa2d83f62e4cc807e5c16d71e80d7c6651265745bb7ba4aa997c1fbf6372ea",
};
const same = (a, b) => typeof a === "string" && typeof b === "string" && a.toLowerCase() === b.toLowerCase();
const word = (value) => `0x${BigInt(value).toString(16).padStart(64, "0")}`;
function require(value, message) { if (!value) throw new Error(message); }

function event(receipt, hash, address, expectedTopics) {
  require(receipt && BigInt(receipt.status) === 1n && same(receipt.transactionHash, hash), "Receipt missing, failed or mismatched");
  const logs = receipt.logs.filter(log => same(log.address, address) && log.topics.length === expectedTopics.length &&
    log.topics.every((value, i) => same(value, expectedTopics[i])));
  require(logs.length === 1, "Matching incident event missing or ambiguous");
  const log = logs[0];
  require(!log.removed && same(log.transactionHash, hash) && same(log.blockHash, receipt.blockHash), "Event is removed or inconsistent");
  return log;
}

export function verifyOrigin(receipt, config, guardian) {
  const { proof, addresses } = config;
  require(same(receipt?.to, addresses.vault) && same(receipt?.from, guardian), "Panic caller/target mismatch");
  const log = event(receipt, proof.panicTx, addresses.vault, [topics.panic, word(guardian), word(proof.incidentId)]);
  require(/^0x[\da-f]{64}$/i.test(log.data) && BigInt(log.data) > 0n, "Invalid protected amount");
  return BigInt(log.data);
}

export function verifyReaction(receipt, config) {
  const { proof, addresses } = config;
  event(receipt, proof.reactiveTx, addresses.reactive, [topics.request, word(proof.incidentId), word(proof.panicTx), word(addresses.vault)]);
  const request = event(receipt, proof.reactiveTx, addresses.system, [topics.callback, word(84532), word(addresses.reactive), word(addresses.vault)]);
  // ABI: (version, bytes configuration), where configuration encodes one dynamic tuple.
  const payload = `8a738683${"0".repeat(64)}${proof.incidentId.slice(2).toLowerCase()}`;
  const fields = [0, 64, 288, 32, 84532, addresses.vault, 350000, 128, 68];
  const expected = `0x${fields.map(value => word(value).slice(2)).join("")}${payload}${"0".repeat(56)}`;
  require(same(request.data, expected), "Callback payload does not match this incident");
  if (receipt.refTx) require(same(receipt.refTx, proof.panicTx) && BigInt(receipt.refChainId) === 84532n, "Reactive origin mismatch");
  return true;
}

export function verifyDestination(receipt, config, safe, protectedWei) {
  const { proof, addresses } = config;
  require(same(receipt?.to, addresses.callbackProxy), "Callback proxy mismatch");
  const log = event(receipt, proof.callbackTx, addresses.vault, [topics.sweep, word(safe), word(proof.incidentId), word(addresses.reactive)]);
  require(/^0x[\da-f]{64}$/i.test(log.data), "Invalid swept amount");
  const amount = BigInt(log.data);
  require(protectedWei > 0n && amount >= protectedWei, "Swept amount inconsistent with panic");
  if (proof.amountWei) require(amount === BigInt(proof.amountWei), "Amount differs from published proof");
  return amount;
}

export function canPanic(state, chainId) {
  return !state.demo && state.ready && !state.swept && !state.proof.panicTx &&
    !state.signing && !state.submitted && BigInt(state.balanceWei || 0) > 0n &&
    state.chainId === chainId && same(state.account, state.guardian);
}
