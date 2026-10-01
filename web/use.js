// Cordon: guard a Morpho market. Reads Robinhood Chain in the browser; writes go through the
// visitor's own wallet. No server.
import { keccak_256 } from 'https://cdn.jsdelivr.net/npm/@noble/hashes@1.4.0/sha3/+esm';

const DEFAULT_RPC = 'https://rpc.mainnet.chain.robinhood.com';
const rpcParam = new URLSearchParams(location.search).get('rpc');
// A local fork may be named for testing; nothing else is accepted.
const RPC = rpcParam && /^http:\/\/(127\.0\.0\.1|localhost):\d+\/?$/.test(rpcParam) ? rpcParam : DEFAULT_RPC;
const CHAIN_ID = 4663;
const EXPLORER = 'https://robinhoodchain.blockscout.com';
const MORPHO = '0x9D53d5E3bd5E8d4Cbfa6DB1ca238AEA02E651010';
const USDG = '0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168';
const FACTORY = '0xA0A564D5C2D8c8E01191Cb70E39322E85B1045EF';
const GUARD = '0x1F82E5aB72B6Ec93e852533Ed9D021CbF51969AC';
const CREATE_MARKET = '0xac4b2400f169220b0c0afdde7a0b32e775ba727ea1cb30b35f935cdaab8683ac';
const CHUNK = 10_000_000;
const MAX_DISCOUNT_PCT = 50;

// selectors from `cast sig`
const SEL = {
  symbol: '0x95d89b41', decimals: '0x313ce567', guard: '0x7ceab3b1', market: '0x5c60e39a',
  create: '0x0ecaea73', predict: '0xe824f282', wrapperOf: '0xd5f4d5de', createMarket: '0x8c1358a2',
};

