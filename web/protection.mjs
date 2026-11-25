import { Protection, NETWORKS, createRecord, validateRecord, publicRpc, same, formatEther, hasWalletErrorCode } from './protection-core.mjs';

const $ = id => document.getElementById(id);
const KEY = 'safesweep.protection.v1';
let records = [], selected = null, account = null, provider = null, artifacts, controller, snapshot, proof, busy = false, reviewKind;
const providers = new Map();
let connectingWallet = false, initializing = true;
const steps = [
  ['reactive','Deploy listener','Reactive Lasna · observes your panic event'],
  ['vault','Deploy vault','Base Sepolia · your immutable guardian and safe wallet'],
  ['configure','Connect contracts','Reactive Lasna · subscribes to your vault'],
  ['reactiveReserve','Fund execution reserve','Reactive Lasna · pays for the reaction'],
  ['callbackReserve','Fund callback reserve','Base Sepolia · pays for delivery'],
  ['deposit','Deposit protected ETH','Base Sepolia · ETH held in your vault'],
];
const short = value => `${value.slice(0,8)}…${value.slice(-6)}`;
const notice = (message, error = false) => { $('notice').textContent = message; $('notice').dataset.error = error; };
const errorText = error => hasWalletErrorCode(error,4001) ? 'Wallet request declined. No new step was completed.' : error.message || String(error);
const fail = error => notice(errorText(error), true);
function recoveryNotice(message,error=false){$('recoveryStatus').hidden=false;$('recoveryStatus').textContent=message;$('recoveryStatus').dataset.error=error;}
function load() {
  const values = JSON.parse(localStorage.getItem(KEY) || '[]');
  if (!Array.isArray(values)) throw new Error('Saved setup data is invalid. Restore an exported setup file.');
  return values.map(validateRecord);
}
function saveRecord(d) {
  records = load(); const index = records.findIndex(x=>x.id===d.id);
  if(index<0) records.push(d); else records[index]=d;
  localStorage.setItem(KEY,JSON.stringify(records)); renderList();
}
function bind(d) { controller = d ? new Protection(d,artifacts,{wallet:provider,save:saveRecord}) : null; }
function link(chain, value, type='address') {
  const a=document.createElement('a'); a.href=`${NETWORKS[chain].blockExplorerUrls[0]}/${type}/${value}`;
  a.textContent=type==='tx'?short(value)+' ↗':value+' ↗'; a.target='_blank'; a.rel='noreferrer'; return a;
}
function row(dl,label,value) { const dt=document.createElement('dt'),dd=document.createElement('dd');dt.textContent=label;typeof value==='string'?dd.textContent=value:dd.append(value);dl.append(dt,dd); }
function renderList() {
  $('setups').replaceChildren();
  for(const d of records) { const b=document.createElement('button'); b.textContent=`${d.vault?'Vault '+short(d.vault):'Setup in progress'} · to ${short(d.safe)}`;
    b.className=d.id===selected?'active':''; b.disabled=busy; b.onclick=()=>select(d.id); $('setups').append(b); }
}
function select(id) {
  if(busy)return; selected=id; sessionStorage.setItem('safesweep.selected',id||''); snapshot=null;proof=null;
  $('recoveryStatus').hidden=true;$('notSent').checked=false;$('submittedRecovery').open=false;
  bind(records.find(d=>d.id===id)); render(); if(controller)queueMicrotask(()=>void refresh());
}
function render() {
  renderList(); const d=controller?.d,s=snapshot;
  $('connect').textContent=account?short(account):'Connect wallet'; $('connect').disabled=busy||initializing;
  $('newSetup').disabled=busy||!artifacts; $('importButton').disabled=busy||!artifacts;
  $('create').disabled=busy||!account||!artifacts;
  $('createPanel').hidden=!!d; $('managePanel').hidden=!d;
  if(!d)return;
  const owner=same(account,d.guardian), funded=s&&s.reactiveReserve>0n&&s.callbackReserve>0n&&s.reactiveDebt===0n&&s.callbackDebt===0n;
  const writable=owner&&!busy&&!d.pending&&s&&!s.swept;
  $('status').textContent=!s?'Checking chain state':proof?.delivery?'Evacuation verified':s.swept?'Vault retired':d.incident?.panicTx?'Evacuation in progress':s.configured&&funded&&s.balance>0n?'Protection ready':'Complete your setup';
  $('protectedBalance').textContent=s?`${formatEther(s.balance)} ETH`:'—';
  $('executionBalance').textContent=s?`${formatEther(s.reactiveReserve)} lREACT`:'—';
  $('callbackBalance').textContent=s?`${formatEther(s.callbackReserve)} ETH`:'—';
  $('guardianMessage').textContent=owner?'Connected as guardian. Each action requires your wallet approval.':`Connect guardian ${short(d.guardian)} to continue. You can view this setup without connecting.`;
  if(s&&(s.reactiveDebt>0n||s.callbackDebt>0n)) $('guardianMessage').textContent+=` Service debt: ${formatEther(s.reactiveDebt)} lREACT / ${formatEther(s.callbackDebt)} ETH. Top up reserves before proceeding.`;
  $('addresses').replaceChildren(); for(const [label,key,chain] of [['Guardian','guardian','base'],['Safe wallet','safe','base'],['Vault','vault','base'],['Listener','reactive','lasna']])row($('addresses'),label,d[key]?link(chain,d[key]):'Not deployed yet');
  $('refresh').disabled=busy; $('pendingPanel').hidden=!d.pending; $('recoverPanel').hidden=!d.pending;
  $('unsentRecovery').hidden=!!d.pending?.hash;
  if(d.pending){
    $('pendingTitle').textContent=d.pending.hash?'Transaction submitted':'No transaction hash received';
    $('pendingText').textContent=d.pending.hash?`${d.pending.title}: ${d.pending.hash}. Waiting for two confirmations. Refresh to check; do not send again.`:`${d.pending.title} · ${NETWORKS[d.pending.chain].chainName} · guardian ${short(d.guardian)}. A missing hash does not confirm whether the wallet sent it. Check wallet activity before choosing a recovery option.`;
    if(d.pending.hash)$('submittedRecovery').open=true;
  }
  $('recover').disabled=busy; $('discard').disabled=busy||!!d.pending?.hash||!$('notSent').checked; $('cancelled').disabled=busy;
  const done=s?[!!d.reactive,!!d.vault,s.configured,s.reactiveReserve>0n,s.callbackReserve>0n,s.balance>0n||s.swept||d.history.some(x=>x.kind==='deposit'&&x.status==='confirmed')]:[];
  $('steps').replaceChildren(); $('steps').hidden=!!s?.swept||!!d.incident?.panicTx;
  steps.forEach(([kind,title,description],index)=>{
    const li=document.createElement('li'), n=document.createElement('span'), copy=document.createElement('div'), sub=document.createElement('small'), b=document.createElement('button');
    n.className='number';n.textContent=done[index]?'✓':String(index+1);copy.className='step-copy';copy.textContent=title;sub.textContent=description;copy.append(sub);
    b.textContent=done[index]?'Confirmed':'Review';b.className='secondary';b.dataset.action=kind;b.disabled=!writable||!!done[index]||done.slice(0,index).some(x=>!x);b.onclick=()=>review(kind);
    li.append(n,copy,b);$('steps').append(li);
  });
  $('activeActions').hidden=!s?.configured||!!s?.swept;
  $('depositMore').disabled=!writable||!funded||!!d.incident;
  $('topupReactive').disabled=!writable;$('topupCallback').disabled=!writable;
  $('panic').disabled=!writable||!funded||s?.balance===0n||!!d.incident;
  $('faucet').disabled=!owner||busy||!!d.pending||!!s?.swept;
  $('depositHint').textContent=`Each additional deposit adds ${d.protectedAmount} ETH. Reserve top-ups add ${d.reactiveReserve} lREACT or ${d.callbackReserve} ETH, as chosen for this setup.`;
  $('incidentPanel').hidden=!d.incident;
  $('incidentStatus').textContent=proof?.delivery?`${proof.amount} ETH delivered to your safe wallet. All three receipts verified.`:proof?.confirmations?`Transfer found. ${proof.confirmations}/13 Base confirmations.`:proof?.reaction?'Reactive request verified. Waiting for the destination transfer.':proof?.origin?'Panic verified. Waiting for Reactive Network.':'Waiting for the panic transaction to confirm.';
  $('incidentLinks').replaceChildren();for(const [key,label,chain] of [['panicTx','Panic','base'],['reactiveTx','Reactive request','lasna'],['callbackTx','Transfer','base']])if(d.incident?.[key]) {const a=link(chain,d.incident[key],'tx');a.textContent=label+' ↗';$('incidentLinks').append(a);}
  $('history').replaceChildren();for(const tx of [...d.history].reverse()){const li=document.createElement('li');li.append(`${tx.kind} · ${tx.status} · `,link(tx.chain,tx.hash,'tx'));$('history').append(li);}
}
async function refresh() {
  if(busy||!controller||$('walletPicker').open)return;busy=true;render();
  try {if(controller.d.pending?.hash)await controller.reconcile(); snapshot=await controller.inspect();proof=await controller.monitor();notice('Chain state checked. Your setup progress is saved in this browser.');}
  catch(error){snapshot=null;proof=null;fail(error);}
  finally {busy=false;render();}
  void balances();
}
async function balances() {
  if(!account)return;
  try {const values=await Promise.all(['base','lasna'].map(async c=>formatEther(BigInt(await publicRpc(c,'eth_getBalance',[account,'latest'])))));
    $('walletBalances').textContent=`Wallet: ${values[0]} Base Sepolia ETH · ${values[1]} lREACT`; }catch{$('walletBalances').textContent='Wallet balances unavailable. Check your wallet app.';}
}
function announce(info,p) {
  if(!info || typeof info.uuid!=='string' || typeof info.name!=='string' || typeof p?.request!=='function')return;
  if(providers.has(info.uuid) || [...providers.values()].some(entry=>entry.provider===p))return;
  providers.set(info.uuid,{name:info.name.slice(0,80),provider:p});
  if($('walletPicker').open)renderWallets();
}
window.addEventListener('eip6963:announceProvider',event=>announce(event.detail?.info,event.detail?.provider));
window.dispatchEvent(new Event('eip6963:requestProvider'));
const accountChanged = accounts => {account=accounts[0]||null;render();void balances();};
const disconnected = () => {account=null;render();};
function renderWallets() {
  const entries=[...providers.values()];
  // Legacy injection is a fallback only, so an announced wallet never appears twice.
  if(!entries.length && typeof window.ethereum?.request==='function')entries.push({name:'Browser wallet',provider:window.ethereum});
  $('walletOptions').replaceChildren();$('walletEmpty').hidden=entries.length>0;
  for(const entry of entries){
    const button=document.createElement('button'),mark=document.createElement('span'),name=document.createElement('span'),state=document.createElement('small');
    button.type='button';button.className='wallet-option';button.disabled=connectingWallet;
    mark.className='wallet-mark';mark.textContent=entry.name.slice(0,1).toUpperCase();mark.setAttribute('aria-hidden','true');
    name.className='wallet-name';name.textContent=entry.name;state.textContent=account&&entry.provider===provider?'Connected':'Connect →';
    button.append(mark,name,state);button.onclick=()=>connectWallet(entry);$('walletOptions').append(button);
  }
}
async function connectWallet(entry) {
  if(busy||connectingWallet)return;connectingWallet=true;busy=true;render();renderWallets();
  $('walletStatus').textContent=`Approve the connection in ${entry.name}.`;
  try {
    const next=entry.provider,accounts=await next.request({method:'eth_requestAccounts'});
    if(!Array.isArray(accounts)||!accounts.length)throw new Error('No account was shared. Unlock your wallet and try again.');
    // Commit provider and account together only after approval; a declined switch keeps the old connection.
    if(provider!==next){provider?.removeListener?.('accountsChanged',accountChanged);provider?.removeListener?.('disconnect',disconnected);provider=next;provider.on?.('accountsChanged',accountChanged);provider.on?.('disconnect',disconnected);}
    if(controller)controller.wallet=provider;accountChanged(accounts);$('walletPicker').close();
    notice(`Connected to ${entry.name}. ${controller?'Your setup is ready to view.':'Choose a separate safe receiving wallet.'}`);
  }catch(error){$('walletStatus').textContent=Number(error.code)===4001?'Connection declined. Choose a wallet to try again.':error.message||'Unable to connect. Try again.';}
  finally {connectingWallet=false;busy=false;render();renderWallets();if(controller&&!snapshot)queueMicrotask(()=>void refresh());}
}
$('walletPicker').addEventListener('close',()=>{if(controller&&!snapshot)queueMicrotask(()=>void refresh());});
$('connect').onclick=()=>{
  if(busy)return;$('walletStatus').textContent='Choose an available wallet to continue.';
  window.dispatchEvent(new Event('eip6963:requestProvider'));renderWallets();$('walletPicker').showModal();
};
$('createForm').onsubmit=async event=>{
  event.preventDefault();if(busy)return;busy=true;render();
  try {if(!account)throw new Error('Connect your guardian wallet first.');const d=createRecord(account,$('safe').value,{protectedAmount:$('protectedAmount').value,reactiveReserve:$('reactiveReserve').value,callbackReserve:$('callbackReserve').value});
    if(await publicRpc('base','eth_getCode',[d.safe,'latest'])!=='0x')throw new Error('Choose a safe wallet with no deployed contract code.');
    saveRecord(d);busy=false;select(d.id);notice('Setup saved. Review and approve each step below. No transaction has been sent yet.');
  }catch(error){fail(error);}finally{busy=false;render();}
};
function review(kind) {
  if(busy||!controller)return;reviewKind=kind;const d=controller.d;
  const p=kind==='panic'?{title:'Trigger irreversible evacuation',chain:'base',tx:{from:d.guardian,to:d.vault,value:'0x0'}}:controller.plan(kind);
  $('reviewTitle').textContent=p.title;$('reviewDetails').replaceChildren();
  row($('reviewDetails'),'Network',NETWORKS[p.chain].chainName);row($('reviewDetails'),'Guardian',d.guardian);row($('reviewDetails'),'Recipient',p.tx.to||'New contract deployment');
  row($('reviewDetails'),'Amount',`${formatEther(BigInt(p.tx.value))} ${NETWORKS[p.chain].nativeCurrency.symbol} + gas`);
  row($('reviewDetails'),'Safe wallet',d.safe);
  $('reviewNote').textContent=kind==='panic'?`This requests evacuation of all ${formatEther(snapshot.balance)} ETH held in this vault to ${d.safe}. The vault retires after delivery. Automation depends on network execution and sufficient reserves.`:kind==='deposit'?'This ETH becomes protected only after it reaches your vault. Reserves and gas are separate.':'Verify the addresses above. Contract guardian and safe-wallet destination cannot be changed.';
  $('review').showModal();
}
async function lockedAction(fn,recovery=false) {
  if(busy)return;
  if(!navigator.locks){const message='This browser cannot safely coordinate wallet actions across tabs. Use a current Chrome, Edge, Firefox or Safari browser.';fail(new Error(message));if(recovery)recoveryNotice(message,true);return;}
  if(recovery)recoveryNotice('Checking saved request and chain state…');
  busy=true;render();
  try {await navigator.locks.request('safesweep-wallet-action',{ifAvailable:true},async lock=>{
    if(!lock)throw new Error('Another SafeSweep tab is handling a wallet action. Finish there first.');
    const fresh=load().find(x=>x.id===selected);if(!fresh)throw new Error('This setup is missing. Restore its exported file.');bind(fresh);await fn();
    if(recovery&&!controller.d.pending){
      snapshot=null;try{snapshot=await controller.inspect();}catch(error){recoveryNotice(`Request resolved and saved, but chain checks are unavailable: ${errorText(error)}. Use Refresh to check again.`,true);}
    }
  });}catch(error){fail(error);if(recovery)recoveryNotice(errorText(error),true);}finally{busy=false;render();if(recovery)$('recoveryStatus').scrollIntoView({block:'nearest'});}
}
$('approve').onclick=async()=>{$('review').close();await lockedAction(async()=>{await controller.send(reviewKind);notice('Transaction submitted. Waiting for two confirmations; refresh to check.');});};
$('recover').onclick=()=>lockedAction(async()=>{const confirmed=await controller.reconcile($('recoveryHash').value.trim());const message=confirmed?'Transaction recovered and confirmed.':'Transaction matched. Waiting for confirmations.';notice(message);recoveryNotice(message);},true);
$('discard').onclick=()=>lockedAction(async()=>{if(!$('notSent').checked)throw new Error('First check your wallet activity and confirm nothing was submitted.');await controller.cancelUnsent();$('notSent').checked=false;const message='Unsubmitted request cleared. Your setup is saved. This recovery action sent no transaction.';notice(message);recoveryNotice(message);},true);
$('notSent').onchange=render;
$('cancelled').onclick=()=>lockedAction(async()=>{await controller.reconcileCancellation($('recoveryHash').value.trim());notice('On-chain cancellation verified.');recoveryNotice('On-chain cancellation verified. The pending request has been cleared.');},true);
$('refresh').onclick=refresh;$('newSetup').onclick=()=>select(null);
for(const [id,kind] of [['depositMore','deposit'],['topupReactive','reactiveReserve'],['topupCallback','callbackReserve'],['panic','panic'],['faucet','faucet']])$(id).onclick=()=>review(kind);
$('export').onclick=()=>{const url=URL.createObjectURL(new Blob([JSON.stringify(controller.d,null,2)],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download=`safesweep-${controller.d.id}.json`;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);notice('Setup exported. This file contains addresses and progress, never private keys.');};
$('importButton').onclick=()=>$('importFile').click();
$('importFile').onchange=async()=>{
  if(busy||!artifacts)return;const file=$('importFile').files[0];if(!file)return;busy=true;render();
  try {if(file.size>100000)throw new Error('Setup file is too large.');const d=validateRecord(JSON.parse(await file.text()));await new Protection(d,artifacts).inspect();
    const existing=records.find(x=>x.id===d.id);if(existing?.pending)throw new Error('Resolve this browser’s pending transaction before restoring an older copy.');saveRecord(d);busy=false;select(d.id);notice('Setup restored and contract configuration verified.');
  }catch(error){fail(error);}finally{busy=false;$('importFile').value='';render();}
};
window.addEventListener('storage',event=>{if(event.key===KEY&&!busy){try{records=load();select(selected);}catch(error){fail(error);}}});
render();
try {localStorage.setItem('safesweep.storage-check','1');localStorage.removeItem('safesweep.storage-check');const response=await fetch('contracts.json');if(!response.ok)throw new Error('Contract definitions unavailable.');artifacts=(await response.json()).contracts;records=load();const id=sessionStorage.getItem('safesweep.selected');select(records.some(x=>x.id===id)?id:records.at(-1)?.id||null);}
catch(error){fail(error);render();}
finally {initializing=false;render();}
setInterval(()=>{if(!document.hidden&&!$('review').open&&!$('walletPicker').open)void refresh();},15000);
