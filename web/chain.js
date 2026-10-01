// Cordon status page: reads Robinhood Chain in the visitor's browser. No wallet, no server.
const RPC = 'https://rpc.mainnet.chain.robinhood.com';
const GUARD = '0x469C46486d44eE02BB5A8d4FE341e55d13f5dF25';
const USDG = '0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168';
const SUPPLY_CONTROL = '0xdf5FfF9cb88B3cAb50572FAE73E2EB08599D25D4';
const PUBLISHED = '2026-09-25'; // KPMG report publication date; not onchain
const TIMEOUT_MS = 8000;
const REFRESH_MS = 60000;
const ANCHOR_MAX_AGE = 2 * 86400; // CordonGuard.ANCHOR_MAX_AGE
const DASH = '…';

// selectors from `cast sig`
const SEL = {
  status: '0x200d2ed2',
  latestAttestation: '0x24b6d96a',
  baselineInBand: '0x9b4eb90a',
  totalSupply: '0x18160ddd',
  pendingDefaultAdmin: '0xcf6eefb7',
  getAllSupplyControllerAddresses: '0x6190bfb0',
  getSupplyControllerConfig: '0xc248f7d6',
  anchor: '0xd3fb73b4',
  releaseSupply: '0xa0893ef2',
  releaseExecutableAt: '0xaa292742',
};

const STATUS_TEXT = [
  "HEALTHY. USDG supply and Paxos' controls on Robinhood Chain look normal.",
  'CAUTION. Something changed that a person should look at. Prices are not touched.',
  'HALT. USDG supply on this chain jumped more than 25%, read from the chain. Markets using Cordon discount USDG collateral.',
];
const LEVEL_WORD = ['HEALTHY', 'CAUTION', 'HALT'];
const REASONS = [
  'Supply on this chain rose more than 25% against the last hour or the last day.',
  'Supply on this chain rose more than 15% against the last hour.',
  'No supply snapshot from the last two hours. Anyone can add one by calling checkpoint().',
  'The set of addresses allowed to mint USDG changed.',
  "A change of USDG's admin is scheduled.",
  'The latest posted report shows reserves below tokens outstanding.',
  'No report posted for a period that ended in the last 62 days.',
  'Supply on this chain is above the posted total for all chains.',
];
const LOADING_TEXT = 'Reading Robinhood Chain…';
const ERROR_TEXT = 'Could not reach Robinhood Chain. Nothing here is a verdict. Try again.';

// ---------- ABI helpers (no library) ----------
const words = (hex) => {
  const h = hex.startsWith('0x') ? hex.slice(2) : hex;
  const out = [];
  for (let i = 0; i < h.length; i += 64) out.push(h.slice(i, i + 64));
  return out;
};
const big = (w) => BigInt('0x' + (w || '0'));
const addr = (w) => '0x' + w.slice(24);
const pad = (a) => a.toLowerCase().replace('0x', '').padStart(64, '0');

function decodeString(hex, byteOffset) {
  const h = hex.slice(2);
  const len = Number(big(h.slice(byteOffset * 2, byteOffset * 2 + 64)));
  const data = h.slice(byteOffset * 2 + 64, byteOffset * 2 + 64 + len * 2);
  const bytes = new Uint8Array(data.match(/../g)?.map((b) => parseInt(b, 16)) || []);
  return new TextDecoder().decode(bytes);
}

function decodeAttestation(hex) {
  const w = words(hex);
  const base = Number(big(w[0])) / 32; // offset of the tuple
  const t = w.slice(base);
  const strOffset = Number(big(t[5])); // relative to tuple start, in bytes
  return {
    periodEnd: Number(big(t[0])),
    postedAt: Number(big(t[1])),
    outstanding: big(t[2]),
    reserves: big(t[3]),
    sha: '0x' + t[4],
    uri: decodeString(hex, base * 32 + strOffset),
  };
}

// ---------- JSON-RPC ----------
async function batch(calls, signal) {
  const body = calls.map((c, i) => ({
    jsonrpc: '2.0', id: i, method: c.method || 'eth_call',
    params: c.params || [{ to: c.to, data: c.data }, 'latest'],
  }));
  const res = await fetch(RPC, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body), signal,
  });
  if (!res.ok) throw new Error('rpc http ' + res.status);
  const arr = await res.json();
  if (!Array.isArray(arr)) throw new Error('rpc: not a batch reply');
  const byId = new Map(arr.map((r) => [r.id, r]));
  return calls.map((_, i) => {
    const r = byId.get(i);
    if (!r || r.error) throw new Error('rpc call ' + i + ' failed');
    return r.result;
  });
}

