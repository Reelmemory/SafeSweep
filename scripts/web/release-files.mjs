// Explicit static release allowlist. Never recursively upload a workspace or secrets.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../web');
const names=['index.html','demo.html','protection.css','protection.mjs','protection-core.mjs','contracts.json','vendor/ethers.js','vendor/ethers.LICENSE.md','styles.css','app.js','config.js','proof.mjs','proof.json','vercel.json'];
const files=names.map(file=>{const data=fs.readFileSync(path.join(root,file));return{file,data:data.toString('base64'),encoding:'base64',sha:createHash('sha1').update(data).digest('hex'),size:data.length,sha256:createHash('sha256').update(data).digest('hex')};});
process.stdout.write(JSON.stringify(files));
