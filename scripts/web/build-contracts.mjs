import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const contracts = {};
for (const name of ['SafeSweepReactive', 'SafeSweepVault']) {
  const artifact = JSON.parse(fs.readFileSync(path.join(root, `out/${name}.sol/${name}.json`)));
  contracts[name] = { abi: artifact.abi, bytecode: artifact.bytecode.object,
    runtime: artifact.deployedBytecode.object, immutableReferences: artifact.deployedBytecode.immutableReferences };
}
fs.writeFileSync(path.join(root, 'web/contracts.json'), JSON.stringify({ compiler: '0.8.29', contracts }) + '\n');
fs.mkdirSync(path.join(root, 'web/vendor'), { recursive: true });
fs.copyFileSync(path.join(root, 'node_modules/ethers/dist/ethers.min.js'), path.join(root, 'web/vendor/ethers.js'));
fs.copyFileSync(path.join(root, 'node_modules/ethers/LICENSE.md'), path.join(root, 'web/vendor/ethers.LICENSE.md'));
console.log('Exported pinned contract bytecode, ABI and ethers browser module');
