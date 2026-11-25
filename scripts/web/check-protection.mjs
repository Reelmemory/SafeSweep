// Real EVM browser rehearsal. All wallet transactions stay on two local Anvil chains.
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { Interface, parseEther } from 'ethers';
import { Protection, SYSTEM, PROXY, runtimeMatches } from '../../web/protection-core.mjs';
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.SAFESWEEP_PLAYWRIGHT||'playwright');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..'),web=path.join(root,'web');
const artifacts=JSON.parse(fs.readFileSync(path.join(web,'contracts.json'))).contracts;
const ports={base:19546,lasna:19545},children=[];
let browser,server;
const pause=ms=>new Promise(r=>setTimeout(r,ms));
async function rpc(chain,method,params=[]) {
  const response=await fetch(`http://127.0.0.1:${ports[chain]}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({jsonrpc:'2.0',id:1,method,params})});
  const json=await response.json();if(json.error)throw new Error(json.error.message);return json.result;
}
async function start(chain,id) {
  // Refuse to attach to a pre-existing process: this harness installs mocks and mutates state.
  try {await rpc(chain,'eth_chainId');throw new Error(`Port ${ports[chain]} is already in use.`);}catch(e){if(e.message.includes('already'))throw e;}
  const child=spawn('anvil',['--port',String(ports[chain]),'--chain-id',String(id),'--silent'],{stdio:'ignore',windowsHide:true});children.push(child);
  let exited=false;child.on('error',()=>{exited=true;});
  for(let i=0;i<100;i++){if(exited)throw new Error('Cannot start Anvil.');try{await rpc(chain,'eth_chainId');return;}catch{await pause(100);}}
  throw new Error('Anvil did not start.');
}
const code=name=>JSON.parse(fs.readFileSync(path.join(root,`out/${name}.sol/${name}.json`))).deployedBytecode.object;
try {
  await start('base',84532);await start('lasna',5318007);
  await rpc('lasna','anvil_setCode',[SYSTEM,code('MockSystem')]);await rpc('base','anvil_setCode',[PROXY,code('MockCallbackProxy')]);
  const accounts=await rpc('base','eth_accounts'),guardian=accounts[0],safe=accounts[1];
  server=http.createServer((req,res)=>{const file=path.resolve(web,'.'+(req.url==='/'?'/index.html':req.url.split('?')[0]));
    if(!file.startsWith(web+path.sep)||!fs.existsSync(file)){res.writeHead(404);res.end();return;}
    res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.mjs':'text/javascript','.css':'text/css','.json':'application/json'})[path.extname(file)]||'application/octet-stream');res.end(fs.readFileSync(file));});
  await new Promise(r=>server.listen(0,'127.0.0.1',r));
  const url=process.env.SAFESWEEP_PROTECTION_URL||`http://127.0.0.1:${server.address().port}`;
  browser=await chromium.launch({headless:true,...(process.env.SAFESWEEP_BROWSER==='chromium'?{}:{channel:process.env.SAFESWEEP_BROWSER||'msedge'})});
  const context=await browser.newContext({viewport:{width:1440,height:1000}}),page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
  await context.route(/https:\/\/(sepolia\.base\.org|lasna-rpc\.rnk\.dev)/,async route=>{
    const {method,params}=route.request().postDataJSON();const chain=route.request().url().includes('base.org')?'base':'lasna';
    try{await route.fulfill({json:{jsonrpc:'2.0',id:1,result:await rpc(chain,method,params)}});}catch(e){await route.fulfill({json:{jsonrpc:'2.0',id:1,error:{code:-32000,message:e.message}}});}
  });
  let lastHash;
  await page.exposeFunction('__localRpc',async(chain,method,params)=>{const result=await rpc(chain,method,params);if(method==='eth_sendTransaction')lastHash=result;return result;});
  await page.addInitScript(({guardian,safe})=>{
    let chain='base';const listeners={};window.testWallet={account:guardian,reject:false,interrupt:false,wrongChain:false};
    window.testWallet.change=account=>{window.testWallet.account=account;listeners.accountsChanged?.forEach(fn=>fn([account]));};
    window.ethereum={on:(name,fn)=>(listeners[name]||=[]).push(fn),removeListener:(name,fn)=>{listeners[name]=(listeners[name]||[]).filter(x=>x!==fn);},request:async({method,params=[]})=>{
      if(['eth_accounts','eth_requestAccounts'].includes(method))return[window.testWallet.account];
      if(method==='eth_chainId')return window.testWallet.wrongChain?'0x1':chain==='base'?'0x14a34':'0x512577';
      if(method==='wallet_switchEthereumChain'){chain=params[0].chainId==='0x14a34'?'base':'lasna';return null;}
      if(method==='eth_sendTransaction'&&window.testWallet.reject){window.testWallet.reject=false;throw Object.assign(new Error('Rejected by user'),{code:4001});}
      const result=await window.__localRpc(chain,method,params);
      if(method==='eth_sendTransaction'&&window.testWallet.interrupt){window.testWallet.interrupt=false;throw new Error('Simulated lost wallet response');}
      return result;
    }};
  },{guardian,safe});
  const saved=()=>page.evaluate(()=>JSON.parse(localStorage.getItem('safesweep.protection.v1'))?.[0]);
  const idle=()=>page.waitForFunction(()=>!document.querySelector('#refresh').disabled);
  async function refresh(){await idle();await page.locator('#refresh').click();await idle();}
  async function submit(selector){await idle();await page.locator(selector).click();await page.locator('#approve').click();await idle();}
  async function confirm(chain){await rpc(chain,'anvil_mine',['0x2']);await refresh();const d=await saved();assert.equal(d.pending,null,await page.locator('#notice').textContent());return d;}
  await page.goto(url);await page.locator('#connect').click();await page.locator('#safe').fill(safe);await page.locator('#acknowledge').check();
  await page.locator('#create').click();await page.locator('#managePanel').waitFor({state:'visible'});await idle();
  assert.equal((await saved()).history.length,0,'draft must not send transactions');
  // Wrong guardian cannot submit even though it can inspect.
  await page.evaluate(safe=>window.testWallet.change(safe),safe);assert.equal(await page.locator('[data-action="reactive"]').isDisabled(),true);
  await page.evaluate(guardian=>window.testWallet.change(guardian),guardian);
  // A rejected wallet signature leaves no uncertain pending transaction.
  await page.evaluate(()=>window.testWallet.reject=true);await submit('[data-action="reactive"]');assert.equal((await saved()).pending,null);
  // Wrong-chain provider must not broadcast.
  await page.evaluate(()=>window.testWallet.wrongChain=true);await submit('[data-action="reactive"]');assert.equal((await saved()).history.length,0);
  assert.match(await page.locator('#notice').textContent(),/wrong network/);await page.evaluate(()=>window.testWallet.wrongChain=false);
  await submit('[data-action="reactive"]');assert.ok((await saved()).pending.hash);
  // Persist the hash before receipt handling, then survive reload without deploying twice.
  await page.reload();await idle();await page.locator('#connect').click();let d=await confirm('lasna');assert.ok(d.reactive);
  assert.equal(runtimeMatches(await rpc('lasna','eth_getCode',[d.reactive,'latest']),artifacts.SafeSweepReactive),true);
  // Wallet broadcasts but fails to return hash. Recover the exact deployment from activity.
  await page.evaluate(()=>window.testWallet.interrupt=true);await submit('[data-action="vault"]');assert.equal((await saved()).pending.hash,undefined);
  const deploymentHash=lastHash;await page.reload();await idle();await page.locator('#connect').click();
  await page.locator('#recoveryHash').fill(deploymentHash);await page.locator('#recover').click();await idle();d=await confirm('base');assert.ok(d.vault);
  for(const [kind,chain] of [['configure','lasna'],['reactiveReserve','lasna'],['callbackReserve','base'],['deposit','base']]){await submit(`[data-action="${kind}"]`);d=await confirm(chain);}
  assert.equal(await page.locator('#status').textContent(),'Protection ready');assert.equal(BigInt(await rpc('base','eth_getBalance',[d.vault,'latest'])),parseEther('0.005'));
  assert.equal(await page.locator('#panic').isEnabled(),true);
  // Export and restore into a new browser context, verify actual immutable settings.
  const download=page.waitForEvent('download');await page.locator('#export').click();const exported=await download;
  fs.mkdirSync(path.join(root,'.tools'),{recursive:true});const backup=path.join(root,'.tools/protection-test-backup.json');await exported.saveAs(backup);
  const freshPage=await context.newPage();await freshPage.goto(url);await freshPage.evaluate(()=>{localStorage.removeItem('safesweep.protection.v1');sessionStorage.clear();});await freshPage.reload();
  await freshPage.waitForFunction(()=>!document.querySelector('#importButton').disabled);
  await freshPage.locator('#importFile').setInputFiles(backup);
  try {await freshPage.waitForFunction(()=>document.querySelector('#status').textContent==='Protection ready');}
  catch(error){throw new Error(`Restore failed: ${await freshPage.locator('#notice').textContent()} / ${await freshPage.locator('#status').textContent()}`,{cause:error});}
  await freshPage.close();await refresh();
  fs.mkdirSync(path.join(root,'docs/screenshots'),{recursive:true});await page.screenshot({path:path.join(root,'docs/screenshots/protection-ready-desktop.png'),fullPage:true});
  for(const width of [768,390]){await page.setViewportSize({width,height:844});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,`overflow at ${width}`);}
  await page.screenshot({path:path.join(root,'docs/screenshots/protection-ready-mobile.png'),fullPage:true});await page.setViewportSize({width:1440,height:1000});
  // Unexpected bytecode and misbound immutable values fail closed.
  const controller=new Protection(d,artifacts,{rpc});await controller.inspect();
  await assert.rejects(new Protection({...d,safe:accounts[2]},artifacts,{rpc}).inspect(),/safeWallet/);
  const originalCode=await rpc('base','eth_getCode',[d.vault,'latest']);await rpc('base','anvil_setCode',[d.vault,'0x60006000']);await assert.rejects(controller.allowed('panic'),/Vault code/);await rpc('base','anvil_setCode',[d.vault,originalCode]);
  // Insufficient reserves disable deposits and panic.
  const debtABI=new Interface(['function setDebt(address,uint256)']);await rpc('base','eth_sendTransaction',[{from:guardian,to:PROXY,data:debtABI.encodeFunctionData('setDebt',[d.vault,1])}]);
  await assert.rejects(controller.allowed('panic'),/clear service debt/);await refresh();assert.equal(await page.locator('#panic').isDisabled(),true);
  await rpc('base','eth_sendTransaction',[{from:guardian,to:PROXY,data:debtABI.encodeFunctionData('setDebt',[d.vault,0])}]);await refresh();
  // Panic rejection clears the incident; retry emits exactly one real panic.
  await page.evaluate(()=>window.testWallet.reject=true);await submit('#panic');assert.equal((await saved()).incident,null);await refresh();
  const safeBefore=BigInt(await rpc('base','eth_getBalance',[safe,'latest']));await submit('#panic');d=await confirm('base');assert.ok(d.incident.panicTx);assert.equal(await page.locator('#depositMore').isDisabled(),true);
  const receipt=await rpc('base','eth_getTransactionReceipt',[d.incident.panicTx]),log=receipt.logs[0];
  await rpc('lasna','anvil_impersonateAccount',[SYSTEM]);await rpc('lasna','anvil_setBalance',[SYSTEM,'0x56bc75e2d63100000']);
  const abi=new Interface(artifacts.SafeSweepReactive.abi);
  const record=[84532,d.vault,log.topics[0],log.topics[1],log.topics[2],0,log.data,receipt.blockNumber,3,receipt.blockHash,d.incident.panicTx,log.logIndex];
  await rpc('lasna','eth_sendTransaction',[{from:SYSTEM,to:d.reactive,data:abi.encodeFunctionData('react',[record]),gas:'0xf4240'}]);
  const proxyABI=new Interface(['function deliver(address,address,bytes32)']);await rpc('base','eth_sendTransaction',[{from:guardian,to:PROXY,data:proxyABI.encodeFunctionData('deliver',[d.vault,d.reactive,d.incident.id]),gas:'0xf4240'}]);
  await rpc('base','anvil_mine',['0xd']);await refresh();assert.equal(await page.locator('#status').textContent(),'Evacuation verified',await page.locator('#notice').textContent());
  assert.equal(BigInt(await rpc('base','eth_getBalance',[safe,'latest']))-safeBefore,parseEther('0.005'));assert.equal(BigInt(await rpc('base','eth_getBalance',[d.vault,'latest'])),0n);
  assert.equal(await page.locator('#activeActions').isHidden(),true);assert.equal(await page.locator('#incidentLinks a').count(),3);assert.deepEqual(errors,[]);
  await page.screenshot({path:path.join(root,'docs/screenshots/protection-evacuated-desktop.png'),fullPage:true});
  console.log('PASS: six setup transactions; guardian and chain guards; wallet rejection; reload and lost-hash recovery; export/import; runtime/immutable/debt checks; desktop/mobile; panic → reaction → delivery; 0.005 ETH received; retired vault. Local chains only.');
} finally {await browser?.close();if(server)await new Promise(r=>server.close(r));for(const child of children)child.kill();}
