// Cordon status page: reads Robinhood Chain in the visitor's browser. No wallet, no server.
const RPC = 'https://rpc.mainnet.chain.robinhood.com';
const GUARD = '0x469C46486d44eE02BB5A8d4FE341e55d13f5dF25';
const USDG = '0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168';
const SUPPLY_CONTROL = '0xdf5FfF9cb88B3cAb50572FAE73E2EB08599D25D4';
const PUBLISHED = '2026-09-25'; // KPMG report publication date; not onchain
const TIMEOUT_MS = 8000;
const REFRESH_MS = 60000;
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
  "HEALTHY. Nothing in Paxos' controls or posted backing needs attention.",
  'CAUTION. Something changed that a human should look at. Prices are not touched.',
  'HALT. USDG supply on this chain jumped more than 25%, read from the chain itself. Markets using Cordon discount USDG collateral.',
];
const LEVEL_WORD = ['HEALTHY', 'CAUTION', 'HALT'];
const REASONS = [
  'Supply on this chain rose more than 25% against the last hour or the last day.',
  'Supply on this chain rose more than 15% within an hour.',
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

// ---------- rendering ----------
const $ = (s) => document.querySelector(s);
const setText = (sel, text) => { const el = $(sel); if (el) el.textContent = text; };

function renderEmpty() {
  document.querySelectorAll('[data-v]').forEach((el) => { el.textContent = DASH; });
  setText('#backing-line', DASH);
  setText('#read-meta', DASH);
}

function setState(state, level) {
  const box = $('#status');
  box.dataset.state = state;
  const word = level !== undefined ? LEVEL_WORD[level] : undefined;
  if (word) document.body.dataset.level = word.toLowerCase();
  else delete document.body.dataset.level;
  $('#retry').hidden = state !== 'error';
  if (state === 'loading') { setText('#status-text', LOADING_TEXT); $('#reasons').replaceChildren(); }
  if (state === 'error') { setText('#status-text', ERROR_TEXT); $('#reasons').replaceChildren(); }
  document.body.dataset.stale = state === 'error' && $('#status').dataset.had === '1' ? '1' : '0';
}

function renderData(d) {
  const box = $('#status');
  box.dataset.had = '1';
  setState('ready', d.level);
  setText('#status-text', STATUS_TEXT[d.level] || STATUS_TEXT[1]);
  const list = $('#reasons');
  list.replaceChildren(...REASONS.flatMap((text, bit) => {
    if (!(d.reasons & (1n << BigInt(bit)))) return [];
    const li = document.createElement('li');
    li.dataset.kind = bit >= 5 ? 'reported' : 'trustless';
    const code = document.createElement('code');
    code.textContent = 'bit ' + bit;
    li.append(code, document.createTextNode(' ' + text));
    return [li];
  }));

  const a = d.attestation;
  // What we read
  setText('[data-v="supply"]', comma(units(d.supply)) + ' USDG');
  if (d.band.ok && d.band.supply > 0n) {
    const bps = Number(((d.supply - d.band.supply) * 100000n) / d.band.supply) / 1000;
    setText('[data-v="change"]', (bps >= 0 ? '+' : '') + bps.toFixed(1) + '%');
  } else {
    setText('[data-v="change"]', 'no baseline');
  }
  const changed = (d.reasons & (1n << 3n)) !== 0n;
  setText('[data-v="minters"]', (changed ? 'changed' : 'unchanged') + ' (' + d.controllers.length + ')');
  const pend = [d.tokenPending, d.controlPending].filter((p) => p.next !== ZERO || p.at > 0);
  setText('[data-v="admin"]', pend.length ? 'pending ' + pend.map((p) => short(p.next)).join(', ') : 'none pending');
  const now = d.block.timestamp;
  const snaps = [];
  snaps.push(d.band.ok ? 'hourly ' + ago(now - d.band.timestamp) : 'no hourly snapshot in range');
  snaps.push(d.anchorAt > 0 ? 'daily ' + ago(now - d.anchorAt) : 'no daily snapshot');
  setText('[data-v="snapshots"]', snaps.join(' · '));
  setText('[data-v="release"]', d.release.supply > 0n
    ? 'scheduled, can execute at ' + utcTime(d.release.at) + ' ' + isoDate(d.release.at)
    : 'none scheduled');
  if (a.periodEnd > 0) {
    const days = Math.floor((d.block.timestamp - a.periodEnd) / 86400);
    setText('[data-v="age"]', days + ' days');
  } else {
    setText('[data-v="age"]', 'none posted');
  }

  // Backing, as attested
  if (a.periodEnd > 0 && a.outstanding > 0n) {
    const excess = Number(((a.reserves - a.outstanding) * 1000000n) / a.outstanding) / 10000;
    const line = $('#backing-line');
    line.replaceChildren(
      'On ', fig(isoDate(a.periodEnd)), ', KPMG attested ', fig(comma(units(a.outstanding))),
      ' USDG outstanding across all chains and ', fig('$' + comma(units(a.reserves))),
      ' in reserves (', fig(excess.toFixed(2) + '%'), ' above par). Published ', fig(PUBLISHED), '.',
    );
    const link = $('#report-link');
    if (link && /^https:\/\//.test(a.uri)) { link.href = a.uri; link.textContent = a.uri.replace(/^https:\/\//, ''); }
    setText('#report-sha', a.sha);
  }

  // Who can mint
  const body = $('#minters');
  body.replaceChildren(...d.controllers.map((c) => {
    const tr = document.createElement('tr');
    const td1 = document.createElement('td');
    const l = document.createElement('a');
    l.href = 'https://robinhoodchain.blockscout.com/address/' + c.address;
    l.textContent = short(c.address);
    l.title = c.address;
    td1.className = 'm';
    td1.append(l);
    const td2 = document.createElement('td'); td2.className = 'v'; td2.textContent = amount6(c.cap) + ' USDG';
    const td3 = document.createElement('td'); td3.className = 'v'; td3.textContent = amount6(c.refill) + ' / s';
    tr.append(td1, td2, td3);
    return tr;
  }));

  setText('#read-meta', 'block ' + comma(BigInt(d.block.number)) + ' · ' + utcTime(d.block.timestamp));
}

function fig(text) { const s = document.createElement('span'); s.className = 'fig'; s.textContent = text; return s; }

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
    if (inflight === ctrl) setState('error');
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
