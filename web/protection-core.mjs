import { Interface, AbiCoder, getAddress, parseEther, formatEther, toBeHex, id } from './vendor/ethers.js';
import { verifyOrigin, verifyReaction, verifyDestination, topics } from './proof.mjs';
export { formatEther };
export const NETWORKS = {
  base: { chainId: '0x14a34', chainName: 'Base Sepolia', nativeCurrency: { name: 'Sepolia ETH', symbol: 'ETH', decimals: 18 }, rpcUrls: ['https://sepolia.base.org'], blockExplorerUrls: ['https://sepolia.basescan.org'] },
  lasna: { chainId: '0x512577', chainName: 'Reactive Lasna', nativeCurrency: { name: 'Testnet REACT', symbol: 'lREACT', decimals: 18 }, rpcUrls: ['https://lasna-rpc.rnk.dev/'], blockExplorerUrls: ['https://lasna.reactscan.net'] },
};
export const SYSTEM = '0x8888888888888888888888888888888888888888';
export const PROXY = '0x476F44b11F5C942c58f4c8E3d0300E5710743585';
export const FAUCET = '0x2afaFD298b23b62760711756088F75B7409f5967';
const coder = AbiCoder.defaultAbiCoder();
const service = new Interface(['function depositTo(address)', 'function reserves(address) view returns(uint256)', 'function debt(address) view returns(uint256)', 'function request(address)']);
export const same = (a, b) => typeof a === 'string' && typeof b === 'string' && a.toLowerCase() === b.toLowerCase();
const check = (ok, message) => { if (!ok) throw new Error(message); };
const hashOK = value => /^0x[0-9a-f]{64}$/i.test(value || '');
export function hasWalletErrorCode(error, code) {
  const queue=[error],seen=new Set();
  while(queue.length && seen.size<24){
    const item=queue.shift();if(!item || typeof item!=='object' || seen.has(item))continue;
    seen.add(item);if(Number(item.code)===code)return true;
    for(const key of ['cause','error','data','originalError'])if(item[key])queue.push(item[key]);
  }
  return false;
}
const word = value => coder.encode(['uint256'], [BigInt(value)]);
export function amount(value) {
  check(typeof value === 'string' && /^(0|[1-9]\d*)(\.\d{1,18})?$/.test(value), 'Enter a positive amount with at most 18 decimal places.');
  const wei = parseEther(value);
  check(wei > 0n, 'Amount must be greater than zero.');
  return wei;
}
export function address(value) {
  const result = getAddress(value.trim());
  check(BigInt(result) !== 0n, 'The zero address cannot receive protection.');
  return result;
}
export function validateRecord(input) {
  check(input && input.version === 1 && input.network === 'base-sepolia-lasna', 'This is not a SafeSweep testnet setup file.');
  const d = structuredClone(input);
  d.guardian = address(d.guardian); d.safe = address(d.safe);
  check(!same(d.guardian, d.safe), 'Use a separate safe wallet, not the guardian wallet.');
  for (const key of ['reactive', 'vault']) if (d[key]) d[key] = address(d[key]);
  for (const key of ['protectedAmount', 'reactiveReserve', 'callbackReserve']) amount(d[key]);
  check(typeof d.id === 'string' && /^[a-zA-Z0-9-]{1,80}$/.test(d.id), 'Invalid setup identifier.');
  d.history = Array.isArray(d.history) ? d.history.filter(x => hashOK(x.hash) && NETWORKS[x.chain] && typeof x.kind === 'string') : [];
  if (d.pending) check(['reactive','vault','configure','reactiveReserve','callbackReserve','deposit','panic','faucet'].includes(d.pending.kind), 'Unknown pending operation.');
  if (d.incident) {
    check(hashOK(d.incident.id), 'Invalid incident identifier.');
    for (const key of ['panicTx','reactiveTx','callbackTx']) if (d.incident[key]) check(hashOK(d.incident[key]), 'Invalid proof hash.');
    for (const key of ['baseCursor','lasnaCursor']) check(Number.isSafeInteger(d.incident[key]) && d.incident[key] >= 0, 'Invalid incident scan cursor.');
  }
  return d;
}
export function createRecord(guardian, safe, values) {
  return validateRecord({ version: 1, network: 'base-sepolia-lasna', id: crypto.randomUUID(), guardian, safe,
    ...values, history: [], createdAt: new Date().toISOString() });
}
export async function publicRpc(chain, method, params = []) {
  const response = await fetch(NETWORKS[chain].rpcUrls[0], { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }), signal: AbortSignal.timeout(15000) });
  const data = await response.json();
  if (!response.ok || data.error) throw new Error(`${NETWORKS[chain].chainName}: ${data.error?.message || 'RPC unavailable'}`);
  return data.result;
}
function executable(code) {
  // Solidity's CBOR trailer contains source hashes; compare executable code.
  const bytes = Number.parseInt(code.slice(-4), 16) + 2;
  return bytes > 2 && bytes * 2 < code.length - 2 ? code.slice(0, -bytes * 2) : code;
}
export function runtimeMatches(actual, artifact) {
  if (!/^0x[0-9a-f]+$/i.test(actual)) return false;
  const mask = code => {
    for (const refs of Object.values(artifact.immutableReferences || {})) for (const { start, length } of refs) {
      code = code.slice(0, 2 + start * 2) + '0'.repeat(length * 2) + code.slice(2 + (start + length) * 2);
    }
    return executable(code).toLowerCase();
  };
  return mask(actual) === mask(artifact.runtime);
}