async function readAll(signal) {
  const [statusHex, attHex, bandHex, supplyHex, tokPendHex, scPendHex, ctrlHex, block, anchorHex, relSupplyHex, relAtHex] = await batch([
    { to: GUARD, data: SEL.status },
    { to: GUARD, data: SEL.latestAttestation },
    { to: GUARD, data: SEL.baselineInBand },
    { to: USDG, data: SEL.totalSupply },
    { to: USDG, data: SEL.pendingDefaultAdmin },
    { to: SUPPLY_CONTROL, data: SEL.pendingDefaultAdmin },
    { to: SUPPLY_CONTROL, data: SEL.getAllSupplyControllerAddresses },
    { method: 'eth_getBlockByNumber', params: ['latest', false] },
    { to: GUARD, data: SEL.anchor },
    { to: GUARD, data: SEL.releaseSupply },
    { to: GUARD, data: SEL.releaseExecutableAt },
  ], signal);

  const sw = words(statusHex);
  const bw = words(bandHex);
  const cw = words(ctrlHex);
  const n = Number(big(cw[1]));
  const controllers = cw.slice(2, 2 + n).map(addr);

  const configs = n ? await batch(controllers.map((a) => ({
    to: SUPPLY_CONTROL, data: SEL.getSupplyControllerConfig + pad(a),
  })), signal) : [];

  const pending = (hex) => { const w = words(hex); return { next: addr(w[0]), at: Number(big(w[1])) }; };
  return {
    level: Number(big(sw[0])),
    reasons: big(sw[1]),
    attestation: decodeAttestation(attHex),
    band: { ok: big(bw[0]) === 1n, supply: big(bw[1]), timestamp: Number(big(bw[2])) },
    supply: BigInt(supplyHex),
    tokenPending: pending(tokPendHex),
    controlPending: pending(scPendHex),
    controllers: controllers.map((a, i) => {
      const w = words(configs[i]);
      return { address: a, cap: big(w[0]), refill: big(w[1]) };
    }),
    block: { number: Number(BigInt(block.number)), timestamp: Number(BigInt(block.timestamp)) },
    anchorSupply: big(words(anchorHex)[0]),
    anchorAt: Number(big(words(anchorHex)[1])),
    release: { supply: BigInt(relSupplyHex), at: Number(BigInt(relAtHex)) },
  };
}

// ---------- formatting ----------
const units = (v) => v / 1_000_000n; // 6 decimals -> whole units
const comma = (v) => v.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
function amount6(v) {
  const whole = units(v);
  if (whole >= 1n) return comma(whole);
  const frac = (v % 1_000_000n).toString().padStart(6, '0').replace(/0+$/, '');
  return '0.' + (frac || '0');
}
const isoDate = (sec) => new Date(sec * 1000).toISOString().slice(0, 10);
const utcTime = (sec) => new Date(sec * 1000).toISOString().slice(11, 19) + ' UTC';
const ago = (sec) => (sec < 3600 ? Math.round(sec / 60) + ' min' : (sec / 3600).toFixed(1) + ' h') + ' ago';
const short = (a) => a.slice(0, 6) + '…' + a.slice(-4);
const ZERO = '0x0000000000000000000000000000000000000000';
// percent change of `now` against `base`, 3 decimals of precision, as a Number
const changePct = (now, base) => Number(((now - base) * 100000n) / base) / 1000;
const signed = (p) => (p >= 0 ? '+' : '') + p.toFixed(1) + '%';

// ---------- DOM helpers ----------
const $ = (s) => document.querySelector(s);
const setText = (sel, text) => { const el = $(sel); if (el) el.textContent = text; };
function el(tag, className, text) {
  const n = document.createElement(tag);
  if (className) n.className = className;
  if (text !== undefined) n.textContent = text;
  return n;
}
const fig = (text) => el('span', 'mono', text);

// ---------- the line: gauge helpers ----------
let firstRead = true; // bars grow once, on the first successful read only

