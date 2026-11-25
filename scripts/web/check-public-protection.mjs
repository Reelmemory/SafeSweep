// Read-only compatibility check against the already retired public demo contracts.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { Protection, createRecord } from '../../web/protection-core.mjs';
const m=JSON.parse(fs.readFileSync(new URL('../../deployments/base-sepolia-20261124T163546Z.json',import.meta.url)));
const artifacts=JSON.parse(fs.readFileSync(new URL('../../web/contracts.json',import.meta.url))).contracts;
const d=createRecord(m.guardian,m.safe_wallet,{protectedAmount:'0.005',reactiveReserve:'0.5',callbackReserve:'0.002'});
d.reactive=m.reactive_contract;d.vault=m.vault_contract;
d.incident={id:m.incident_id,panicTx:m.panic_tx,reactiveTx:m.reactive_tx,callbackTx:m.callback_tx,baseCursor:m.panic_block,lasnaCursor:m.reactive_block};
const p=new Protection(d,artifacts);const state=await p.inspect();assert.equal(state.swept,true);assert.equal(state.balance,0n);
const proof=await p.monitor();assert.equal(proof.delivery,true);
console.log('PASS: public contract runtime, immutables, configuration, service reads and three actual receipts verified with the new app engine. Read-only; no transactions sent.');
