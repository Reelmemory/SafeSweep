/* Run: node scripts/web/check-browser.cjs [--live]. Requires Playwright + Edge/Chromium.
   SAFESWEEP_PLAYWRIGHT optionally selects an existing Playwright installation. */
const { chromium } = require(process.env.SAFESWEEP_PLAYWRIGHT || 'playwright');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
const web = path.join(root, 'web');
const proof = JSON.parse(fs.readFileSync(path.join(web, 'proof.json')));
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'deployments/base-sepolia-20261124T163546Z.json')));
const word = value => '0x' + BigInt(value).toString(16).padStart(64, '0');
const recording = process.argv.includes('--record-demo');
const live = process.argv.includes('--live') || recording;
const server = http.createServer((req, res) => {
  const file = path.resolve(web, '.' + (req.url === '/' ? '/index.html' : req.url.split('?')[0]));
  if (!file.startsWith(web + path.sep) || !fs.existsSync(file)) { res.writeHead(404); res.end(); return; }
  const mime = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png' };
  res.setHeader('Content-Type', mime[path.extname(file)] || 'application/octet-stream');
  res.end(fs.readFileSync(file));
});

function rpcResult(method, params, active = false) {
  if (method === 'eth_blockNumber') return '0x' + proof.final_state.block.toString(16);
  if (method === 'eth_getBalance') return active ? word(5000000000000000n) : '0x0';
  if (method === 'eth_call') return ({ '0x452a9320': word(manifest.guardian), '0x88cfce56': word(manifest.safe_wallet), '0x2113eaca': word(active ? 0 : 1) })[params[0].data];
  const receipts = [proof.origin_receipt, proof.reactive_receipt, proof.callback_receipt];
  if (method === 'eth_getTransactionReceipt') return receipts.find(r => r.transactionHash === params[0]);
  if (method === 'eth_getBlockByNumber') return { hash: receipts.find(r => r.blockNumber === params[0]).blockHash };
  throw new Error('Unexpected RPC ' + method);
}

