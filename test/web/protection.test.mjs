import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { Protection, amount, createRecord, validateRecord, runtimeMatches, hasWalletErrorCode } from '../../web/protection-core.mjs';
const artifacts=JSON.parse(fs.readFileSync(new URL('../../web/contracts.json',import.meta.url))).contracts;
const guardian='0x1111111111111111111111111111111111111111',safe='0x2222222222222222222222222222222222222222';
const draft=()=>createRecord(guardian,safe,{protectedAmount:'0.005',reactiveReserve:'0.5',callbackReserve:'0.002'});
test('amounts reject zero, negative, exponent and excess precision',()=>{
  for(const value of ['0','-1','1e9','0.0000000000000000001','Infinity','01',''])assert.throws(()=>amount(value));
  assert.equal(amount('0.005'),5000000000000000n);
});
test('setup forbids zero or same receiving wallet and wrong network imports',()=>{
  for(const bad of ['0x0000000000000000000000000000000000000000',guardian])assert.throws(()=>validateRecord({...draft(),safe:bad}));
  assert.throws(()=>validateRecord({...draft(),network:'mainnet'}));
});
test('runtime validation rejects bytecode mutation outside immutable slots',()=>{
  const artifact=artifacts.SafeSweepVault;
  assert.equal(runtimeMatches(artifact.runtime,artifact),true);
  assert.equal(runtimeMatches('0x00'+artifact.runtime.slice(4),artifact),false);
  assert.equal(runtimeMatches('0x',artifact),false);
});
test('pending action blocks any further send before network or wallet calls',async()=>{
  const d=draft();d.pending={kind:'reactive'};
  const p=new Protection(d,artifacts,{rpc:()=>{throw new Error('must not call RPC');}});
  await assert.rejects(p.send('reactive'),/Resolve the pending/);
});
test('receipt recovery rejects transactions that change sender, input, amount or nonce',async()=>{
  const hash='0x'+'ab'.repeat(32),p=new Protection(draft(),artifacts);
  const expected=p.plan('reactive');p.d.pending={...expected,nonce:'0x1'};
  const good={from:guardian,to:null,input:expected.tx.data,value:'0x0',nonce:'0x1'};
  for(const change of [{from:safe},{to:safe},{input:'0x'},{value:'0x1'},{nonce:'0x2'}]){
    p.rpc=async()=>({...good,...change});await assert.rejects(p.reconcile(hash),/does not match/);
    assert.equal(p.d.pending.hash,undefined);
  }
});
test('log discovery respects 200-block windows and bounded work per refresh',async()=>{
  const calls=[],p=new Protection(draft(),artifacts,{rpc:async(chain,method,params)=>{calls.push(params[0]);return[];}});
  const result=await p.find('base',safe,[],50,10000);assert.equal(calls.length,5);assert.equal(result.cursor,1038);
  for(const filter of calls)assert.ok(BigInt(filter.toBlock)-BigInt(filter.fromBlock)<200n);
});
test('failed panic preparation clears the draft incident without losing submitted state',async()=>{
  const p=new Protection(draft(),artifacts,{rpc:async()=> '0x1'});p.d.vault=safe;p.allowed=async()=>{};
  p.connectChain=async()=>{throw new Error('network refused');};await assert.rejects(p.send('panic'),/network refused/);assert.equal(p.d.incident,null);
});
test('only a confirmed self-transfer with the same nonce can clear a cancelled wallet request',async()=>{
  const hash='0x'+'cd'.repeat(32),p=new Protection(draft(),artifacts);p.d.pending={...p.plan('reactive'),nonce:'0x4'};
  let tx={from:guardian,to:guardian,value:'0x0',input:'0x',nonce:'0x5'};
  p.rpc=async(chain,method)=>method==='eth_getTransactionByHash'?tx:'0x12';p.canonical=async()=>({blockNumber:'0x10'});
  await assert.rejects(p.reconcileCancellation(hash),/not a self-transfer/);assert.ok(p.d.pending);
  tx.nonce='0x4';await p.reconcileCancellation(hash);assert.equal(p.d.pending,null);assert.equal(p.d.history[0].status,'cancelled');
});
test('wallet rejection codes are recognized through nested wrappers without assuming unknown errors are rejections',()=>{
  const wrapped={code:-32603,data:{originalError:{code:4001}}};wrapped.cause=wrapped;
  assert.equal(hasWalletErrorCode(wrapped,4001),true);
  assert.equal(hasWalletErrorCode({code:-32603,message:'blocked'},4001),false);
});
test('same-chain wallet checks do not request switches; changed networks still require switching and verification',async()=>{
  const calls=[];let chain='0x512577';
  const p=new Protection(draft(),artifacts,{wallet:{request:async({method,params})=>{calls.push(method);if(method==='eth_chainId')return chain;if(method==='eth_accounts')return[guardian];if(method==='wallet_switchEthereumChain')chain=params[0].chainId;}}});
  await p.connectChain('lasna');await p.connectChain('lasna');assert.equal(calls.filter(x=>x==='wallet_switchEthereumChain').length,0);
  await p.connectChain('base');await p.connectChain('base');assert.equal(calls.filter(x=>x==='wallet_switchEthereumChain').length,1);
});
test('known wrapped rejection clears unsent state; unknown provider errors retain recovery state',async()=>{
  for(const [error,rejected] of [[{code:-32603,data:{originalError:{code:4001}}},true],[{code:-32603,message:'Provider stopped responding'},false]]){
    const p=new Protection(draft(),artifacts,{rpc:async(chain,method)=>method==='eth_getBalance'?'0x1000000000000000000':'0x1',wallet:{request:async({method})=>{if(method==='eth_getTransactionCount')return'0x0';throw error;}}});
    p.allowed=async()=>{};p.connectChain=async()=>{};
    await assert.rejects(p.send('reactive'));assert.equal(!!p.d.pending,!rejected);
  }
});
test('clear unsubmitted request is read-only, preserves deployed addresses, and requires matching unused nonce',async()=>{
  for(const [latest,pending,success] of [['0x4','0x4',true],['0x5','0x5',false],['0x4','0x5',false]]){
    const d=draft();d.reactive='0x3333333333333333333333333333333333333333';
    const p=new Protection(d,artifacts,{rpc:async(chain,method,params)=>method==='eth_chainId'?'0x14a34':params[1]==='latest'?latest:pending,wallet:{request:()=>assert.fail('Clearing must not call the wallet')}});
    p.d.pending={...p.plan('vault'),nonce:'0x4'};
    if(success){await p.cancelUnsent();assert.equal(p.d.pending,null);assert.equal(p.d.reactive,d.reactive);}else{await assert.rejects(p.cancelUnsent(),/nonce has changed/);assert.ok(p.d.pending);}
  }
});
test('known transaction hashes and unavailable chain checks cannot be cleared',async()=>{
  const p=new Protection(draft(),artifacts,{rpc:async()=>{throw new Error('RPC unavailable');}});
  p.d.pending={...p.plan('reactive'),nonce:'0x0',hash:'0x'+'aa'.repeat(32)};await assert.rejects(p.cancelUnsent(),/cannot be discarded/);assert.ok(p.d.pending.hash);
  delete p.d.pending.hash;await assert.rejects(p.cancelUnsent(),/RPC unavailable/);assert.ok(p.d.pending);
});
