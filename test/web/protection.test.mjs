import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { Protection, amount, createRecord, validateRecord, runtimeMatches } from '../../web/protection-core.mjs';
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