function setBar(bar, value, base) {
  const g = bar.parentElement;
  const lo = Number(g.style.getPropertyValue('--lo'));
  const hi = Number(g.style.getPropertyValue('--hi'));
  const v = Math.min(hi, Math.max(lo, value));
  bar.hidden = false;
  bar.style.setProperty('--a', Math.min(base, v));
  bar.style.setProperty('--b', Math.max(base, v));
  bar.classList.toggle('neg', v < base);
  bar.classList.toggle('over', value > hi);
  bar.classList.toggle('over-l', value < lo);
}

function noBar(sel, valueSel, words) {
  $(sel).hidden = true;
  const v = $(valueSel);
  v.textContent = words;
  v.classList.add('words');
}

function showValue(valueSel, text) {
  const v = $(valueSel);
  v.textContent = text;
  v.classList.remove('words');
}

function revealGauge(g) {
  if (firstRead) void g.offsetWidth; // commit the zero state so the first reveal animates
  g.classList.add('read');
}

function mintRow(c, supply, last) {
  const pct = supply > 0n ? Number((c.cap * 100000n) / supply) / 1000 : 0;
  const row = el('div', 'g-row' + (last ? ' has-lab' : ''));
  const link = el('a', null, short(c.address));
  link.href = 'https://robinhoodchain.blockscout.com/address/' + c.address;
  link.title = c.address;
  const id = el('span', 'g-id'); id.append(link);
  const cap = el('span', 'g-cap'); cap.append(id, 'Cap ' + amount6(c.cap) + ' USDG, refills ' + amount6(c.refill) + ' per second');
  const head = el('div', 'g-head'); head.append(cap, el('span', 'g-val', pct > 0 && pct < 0.01 ? '<0.01%' : pct.toFixed(1) + '%'));
  const g = el('div', 'gauge');
  g.style.cssText = '--lo:0;--hi:150;--t:25;--r:25';
  const bar = el('span', 'g-bar'); g.append(bar);
  setBar(bar, pct, 0);
  g.append(el('span', 'g-rule'));
  if (last) g.append(Object.assign(el('span', 'g-lab r', 'A mint this size halts')));
  row.append(head, g);
  return { row, gauge: g };
}

// ---------- rendering ----------
function renderEmpty() {
  document.querySelectorAll('[data-v]').forEach((e) => { e.textContent = DASH; });
  setText('#backing-line', DASH);
  setRead(DASH);
}

function setState(state, level) {
  const box = $('#status');
  box.dataset.state = state;
  const word = level !== undefined ? LEVEL_WORD[level] : undefined;
  if (word) document.body.dataset.level = word.toLowerCase();
  else delete document.body.dataset.level;
  $('#retry').hidden = state !== 'error';
  if (state === 'loading') { setVerdict('', LOADING_TEXT); $('#reasons').replaceChildren(); }
  if (state === 'error') { setVerdict('', ERROR_TEXT); $('#reasons').replaceChildren(); }
  document.body.dataset.stale = state === 'error' && box.dataset.had === '1' ? '1' : '0';
}

function setVerdict(word, rest) {
  setText('#status-word', word);
  setText('#status-rest', (word ? ' ' : '') + rest);
}

function renderVerdict(d) {
  $('#status').dataset.had = '1';
  setState('ready', d.level);
  const text = STATUS_TEXT[d.level] || STATUS_TEXT[1];
  const cut = text.indexOf('. ') + 1;
  setVerdict(text.slice(0, cut), text.slice(cut + 1));
  const items = REASONS.flatMap((text, bit) => (d.reasons & (1n << BigInt(bit)) ? [el('li', null, text)] : []));
  $('#reasons').replaceChildren(...items.slice(0, 3));
}

function renderTable(d) {
  const a = d.attestation;
  setText('[data-v="supply"]', comma(units(d.supply)) + ' USDG');
  const hourly = d.band.ok && d.band.supply > 0n;
  setText('[data-v="change"]', hourly ? signed(changePct(d.supply, d.band.supply)) : 'no baseline');
  const changed = (d.reasons & (1n << 3n)) !== 0n;
  setText('[data-v="minters"]', (changed ? 'changed' : 'unchanged') + ' (' + d.controllers.length + ')');
  const pend = [d.tokenPending, d.controlPending].filter((p) => p.next !== ZERO || p.at > 0);
  setText('[data-v="admin"]', pend.length ? 'pending ' + pend.map((p) => short(p.next)).join(', ') : 'none pending');
  const now = d.block.timestamp;
  setText('[data-v="snapshots"]', [
    d.band.ok ? 'hourly ' + ago(now - d.band.timestamp) : 'no hourly snapshot in range',
    d.anchorAt > 0 ? 'daily ' + ago(now - d.anchorAt) : 'no daily snapshot',
  ].join(', '));
  setText('[data-v="release"]', d.release.supply > 0n
    ? 'scheduled, can execute at ' + utcTime(d.release.at) + ' ' + isoDate(d.release.at)
    : 'none scheduled');
  setText('[data-v="age"]', a.periodEnd > 0 ? Math.floor((now - a.periodEnd) / 86400) + ' days' : 'none posted');
}