export class Protection {
  constructor(record, artifacts, { rpc = publicRpc, wallet, save = () => {} } = {}) {
    this.d = validateRecord(record); this.artifacts = artifacts; this.rpc = rpc; this.wallet = wallet; this.save = save;
    this.vaultABI = new Interface(artifacts.SafeSweepVault.abi);
    this.reactiveABI = new Interface(artifacts.SafeSweepReactive.abi);
  }
  persist() { this.save(structuredClone(this.d)); }
  async read(chain, target, abi, name, args = [], at = 'latest') {
    return abi.decodeFunctionResult(name, await this.rpc(chain, 'eth_call', [{ to: target, data: abi.encodeFunctionData(name, args) }, at]))[0];
  }
  async inspect() {
    const d = this.d;
    const ids = await Promise.all(['base','lasna'].map(c => this.rpc(c, 'eth_chainId')));
    check(BigInt(ids[0]) === 84532n && BigInt(ids[1]) === 5318007n, 'RPC network mismatch.');
    const s = { configured: false, swept: false, balance: 0n, reactiveReserve: 0n, callbackReserve: 0n, reactiveDebt: 0n, callbackDebt: 0n };
    if (d.reactive) {
      check(runtimeMatches(await this.rpc('lasna','eth_getCode',[d.reactive,'latest']), this.artifacts.SafeSweepReactive), 'Reactive contract code is not the supported SafeSweep version.');
      check(same(await this.read('lasna',d.reactive,this.reactiveABI,'owner'), d.guardian), 'Reactive owner does not match this setup.');
      s.configured = await this.read('lasna',d.reactive,this.reactiveABI,'configured');
      if (s.configured) {
        for (const [name, expected] of [['originChainId',84532n],['destinationChainId',84532n],['originVault',d.vault],['callbackRecipient',d.vault]]) {
          const value = await this.read('lasna',d.reactive,this.reactiveABI,name);
          check(typeof value === 'bigint' ? value === expected : same(value,expected), 'Reactive subscription configuration does not match this vault.');
        }
      }
      [s.reactiveReserve,s.reactiveDebt] = await Promise.all(['reserves','debt'].map(n=>this.read('lasna',SYSTEM,service,n,[d.reactive])));
    }
    if (d.vault) {
      check(d.reactive, 'The vault must have a Reactive contract.');
      check(runtimeMatches(await this.rpc('base','eth_getCode',[d.vault,'latest']),this.artifacts.SafeSweepVault), 'Vault code is not the supported SafeSweep version.');
      for (const [name, expected] of [['guardian',d.guardian],['safeWallet',d.safe],['_CALLBACK_SENDER',d.reactive],['_SERVICE_PROVIDER',PROXY]]) {
        check(same(await this.read('base',d.vault,this.vaultABI,name),expected), `Vault ${name} does not match this setup.`);
      }
      [s.swept,s.callbackReserve,s.callbackDebt] = await Promise.all([
        this.read('base',d.vault,this.vaultABI,'swept'), ...['reserves','debt'].map(n=>this.read('base',PROXY,service,n,[d.vault]))]);
      s.balance = BigInt(await this.rpc('base','eth_getBalance',[d.vault,'latest']));
    }
    this.snapshot = s;
    return s;
  }
  plan(kind) {
    const d = this.d; const from = d.guardian;
    const plan = (chain, tx, title) => ({ kind, chain, tx: { from, value: '0x0', ...tx }, title });
    if (kind === 'reactive') return plan('lasna',{data:this.artifacts.SafeSweepReactive.bytecode},'Deploy your Reactive listener');
    if (kind === 'vault') return plan('base',{data:this.artifacts.SafeSweepVault.bytecode + coder.encode(['address','address','address','address'],[PROXY,d.reactive,d.guardian,d.safe]).slice(2)},'Deploy your protected vault');
    if (kind === 'configure') return plan('lasna',{to:d.reactive,data:this.reactiveABI.encodeFunctionData('configure',[84532,d.vault,84532,d.vault])},'Connect the listener to your vault');
    if (kind === 'reactiveReserve') return plan('lasna',{to:SYSTEM,data:service.encodeFunctionData('depositTo',[d.reactive]),value:toBeHex(amount(d.reactiveReserve))},'Fund the Reactive execution reserve');
    if (kind === 'callbackReserve') return plan('base',{to:PROXY,data:service.encodeFunctionData('depositTo',[d.vault]),value:toBeHex(amount(d.callbackReserve))},'Fund the callback reserve');
    if (kind === 'deposit') return plan('base',{to:d.vault,data:'0x',value:toBeHex(amount(d.protectedAmount))},'Deposit protected testnet ETH');
    if (kind === 'panic') return plan('base',{to:d.vault,data:this.vaultABI.encodeFunctionData('panic',[d.incident.id])},'Trigger irreversible evacuation');
    if (kind === 'faucet') return plan('base',{to:FAUCET,data:service.encodeFunctionData('request',[d.guardian]),value:toBeHex(parseEther('0.01'))},'Request 1 lREACT with 0.01 Base Sepolia ETH');
    throw new Error('Unknown operation.');
  }
  async allowed(kind) {
    const s = await this.inspect(), d = this.d;
    check(!s.swept, 'This vault has been evacuated and is retired.');
    if (kind === 'reactive') check(!d.reactive, 'Listener already deployed.');
    if (kind === 'vault') check(d.reactive && !d.vault, 'Deploy the listener first; do not duplicate an existing vault.');
    if (kind === 'configure') check(d.vault && !s.configured, 'Vault missing or already configured.');
    if (['reactiveReserve','callbackReserve','deposit','panic'].includes(kind)) check(s.configured, 'Complete and verify configuration first.');
    if (['deposit','panic'].includes(kind)) check(s.reactiveReserve > 0n && s.callbackReserve > 0n && s.reactiveDebt === 0n && s.callbackDebt === 0n, 'Fund both execution reserves and clear service debt first.');
    if (kind === 'deposit') check(!d.incident, 'An incident is already in progress; deposits are disabled.');
    if (kind === 'panic') check(s.balance > 0n && !d.incident?.panicTx, 'No protected funds or panic already submitted.');
    const safeCode = await this.rpc('base','eth_getCode',[d.safe,'latest']);
    check(safeCode === '0x', 'This version requires a safe wallet with no deployed code.');
  }
  async connectChain(chain) {
    check(this.wallet, 'Install or open an Ethereum browser wallet.');
    const target=BigInt(NETWORKS[chain].chainId);
    if(BigInt(await this.wallet.request({method:'eth_chainId'}))!==target){
      try { await this.wallet.request({method:'wallet_switchEthereumChain',params:[{chainId:NETWORKS[chain].chainId}]}); }
      catch (error) {
        if (!hasWalletErrorCode(error,4902)) throw error;
        await this.wallet.request({method:'wallet_addEthereumChain',params:[NETWORKS[chain]]});
        if(BigInt(await this.wallet.request({method:'eth_chainId'}))!==target)
          await this.wallet.request({method:'wallet_switchEthereumChain',params:[{chainId:NETWORKS[chain].chainId}]});
      }
    }
    const accounts = await this.wallet.request({method:'eth_accounts'});
    check(same(accounts[0],this.d.guardian), 'Connect the guardian that started this setup.');
    check(BigInt(await this.wallet.request({method:'eth_chainId'})) === BigInt(NETWORKS[chain].chainId), 'Wallet is on the wrong network.');
  }
  async send(kind) {
    check(!this.d.pending, 'Resolve the pending transaction before starting another.');
    await this.allowed(kind);
    if (kind === 'panic') {
      const [base,lasna] = await Promise.all(['base','lasna'].map(c=>this.rpc(c,'eth_blockNumber')));
      this.d.incident = { id: id(crypto.randomUUID()), baseCursor:Number(BigInt(base)),lasnaCursor:Number(BigInt(lasna)) };
    }
    try {
    const p = this.plan(kind);
    await this.connectChain(p.chain);
    // Estimate before asking for a signature, including the value and constructor data.
    const gas = BigInt(await this.rpc(p.chain,'eth_estimateGas',[p.tx]));
    const gasPrice = BigInt(await this.rpc(p.chain,'eth_gasPrice'));
    const balance = BigInt(await this.rpc(p.chain,'eth_getBalance',[this.d.guardian,'latest']));
    check(balance >= BigInt(p.tx.value) + gas * gasPrice * 12n / 10n, `Insufficient ${NETWORKS[p.chain].nativeCurrency.symbol} for this amount and gas.`);
    // Recheck after RPC calls in case the user changed account/network meanwhile.
    await this.connectChain(p.chain);
    p.tx.gas = toBeHex(gas * 12n / 10n);
    p.nonce = await this.wallet.request({method:'eth_getTransactionCount',params:[this.d.guardian,'pending']});
    p.tx.nonce = p.nonce;
    this.d.pending = p; this.persist();
      const hash = await this.wallet.request({method:'eth_sendTransaction',params:[p.tx]});
      check(hashOK(hash),'Wallet returned an invalid transaction hash. Recover the hash before continuing.');
      this.d.pending.hash = hash; this.persist();
      return hash;
    } catch (error) {
      if (hasWalletErrorCode(error,4001) && !this.d.pending?.hash) { this.d.pending = null; if (kind === 'panic') this.d.incident = null; this.persist(); }
      if (!this.d.pending && kind === 'panic') this.d.incident = null;
      throw error;
    }
  }
  async reconcile(hash) {
    const p = this.d.pending;
    if (!p) return false;
    const expected = this.plan(p.kind);
    check(expected.chain === p.chain, 'Pending transaction network mismatch.');
    if (hash) check(hashOK(hash), 'Enter the transaction hash from your wallet activity.');
    const txHash = hash || p.hash;
    if (!txHash) return false;
    const tx = await this.rpc(p.chain,'eth_getTransactionByHash',[txHash]);
    check(tx && same(tx.from,this.d.guardian) && same(tx.to || '0x',expected.tx.to || '0x') &&
      same(tx.input || tx.data,expected.tx.data) && BigInt(tx.value) === BigInt(expected.tx.value), 'Transaction does not match the reviewed setup action.');
    if (p.nonce) check(BigInt(tx.nonce) === BigInt(p.nonce),'Transaction nonce does not match the pending action.');
    p.hash = txHash; this.persist();
    const receipt = await this.rpc(p.chain,'eth_getTransactionReceipt',[txHash]);
    if (!receipt) return false;
    check(same(receipt.transactionHash,txHash),'Receipt hash mismatch.');
    const block = await this.rpc(p.chain,'eth_getBlockByNumber',[receipt.blockNumber,false]);
    check(block?.hash === receipt.blockHash,'Transaction changed chain history; refresh before continuing.');
    if (BigInt(receipt.status) !== 1n) {
      this.d.history.push({kind:p.kind,chain:p.chain,hash:txHash,status:'reverted'});
      this.d.pending = null; if (p.kind === 'panic') this.d.incident = null; this.persist();
      throw new Error('Transaction reverted. No step was completed; review balances and retry.');
    }
    const head = BigInt(await this.rpc(p.chain,'eth_blockNumber'));
    if (head < BigInt(receipt.blockNumber) + 1n) return false;
    if (['reactive','vault'].includes(p.kind)) this.d[p.kind] = address(receipt.contractAddress);
    if (p.kind === 'panic') {
      this.d.incident.panicTx = txHash;
      this.d.incident.baseCursor = Number(BigInt(receipt.blockNumber));
    }
    // Persist the receipt/address before post-confirmation reads, so RPC failure cannot cause duplicate deployments.
    this.d.history.push({kind:p.kind,chain:p.chain,hash:txHash,block:Number(BigInt(receipt.blockNumber)),status:'confirmed'});
    this.d.pending = null; this.persist();
    await this.inspect();
    return true;
  }
  async cancelUnsent() {
    const p = this.d.pending;
    check(p && !p.hash, 'A submitted transaction cannot be discarded.');
    check(p.chain===this.plan(p.kind).chain && /^0x[0-9a-f]+$/i.test(p.nonce||''), 'The saved request is missing valid network or nonce information. Keep your setup export for recovery.');
    check(BigInt(await this.rpc(p.chain,'eth_chainId'))===BigInt(NETWORKS[p.chain].chainId),'RPC network mismatch. Request was not cleared.');
    const [latest,pending] = await Promise.all(['latest','pending'].map(tag=>this.rpc(p.chain,'eth_getTransactionCount',[this.d.guardian,tag])));
    check(BigInt(latest) === BigInt(p.nonce) && BigInt(pending) === BigInt(p.nonce), 'The account nonce has changed. Recover the transaction hash from wallet activity.');
    // Caller must explicitly confirm wallet activity contains no submitted transaction.
    this.d.pending = null; if(p.kind === 'panic') this.d.incident = null; this.persist();
  }
  async reconcileCancellation(hash) {
    const p=this.d.pending;
    check(p && hashOK(hash),'Enter the cancellation transaction hash from your wallet.');
    const tx=await this.rpc(p.chain,'eth_getTransactionByHash',[hash]);
    check(tx && same(tx.from,this.d.guardian) && same(tx.to,this.d.guardian) && BigInt(tx.value)===0n &&
      (tx.input||tx.data)==='0x' && BigInt(tx.nonce)===BigInt(p.nonce),'This is not a self-transfer cancellation of the pending nonce.');
    const receipt=await this.canonical(p.chain,hash);
    check(BigInt(await this.rpc(p.chain,'eth_blockNumber'))>=BigInt(receipt.blockNumber)+1n,'Wait for two confirmations of the wallet cancellation.');
    this.d.history.push({kind:p.kind,chain:p.chain,hash,status:'cancelled'});
    this.d.pending=null;if(p.kind==='panic')this.d.incident=null;this.persist();
  }
  proofConfig() {
    const d=this.d;
    return { addresses:{vault:d.vault,reactive:d.reactive,system:SYSTEM,callbackProxy:PROXY},proof:{...d.incident,incidentId:d.incident.id} };
  }
  async canonical(chain, hash) {
    const receipt=await this.rpc(chain,'eth_getTransactionReceipt',[hash]);
    check(receipt && BigInt(receipt.status)===1n,'Proof transaction is missing or reverted.');
    const block=await this.rpc(chain,'eth_getBlockByNumber',[receipt.blockNumber,false]);
    check(block?.hash===receipt.blockHash,'Proof receipt is not canonical.');
    return receipt;
  }
  async find(chain, target, filter, cursor, head) {
    // Five bounded requests per refresh; persist progress and overlap to tolerate reorgs.
    let current=cursor;
    for(let i=0;i<5 && current<=head;i++) {
      const end=Math.min(current+199,head);
      const logs=await this.rpc(chain,'eth_getLogs',[{address:target,topics:filter,fromBlock:toBeHex(current),toBlock:toBeHex(end)}]);
      const log=logs.find(l=>!l.removed);
      if(log) return {hash:log.transactionHash,cursor:current};
      current=end+1;
    }
    return {cursor:Math.max(cursor,current-12)};
  }
  async monitor() {
    const d=this.d, i=d.incident;
    if(!i?.panicTx) return {origin:false,reaction:false,delivery:false};
    const result={origin:false,reaction:false,delivery:false};
    const origin=await this.canonical('base',i.panicTx);
    const protectedWei=verifyOrigin(origin,this.proofConfig(),d.guardian); result.origin=true;
    const [baseHead,lasnaHead]=await Promise.all(['base','lasna'].map(async c=>Number(BigInt(await this.rpc(c,'eth_blockNumber')))));
    if(!i.reactiveTx) {
      const found=await this.find('lasna',d.reactive,[topics.request,word(i.id),word(i.panicTx),word(d.vault)],i.lasnaCursor,lasnaHead);
      i.lasnaCursor=found.cursor; if(found.hash)i.reactiveTx=found.hash; this.persist();
    }
    if(i.reactiveTx) { verifyReaction(await this.canonical('lasna',i.reactiveTx),this.proofConfig()); result.reaction=true; }
    if(!i.callbackTx) {
      const found=await this.find('base',d.vault,[topics.sweep,word(d.safe),word(i.id),word(d.reactive)],i.baseCursor,baseHead);
      i.baseCursor=found.cursor; if(found.hash)i.callbackTx=found.hash; this.persist();
    }
    if(i.callbackTx && result.reaction) {
      const callback=await this.canonical('base',i.callbackTx);
      const swept=verifyDestination(callback,this.proofConfig(),d.safe,protectedWei);
      check(BigInt(callback.blockNumber)>=BigInt(origin.blockNumber),'Callback precedes panic.');
      result.confirmations=baseHead-Number(BigInt(callback.blockNumber))+1;
      result.delivery=result.confirmations>=13 && this.snapshot.swept && this.snapshot.balance===0n;
      result.amount=formatEther(swept);
    }
    return result;
  }
}