// ---------- ABI helpers ----------
const strip = (h) => (h.startsWith('0x') ? h.slice(2) : h);
const words = (hex) => strip(hex).match(/.{64}/g) || [];
const big = (w) => BigInt('0x' + (w || '0'));
const addr = (w) => '0x' + w.slice(24);
const pad = (v) => (typeof v === 'bigint' ? v.toString(16) : strip(v).toLowerCase()).padStart(64, '0');
const same = (a, b) => a.toLowerCase() === b.toLowerCase();
const hexToBytes = (h) => new Uint8Array(strip(h).match(/../g).map((b) => parseInt(b, 16)));
const toHex = (bytes) => '0x' + [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
const marketId = (m) => toHex(keccak_256(hexToBytes([m.loan, USDG, m.oracle, m.irm, m.lltv].map(pad).join(''))));

function decodeString(hex) {
  const w = words(hex);
  if (w.length < 3) return '';
  const len = Number(big(w[1]));
  return new TextDecoder().decode(hexToBytes(w.slice(2).join('').slice(0, len * 2)));
}

// ---------- JSON-RPC (reads) ----------
async function batch(calls) {
  const body = calls.map((c, i) => ({
    jsonrpc: '2.0', id: i, method: c.method || 'eth_call',
    params: c.params || [{ to: c.to, data: c.data }, 'latest'],
  }));
  const res = await fetch(RPC, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  if (!res.ok) throw new Error('Robinhood Chain answered ' + res.status);
  const arr = await res.json();
  const byId = new Map(arr.map((r) => [r.id, r]));
  return calls.map((_, i) => { const r = byId.get(i); return r && !r.error ? r.result : null; });
}

async function createMarketLogs() {
  const [head] = await batch([{ method: 'eth_blockNumber', params: [] }]);
  const latest = Number(BigInt(head));
  const ranges = [];
  for (let from = 0; from <= latest; from += CHUNK) ranges.push([from, Math.min(from + CHUNK - 1, latest)]);
  const results = await batch(ranges.map(([a, b]) => ({
    method: 'eth_getLogs',
    params: [{ address: MORPHO, topics: [CREATE_MARKET], fromBlock: '0x' + a.toString(16), toBlock: '0x' + b.toString(16) }],
  })));
  if (results.some((r) => r === null)) throw new Error('Could not read every block range of Morpho markets');
  return results.flat();
}

async function loadMarkets() {
  const logs = await createMarketLogs();
  const markets = logs.map((l) => {
    const w = words(l.data);
    return { id: l.topics[1], loan: addr(w[0]), collateral: addr(w[1]), oracle: addr(w[2]), irm: addr(w[3]), lltv: big(w[4]) };
  }).filter((m) => same(m.collateral, USDG));
  const extra = await batch(markets.flatMap((m) => [
    { to: m.loan, data: SEL.symbol }, { to: m.loan, data: SEL.decimals },
    { to: MORPHO, data: SEL.market + strip(m.id) }, { to: m.oracle, data: SEL.guard },
  ]));
  return markets.map((m, i) => {
    const [sym, dec, mkt, guard] = extra.slice(i * 4, i * 4 + 4);
    const mw = mkt ? words(mkt) : [];
    return {
      ...m, symbol: sym ? decodeString(sym) : '?', decimals: dec ? Number(BigInt(dec)) : 18,
      supplied: big(mw[0]), borrowed: big(mw[2]),
      // any oracle answering guard() is a Cordon wrapper (this guard or an earlier one)
      cordon: !!guard && guard.length >= 66,
      current: !!guard && guard.length >= 66 && same(addr(words(guard)[0]), GUARD),
    };
  });
}

// ---------- wallet (writes) ----------
const eth = () => window.ethereum;

async function connect() {
  if (!eth()) throw new Error('No browser wallet found. You can call the factory directly; see the status page.');
  const [account] = await eth().request({ method: 'eth_requestAccounts' });
  const chain = Number(await eth().request({ method: 'eth_chainId' }));
  if (chain !== CHAIN_ID) await switchChain();
  return account;
}

async function switchChain() {
  const chainId = '0x' + CHAIN_ID.toString(16);
  try {
    await eth().request({ method: 'wallet_switchEthereumChain', params: [{ chainId }] });
  } catch (e) {
    if (e.code !== 4902) throw e;
    await eth().request({ method: 'wallet_addEthereumChain', params: [{
      chainId, chainName: 'Robinhood Chain', rpcUrls: [DEFAULT_RPC],
      nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 }, blockExplorerUrls: [EXPLORER],
    }] });
  }
}

async function send(from, to, data) {
  const hash = await eth().request({ method: 'eth_sendTransaction', params: [{ from, to, data }] });
  for (let i = 0; i < 90; i++) {
    const [r] = await batch([{ method: 'eth_getTransactionReceipt', params: [hash] }]);
    if (r) {
      if (r.status !== '0x1') throw new Error('Transaction reverted: ' + hash);
      return hash;
    }
    await new Promise((ok) => setTimeout(ok, 2000));
  }
  throw new Error('No receipt after 3 minutes. Check ' + hash + ' on Blockscout.');
}

// ---------- page state ----------
const $ = (s) => document.querySelector(s);
const state = { markets: [], pick: null, account: null, wrapper: null };

const pct = (v) => (Number(v) / 1e16).toFixed(1) + '%';
function amount(v, decimals) {
  const n = Number(v) / 10 ** decimals;
  return n.toLocaleString('en-US', { maximumFractionDigits: n > 0 && n < 1 ? 6 : 2 });
}

function discountBps() {
  const v = Number($('#discount').value);
  return Number.isFinite(v) && v >= 0.01 && v <= MAX_DISCOUNT_PCT ? Math.round(v * 100) : null;
}

function link(href, text) { const a = document.createElement('a'); a.href = href; a.textContent = text; return a; }
const short = (a) => a.slice(0, 6) + '…' + a.slice(-4);

function renderMarkets() {
  const list = $('#markets');
  list.replaceChildren(...state.markets.map((m, i) => {
    const li = document.createElement('li');
    const label = document.createElement('label');
    const input = Object.assign(document.createElement('input'), { type: 'radio', name: 'market', value: i, disabled: m.cordon });
    input.addEventListener('change', () => { state.pick = m; state.wrapper = null; renderPlan(); });
    const name = document.createElement('span'); name.className = 'mk';
    name.textContent = m.symbol + ' loan · LLTV ' + pct(m.lltv);
    const meta = document.createElement('span'); meta.className = 'mm';
    meta.textContent = amount(m.supplied, m.decimals) + ' ' + m.symbol + ' supplied · ' + amount(m.borrowed, m.decimals) + ' borrowed · oracle ' + short(m.oracle)
      + (m.current ? ' · already guarded by Cordon' : m.cordon ? ' · wraps an earlier Cordon guard' : '');
    label.append(input, name, meta);
    li.append(label);
    return li;
  }));
  setText('#markets-note', state.markets.length + ' Morpho markets on Robinhood Chain take USDG as collateral.');
}

function setText(sel, t) { const el = $(sel); if (el) el.textContent = t; }

function renderPlan() {
  const m = state.pick;
  const bps = discountBps();
  $('#plan').hidden = !m;
  if (!m) return;
  const keep = bps === null ? null : (10000 - bps) / 10000;
  setText('#math', bps === null
    ? 'Choose a discount between 0.01% and ' + MAX_DISCOUNT_PCT + '%.'
    : 'On HALT, USDG collateral in this market is valued at ' + (keep * 100).toFixed(2).replace(/\.?0+$/, '') + '% of the price its oracle reports. '
      + 'New borrows then stop above ' + (Number(m.lltv) / 1e16 * keep).toFixed(1) + '% loan-to-value instead of ' + pct(m.lltv)
      + ', and any position above that line can be liquidated. Repaying and withdrawing keep working.');
  $('#do-wrap').disabled = bps === null || !state.account;
  $('#do-market').disabled = !state.wrapper || !state.account;
  setText('#wrap-out', state.wrapper ? 'Wrapper ' + state.wrapper : '');
}

function fail(sel, e) { setText(sel, e && e.message ? e.message : String(e)); }

// ---------- actions ----------
async function onConnect() {
  try {
    state.account = await connect();
    setText('#account', 'Connected ' + short(state.account));
    renderPlan();
  } catch (e) { fail('#account', e); }
}

async function onWrap() {
  const m = state.pick; const bps = discountBps();
  const args = pad(m.oracle) + pad(BigInt(bps));
  $('#do-wrap').disabled = true;
  setText('#wrap-out', 'Waiting for your wallet…');
  try {
    const [existing] = await batch([{ to: FACTORY, data: SEL.wrapperOf + args }]);
    const found = existing ? addr(words(existing)[0]) : null;
    if (found && BigInt(found) !== 0n) state.wrapper = found;
    else {
      await send(state.account, FACTORY, SEL.create + args);
      const [pred] = await batch([{ to: FACTORY, data: SEL.predict + args }]);
      state.wrapper = addr(words(pred)[0]);
    }
    renderPlan();
  } catch (e) { fail('#wrap-out', e); $('#do-wrap').disabled = false; }
}

async function onMarket() {
  const m = state.pick;
  const params = { loan: m.loan, oracle: state.wrapper, irm: m.irm, lltv: m.lltv };
  const id = marketId(params);
  $('#do-market').disabled = true;
  setText('#market-out', 'Waiting for your wallet…');
  try {
    const [mkt] = await batch([{ to: MORPHO, data: SEL.market + strip(id) }]);
    const exists = mkt && big(words(mkt)[4]) > 0n;
    if (!exists) await send(state.account, MORPHO, SEL.createMarket + [m.loan, USDG, params.oracle, m.irm, m.lltv].map(pad).join(''));
    const out = $('#market-out');
    out.replaceChildren((exists ? 'This market already exists. ' : 'Market created. ') + 'Id ', link(EXPLORER + '/address/' + MORPHO, id),
      '. Lenders supply to it on Morpho like any other market.');
  } catch (e) { fail('#market-out', e); $('#do-market').disabled = false; }
}

async function start() {
  $('#connect').addEventListener('click', onConnect);
  $('#discount').addEventListener('input', () => { state.wrapper = null; renderPlan(); });
  $('#do-wrap').addEventListener('click', onWrap);
  $('#do-market').addEventListener('click', onMarket);
  try {
    state.markets = await loadMarkets();
    renderMarkets();
  } catch (e) {
    fail('#markets-note', e);
  }
}

start();
