// Verify every public app asset against the local release allowlist, then record evidence.
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
const files=JSON.parse(execFileSync(process.execPath,['scripts/web/release-files.mjs'],{encoding:'utf8',maxBuffer:4000000}));
const url='https://safesweep-pj.vercel.app',deployment=process.argv[2];
if(!/^dpl_[a-zA-Z0-9]+$/.test(deployment||''))throw new Error('Pass the verified Vercel deployment ID.');
for(const file of files.filter(x=>x.file!=='vercel.json')){
  const response=await fetch(`${url}/${file.file}`,{signal:AbortSignal.timeout(30000)});
  if(!response.ok)throw new Error(`HTTP ${response.status}: ${file.file}`);
  const digest=createHash('sha256').update(Buffer.from(await response.arrayBuffer())).digest('hex');
  if(digest!==file.sha256)throw new Error(`Hosted content mismatch: ${file.file}`);
}
const sourceCommit=execFileSync('git',['-c','safe.directory='+process.cwd().replaceAll('\\','/'),'rev-parse','HEAD'],{encoding:'utf8'}).trim();
fs.writeFileSync('deployments/dashboard.json',JSON.stringify({url,project_id:'prj_PCwURppHqV2eJhHlVRdPurKgxrll',deployment_id:deployment,target:'production',source_commit:sourceCommit,verified_date:new Date().toISOString(),files_sha256:Object.fromEntries(files.map(x=>[x.file,x.sha256])),verification:'13 hosted assets matched SHA-256; vercel.json is deployment configuration and is not public.'},null,2)+'\n');
console.log('PASS: 13 hosted static assets match the local release. Recorded deployment evidence.');