function renderSupplyGauges(d) {
  setText('#supply', comma(units(d.supply)));
  const hourly = d.band.ok && d.band.supply > 0n;
  const dailyOk = d.anchorSupply > 0n && d.anchorAt > 0 && d.block.timestamp - d.anchorAt <= ANCHOR_MAX_AGE;
  const rows = [['#bar-hourly', '#val-hourly', hourly, d.band.supply], ['#bar-daily', '#val-daily', dailyOk, d.anchorSupply]];
  for (const [bar, val, ok, base] of rows) {
    if (!ok) { noBar(bar, val, 'No snapshot in range'); continue; }
    const p = changePct(d.supply, base);
    setBar($(bar), p, 0);
    showValue(val, signed(p));
  }
}

function renderBacking(d) {
  const a = d.attestation;
  if (!(a.periodEnd > 0 && a.outstanding > 0n)) return;
  const ratio = Number((a.reserves * 1000000n) / a.outstanding) / 10000; // reserves as % of outstanding
  const excess = ratio - 100;
  $('#backing-line').replaceChildren(
    'On ', fig(isoDate(a.periodEnd)), ', KPMG attested ', fig(comma(units(a.outstanding))),
    ' USDG outstanding across all chains and ', fig('$' + comma(units(a.reserves))),
    ' in reserves, ', fig(Math.abs(excess).toFixed(2) + '%'), excess < 0 ? ' below par' : ' above par',
    '. Published ', PUBLISHED, '. Posted on chain by our reporter.',
  );
  const bar = $('#bar-backing');
  setBar(bar, ratio, 98);
  bar.classList.toggle('low', ratio < 100);
  showValue('#val-backing', ratio.toFixed(2) + '%');
  const link = $('#report-link');
  if (link && /^https:\/\//.test(a.uri)) { link.href = a.uri; link.textContent = a.uri.replace(/^https:\/\//, ''); }
  setText('#report-sha', a.sha);
}

function renderMinters(d) {
  const box = $('#minters');
  const made = d.controllers.map((c, i) => mintRow(c, d.supply, i === d.controllers.length - 1));
  box.replaceChildren(...made.map((m) => m.row));
  return made.map((m) => m.gauge);
}

// the sentence exists twice in the page (beside the button on desktop, after the gauges at 390); CSS shows one
function setRead(text) { document.querySelectorAll('.lastread').forEach((n) => { n.textContent = text; }); }

function renderMeta(d) {
  setRead('Read at ' + utcTime(d.block.timestamp) + ' from block ' + comma(BigInt(d.block.number)) + '. Re-read every 60 seconds.');
}

function renderData(d) {
  renderVerdict(d);
  renderTable(d);
  renderSupplyGauges(d);
  renderBacking(d);
  const mintGauges = renderMinters(d);
  renderMeta(d);
  const fixed = [...document.querySelectorAll('.gauge')].filter((g) => !g.closest('#minters'));
  [...fixed, ...mintGauges].forEach(revealGauge);
  firstRead = false;
}

// ---------- loop ----------
let inflight = null;
let timer = null;
async function run() {
  if (inflight) inflight.abort();
  const ctrl = new AbortController();
  inflight = ctrl;
  if ($('#status').dataset.had !== '1') setState('loading');
  const kill = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const d = await readAll(ctrl.signal);
    if (inflight === ctrl) renderData(d);
  } catch (e) {
    if (inflight === ctrl) { setState('error'); document.querySelectorAll('[data-static]').forEach(revealGauge); }
  } finally {
    clearTimeout(kill);
    if (inflight === ctrl) inflight = null;
  }
}

function start() {
  renderEmpty();
  setState('loading');
  $('#retry').addEventListener('click', () => { setState('loading'); run(); schedule(); });
  run();
  schedule();
}
function schedule() { clearInterval(timer); timer = setInterval(run, REFRESH_MS); }

start();