(async () => {
  let browser;
  const results = [];
  try {
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const url = process.env.SAFESWEEP_DASHBOARD_URL || 'http://127.0.0.1:' + server.address().port + '/demo.html';
    browser = await chromium.launch({ channel: process.env.SAFESWEEP_BROWSER || 'msedge', headless: true });
    const videoDir = path.join(root, 'docs/demo');
    const context = await browser.newContext(recording ? { recordVideo: { dir: videoDir, size: { width: 1280, height: 800 } } } : {});
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    if (!live) {
      await context.route(/https:\/\/(sepolia\.base\.org|lasna-rpc\.rnk\.dev)/, async route => {
        const { method, params } = route.request().postDataJSON();
        await route.fulfill({ json: { jsonrpc: '2.0', id: 1, result: rpcResult(method, params) } });
      });
    }
    for (const [name, width, height] of recording ? [['walkthrough', 1280, 800]] : [['desktop', 1440, 1000], ['tablet', 768, 1024], ['mobile', 390, 844]]) {
      await page.setViewportSize({ width, height });
      await page.goto(url);
      await page.waitForFunction(() => document.querySelector('#heroState').textContent === 'Evacuation verified', null, { timeout: 60000 });
      assert.equal(await page.locator('#panicButton').isDisabled(), true);
      assert.equal(await page.locator('#balanceValue').textContent(), '0.0000');
      assert.equal(await page.locator('.loop-step.active').count(), 4);
      const fits = await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth);
      assert.equal(fits, true, `${name} horizontal overflow`);
      fs.mkdirSync(path.join(root, 'docs/screenshots'), { recursive: true });
      if (!recording) await page.screenshot({ path: path.join(root, `docs/screenshots/${live ? 'live-' : ''}${name}.png`), fullPage: true });
      results.push(`${name}: verified receipts, retired controls, no overflow`);
    }
    if (recording) {
      const scenes = [
        ['#overview', 'SafeSweep · verified public testnet walkthrough', 'An emergency alarm on Base Sepolia. An autonomous Reactive callback. One immutable safe wallet.'],
        ['.metric-grid', 'The destination is fixed; execution fees are separate', 'This completed incident protected 0.005 ETH. The guardian can raise the alarm but cannot redirect the funds.'],
        ['#activity', '1 · Guardian panic — Base block 63,083,237', 'PanicTriggered recorded 0.005 ETH and incident 0x0d1f99b2…7fe0f33. The panic transaction itself did not move the funds.'],
        ['#activity', '2 · Reactive execution — Lasna block 9,151,244', 'SweepRequested references the original panic hash. CallbackRequest encodes the same vault, incident and sweep function.'],
        ['#activity', '3 · Destination callback — Base block 63,083,245', 'Transaction 0x62397313…75bf3f emitted FundsSwept. The intended safe wallet gained exactly 0.005 ETH.'],
        ['#deployment', 'A reproducible trail, not just a green badge', 'The incident, three receipts and beneficiary balance delta are saved in the public proof report. Each stage has an explorer link.'],
        ['.protection-loop', 'Delivery verified · vault retired', 'All three live receipts match. Vault balance: zero. No new panic, funding or redeployment was used for this recording.'],
      ];
      for (const [selector, title, caption] of scenes) {
        await page.locator(selector).scrollIntoViewIfNeeded();
        await page.evaluate(({ title, caption }) => {
          let panel = document.getElementById('walkthrough-caption');
          if (!panel) { panel = document.createElement('aside'); panel.id = 'walkthrough-caption'; document.body.append(panel); }
          panel.style.cssText = 'position:fixed;bottom:18px;left:5%;width:90%;box-sizing:border-box;padding:18px 24px;background:#0a1512f5;border:1px solid #7bf2b2;border-radius:14px;z-index:100;color:#e9fff2;font:18px/1.5 system-ui;box-shadow:0 8px 40px #000';
          panel.replaceChildren();
          const label = document.createElement('small'); label.textContent = 'RECORDED EVIDENCE WALKTHROUGH · BASE SEPOLIA + LASNA'; label.style.cssText = 'display:block;color:#7bf2b2;font-size:10px;letter-spacing:1.5px';
          const heading = document.createElement('strong'); heading.textContent = title; heading.style.display = 'block';
          const body = document.createElement('div'); body.textContent = caption; body.style.cssText = 'font-size:15px;color:#bccfc6';
          panel.append(label, heading, body);
        }, { title, caption });
        await new Promise(resolve => setTimeout(resolve, 7500));
      }
      const video = page.video();
      await context.close();
      await video.saveAs(path.join(videoDir, 'safesweep-proof.webm'));
      await video.delete();
      results.push('Recorded captioned public-evidence walkthrough (no audio, no transactions)');
    }
    if (!live) {
      await context.route(/https:\/\/(sepolia\.base\.org|lasna-rpc\.rnk\.dev)/, async route => {
        const { method, params } = route.request().postDataJSON();
        const result = method === 'eth_getTransactionReceipt' && params[0] === manifest.callback_tx ? null : rpcResult(method, params);
        await route.fulfill({ json: { jsonrpc: '2.0', id: 1, result } });
      });
      await page.reload();
      await page.waitForFunction(() => document.querySelector('#heroState').textContent === 'Vault reports swept');
      assert.equal(await page.locator('[data-step="safe"]').evaluate(el => el.classList.contains('active')), false);
      results.push('missing destination receipt: no success state');
      await context.close();

      const controls = await browser.newContext();
      const configSource = fs.readFileSync(path.join(web, 'config.js'), 'utf8').replace(/panicTx: .*,/, 'panicTx: null,').replace(/reactiveTx: .*,/, 'reactiveTx: null,').replace(/callbackTx: .*,/, 'callbackTx: null,');
      await controls.route('**/config.js', route => route.fulfill({ body: configSource, contentType: 'text/javascript' }));
      await controls.route(/https:\/\/(sepolia\.base\.org|lasna-rpc\.rnk\.dev)/, async route => {
        const { method, params } = route.request().postDataJSON();
        await route.fulfill({ json: { jsonrpc: '2.0', id: 1, result: rpcResult(method, params, true) } });
      });
      await controls.addInitScript(({ guardian }) => {
        window.walletTest = { account: guardian, chain: '0x14a34', reject: false, sent: 0, listeners: {} };
        window.ethereum = {
          on: (event, cb) => { window.walletTest.listeners[event] = cb; },
          request: async ({ method }) => {
            if (window.walletTest.reject) throw new Error('User rejected connection');
            if (method === 'eth_requestAccounts') return [window.walletTest.account];
            if (method === 'eth_chainId') return window.walletTest.chain;
            if (method === 'eth_sendTransaction') { window.walletTest.sent++; throw new Error('Signing rejected in test'); }
            throw new Error('Unexpected wallet call');
          },
        };
      }, { guardian: manifest.guardian });
      const wallet = await controls.newPage();
      await wallet.goto(url);
      await wallet.waitForFunction(() => document.querySelector('#heroState').textContent === 'Monitoring');
      assert.equal(await wallet.locator('#panicButton').isDisabled(), true);
      await wallet.locator('#connectButton').click();
      await wallet.waitForFunction(() => !document.querySelector('#panicButton').disabled);
      await wallet.evaluate(() => { walletTest.chain = '0x1'; walletTest.listeners.chainChanged('0x1'); });
      assert.equal(await wallet.locator('#panicButton').isDisabled(), true);
      await wallet.evaluate(({ safe }) => { walletTest.account = safe; walletTest.listeners.accountsChanged([safe]); }, { safe: manifest.safe_wallet });
      await wallet.evaluate(() => { walletTest.chain = '0x14a34'; walletTest.listeners.chainChanged('0x14a34'); });
      assert.equal(await wallet.locator('#panicButton').isDisabled(), true);
      await wallet.evaluate(() => walletTest.listeners.accountsChanged([]));
      assert.equal(await wallet.locator('#connectButton').textContent(), 'Connect wallet');
      assert.equal(await wallet.evaluate(() => walletTest.sent), 0);
      await wallet.evaluate(() => { walletTest.reject = true; });
      await wallet.locator('#connectButton').click();
      await wallet.waitForFunction(() => document.querySelector('#toast').textContent.includes('rejected'));
      results.push('wallet stub: guardian connection, wrong chain, non-guardian, disconnect, rejection; zero sends');
      await controls.route(/https:\/\/(sepolia\.base\.org|lasna-rpc\.rnk\.dev)/, route => route.abort());
      await wallet.locator('#refreshButton').click();
      await wallet.waitForFunction(() => document.querySelector('#heroState').textContent === 'Awaiting contract data');
      assert.equal(await wallet.locator('#panicButton').isDisabled(), true);
      results.push('RPC outage: unavailable state and disabled panic');
      await controls.close();
    }
    assert.deepEqual(errors, []);
    console.log(JSON.stringify({ mode: live ? 'public RPC' : 'fixture RPC and wallet stub', results, pageErrors: errors }, null, 2));
  } finally {
    if (browser) await browser.close();
    server.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
