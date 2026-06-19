/* ============================================================================
   Leyne — design sandbox app logic (vanilla JS, no build step)
   ----------------------------------------------------------------------------
   Renders the iOS app's screens from data so you can iterate the DESIGN in the
   browser. Visuals live in styles.css (tokens). This file owns: sample data,
   the reusable components (badge / stop card / arrival row / crowd meter /
   ETA), the five tabs + drill-downs, and a tiny nav stack.
   ========================================================================== */

// ─── Icons (inline SVG, currentColor) ──────────────────────────────────────
const I = {
  bus:   `<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><path d="M4 5a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2v2a1 1 0 0 1-2 0v-1H8v1a1 1 0 0 1-2 0v-2a2 2 0 0 1-2-2V5zm2 1v4h12V6H6zm1.5 8a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3zm9 0a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3z"/></svg>`,
  tram:  `<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><path d="M7 3h10a3 3 0 0 1 3 3v9a3 3 0 0 1-3 3l1.3 1.9a.7.7 0 0 1-1.1.8L15.6 18H8.4l-1.5 2.7a.7.7 0 0 1-1.1-.8L7 18a3 3 0 0 1-3-3V6a3 3 0 0 1 3-3zM6.5 7v4h11V7h-11zM8.2 16a1.2 1.2 0 1 0 0-2.4 1.2 1.2 0 0 0 0 2.4zm7.6 0a1.2 1.2 0 1 0 0-2.4 1.2 1.2 0 0 0 0 2.4z"/></svg>`,
  star:  `<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2.5l2.9 5.9 6.5.9-4.7 4.6 1.1 6.5L12 17.8 6.2 20.4l1.1-6.5L2.6 9.3l6.5-.9z"/></svg>`,
  search:`<svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.2-4.2"/></svg>`,
  bell:  `<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2a6 6 0 0 0-6 6c0 5-2 6-2 7h16c0-1-2-2-2-7a6 6 0 0 0-6-6zm0 20a3 3 0 0 0 3-3H9a3 3 0 0 0 3 3z"/></svg>`,
  pin:   `<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2a6 6 0 0 0-6 6c0 4.5 6 12 6 12s6-7.5 6-12a6 6 0 0 0-6-6zm0 8.4A2.4 2.4 0 1 1 12 5.6a2.4 2.4 0 0 1 0 4.8z"/></svg>`,
  loc:   `<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><path d="M21 3L3 10.6l7.4 2.5L13 21z"/></svg>`,
  walk:  `<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><circle cx="13" cy="4" r="2"/><path d="M11 7.5l-2.6 1.7a2 2 0 0 0-.9 1.7V16a1 1 0 0 0 2 0v-3.3l1.4-.9-1 4.7 1.5 1 1.6 4a1 1 0 0 0 1.9-.7l-1.7-4.4-1.3-1 .8-3.4 1 2a1 1 0 0 0 .8.5l2.4.2a1 1 0 0 0 .1-2l-2-.2-1.4-2.8a2 2 0 0 0-2.6-.9z"/></svg>`,
  chev:  `<svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M9 5l7 7-7 7"/></svg>`,
  back:  `<svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M15 5l-7 7 7 7"/></svg>`,
  eye:   `<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><path d="M12 5C5 5 1 12 1 12s4 7 11 7 11-7 11-7-4-7-11-7zm0 11a4 4 0 1 1 0-8 4 4 0 0 1 0 8z"/></svg>`,
  person:`<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="6" r="3.3"/><path d="M5 21v-1.5a7 7 0 0 1 14 0V21z"/></svg>`,
  clock: `<svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M12 7.5v5l3 2"/></svg>`,
  gear:  `<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><path d="M12 8.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7zm9 3.5q0-.6-.1-1.2l1.9-1.5-1.9-3.3-2.3 1a7 7 0 0 0-2-1.2L16.1 3H8l-.5 2.6a7 7 0 0 0-2 1.2l-2.3-1L1.3 9.1l1.9 1.5q-.1.6-.1 1.4t.1 1.2l-1.9 1.5 1.9 3.3 2.3-1c.6.5 1.3.9 2 1.2L8 21h4.1l.5-2.6c.7-.3 1.4-.7 2-1.2l2.3 1 1.9-3.3-1.9-1.5q.1-.6.1-1.2z"/></svg>`,
  sort:  `<svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 7h11M4 12h8M4 17h5M17 9l3-3 3 3M20 6v12"/></svg>`,
};
function ic(name, cls = '') { return I[name].replace('class="ico"', `class="ico ${cls}"`); }

// ─── Sample SG data ─────────────────────────────────────────────────────────
const STOPS = [
  { code: '53061', name: 'Bef Bishan Stn', road: 'Bishan Rd', walk: 3, dist: 240, saved: true, arr: [
    { no: '88',  dest: 'Clementi Int',  etas: [2, 9, 20],  load: 'sea', mon: true,  wab: true,  deck: 'DD' },
    { no: '156', dest: 'Toa Payoh Int', etas: [9, 19],     load: 'sda', mon: true },
    { no: '410', dest: 'Bishan Int',    etas: [0, 16],     load: 'lsd', mon: false },
    { no: '13',  dest: 'Tampines Int',  etas: [12, 24],    load: 'sea', mon: true,  wab: true },
  ]},
  { code: '53069', name: 'Opp Bishan Stn', road: 'Bishan Rd', walk: 4, dist: 310, saved: false, arr: [
    { no: '52', dest: 'Toa Payoh Int', etas: [1],      load: 'sda', mon: true },
    { no: '59', dest: 'Hougang Ctrl',  etas: [6, 14],  load: 'sea', mon: true,  wab: true },
  ]},
  { code: '59039', name: 'Blk 217',        road: 'Ang Mo Kio Ave 1', walk: 6, dist: 480, saved: false, arr: [
    { no: '162',  dest: 'Marymount',  etas: [3, 11], load: 'sea', mon: true },
    { no: '162M', dest: 'AMK Int',    etas: [8],     load: 'sda', mon: false },
  ]},
];
const stopByCode = Object.fromEntries(STOPS.map(s => [s.code, s]));

const MRT_LINES = [
  { code: 'NS', name: 'North South',        v: '--ns', crowd: 'sda' },
  { code: 'EW', name: 'East West',          v: '--ew', crowd: 'sea' },
  { code: 'NE', name: 'North East',         v: '--ne', crowd: 'lsd' },
  { code: 'CC', name: 'Circle',             v: '--cc', crowd: 'sda' },
  { code: 'DT', name: 'Downtown',           v: '--dt', crowd: 'sea' },
  { code: 'TE', name: 'Thomson-East Coast', v: '--te', crowd: 'sea' },
];
const MRT_STATIONS = [
  { name: 'Bishan',     codes: [['NS','NS17'],['CC','CC15']], walk: 5 },
  { name: 'Marina Bay', codes: [['NS','NS27'],['TE','TE20'],['CC','CE2']], walk: 12 },
];
const ALERTS = [
  { v: '--ns', code: 'NSL', title: 'Delay: Jurong East → Bukit Batok', detail: 'Train fault. Add ~15 min to your trip. Recovery in progress.' },
  { v: '--cc', code: 'CCL', title: 'Lift maintenance · Bishan', detail: 'Exit B lift out of service until 6:00 PM today.' },
];
const RECENTS = ['Bishan', '88', 'Orchard', '156'];

// ─── Component helpers (return HTML strings) ────────────────────────────────
function fmtEta(min) {
  if (min <= 0) return { big: 'Arr', unit: 'now', soon: true };
  return { big: String(min), unit: 'min', soon: min <= 1 };
}
function badge(no, size = 'md', inv = false) {
  return `<div class="badge badge--${size}${inv ? ' badge--inv' : ''}">${no}</div>`;
}
function etaCol(min, mon, lead) {
  const e = fmtEta(min);
  const tilde = (!mon && min > 0) ? `<span class="eta-tilde">~</span>` : '';
  const dim = (!mon && !e.soon) ? ' eta-dim' : '';
  return `<div class="etacol${dim}">
      <div class="eta-big${e.soon && lead ? ' is-soon' : ''}">${tilde}${e.big}</div>
      <div class="eta-unit">${e.unit}</div>
    </div>`;
}
const LOAD = { sea: { n: 1, cls: '',     label: 'Seats available' },
               sda: { n: 2, cls: 'mid',  label: 'Standing available' },
               lsd: { n: 3, cls: 'full', label: 'Limited standing' },
               none:{ n: 0, cls: '',     label: 'Crowd unknown' } };
function crowd(load, withLabel = false) {
  const m = LOAD[load] || LOAD.none;
  let g = '';
  for (let i = 0; i < 3; i++) g += ic('person', i < m.n ? `on ${m.cls}` : 'off');
  return `<span class="crowd">${g}${withLabel ? `<span class="crowd__label">${m.label}</span>` : ''}</span>`;
}
function arrivalRow(svc, stopCode) {
  const cols = svc.etas.slice(0, 3).map((m, i) => etaCol(m, svc.mon, i === 0)).join('');
  const feat = [];
  if (svc.mon) {
    if (svc.wab)  feat.push('WAB');
    if (svc.deck) feat.push(svc.deck);
  }
  const featRow = feat.length ? `<div class="arow__feat">${feat.map(f => `<span class="eyebrow" style="opacity:.6">${f}</span>`).join('')}</div>` : '';
  return `<div class="arow" data-nav="bus:${stopCode}:${svc.no}">
      ${badge(svc.no, 'md')}
      <div class="arow__dest"><div class="d">${svc.dest}</div>${featRow}<div style="margin-top:4px">${crowd(svc.load)}</div></div>
      <div class="etacols">${cols}</div>
    </div>`;
}
function stopCard(stop, opts = {}) {
  const soonest = stop.arr[0];
  const e = soonest ? fmtEta(soonest.etas[0]) : null;
  const soonTxt = e ? `${(!soonest.mon && soonest.etas[0] > 0) ? '~ ' : ''}${e.big === 'Arr' ? 'Arr' : e.big + ' min'}` : 'No live arrivals';
  const chips = stop.arr.slice(0, 4).map(s => {
    const ce = fmtEta(s.etas[0]);
    return `<div class="chip"><div class="chip__no">${s.no}</div><div class="chip__eta">${ce.big}${ce.big === 'Arr' ? '' : 'm'}</div></div>`;
  }).join('');
  const more = stop.arr.length > 4 ? `<div class="chip chip--more">+${stop.arr.length - 4}</div>` : '';
  return `<div class="card stopcard${opts.hi ? ' card--hi' : ''}" data-nav="stop:${stop.code}">
      ${opts.badge ? `<span class="pill-badge">${opts.badge}</span>` : ''}
      <div class="stopcard__head">
        <div class="tile">${ic('pin')}</div>
        <div class="stopcard__id">
          <div class="stopcard__name">${stop.name}${stop.saved ? `<span class="star">${ic('star')}</span>` : ''}</div>
          <div class="stopcard__sub">Stop ${stop.code} · ${stop.road}</div>
          <div class="stopcard__meta">
            <span class="walk">${ic('walk')} ${stop.walk} min</span>
            <span class="sep">·</span>
            <span class="bus">${ic('bus')} ${soonTxt}</span>
          </div>
        </div>
        <span class="chev">${ic('chev')}</span>
      </div>
      ${stop.arr.length ? `<div class="chips">${chips}${more}</div>` : `<div class="quiet">No live arrivals right now</div>`}
    </div>`;
}
function topbar(opts = {}) {
  const right = (opts.right || []).join('');
  return `<div class="topbar">
      <div class="iconbtn" data-back>${ic('back')}</div>
      <div class="topbar__right">${right}</div>
    </div>`;
}

// ─── Screens ────────────────────────────────────────────────────────────────
function screenHome() {
  const now = new Date();
  const h = now.getHours();
  const greet = h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening';
  const clock = now.toLocaleTimeString('en-SG', { hour: 'numeric', minute: '2-digit' });
  const closest = STOPS[0];
  const rest = STOPS.slice(1);
  return `<div class="page">
    <div class="t-greeting"><b>${greet}</b> · <span class="clock">${clock}</span>
      <span data-nav="settings" style="margin-left:auto;color:var(--dim);cursor:pointer">${ic('gear')}</span>
    </div>
    <div class="t-title">Stops near you</div>
    <div class="statusline">
      ${ic('loc','ico--blue')}
      <span class="live-badge"><span class="live-dot"></span><span class="eyebrow">LIVE</span></span>
      <span>· updated 8s ago</span>
    </div>
    ${ALERTS.slice(0,1).map(alertCard).join('')}
    ${stopCard(closest, { hi: true, badge: 'Closest stop' })}
    <div class="t-section">More stops</div>
    ${rest.map(s => stopCard(s)).join('')}
  </div>`;
}
function screenStop(code) {
  const s = stopByCode[code];
  if (!s) return `<div class="page">${topbar()}<div class="quiet">Unknown stop.</div></div>`;
  const rows = s.arr.map(svc => arrivalRow(svc, code)).join('');
  return `<div class="page">
    ${topbar({ right: [`<div class="iconbtn${s.saved ? ' iconbtn--on' : ''}" data-toggle>${ic('star')}</div>`] })}
    <div class="detail-title">${s.name}</div>
    <div class="detail-sub">Stop ${s.code} · ${s.road}</div>
    <div class="detail-meta">
      <span style="color:var(--soon);display:inline-flex;gap:3px;align-items:center">${ic('walk')} ${s.walk} min walk · ${s.dist} m</span>
      <span class="live-badge"><span class="live-dot"></span><span class="eyebrow">LIVE</span></span>
    </div>
    <div class="t-section" style="display:flex;align-items:center">Arrivals
      <span class="sortpill">${ic('sort')} By ETA</span>
    </div>
    ${rows}
    <div class="footer-note">Bus arrival times are estimates from LTA DataMall.</div>
  </div>`;
}
function screenBus(code, no) {
  const s = stopByCode[code];
  const svc = s && s.arr.find(a => a.no === no);
  if (!svc) return `<div class="page">${topbar()}<div class="quiet">Unknown service.</div></div>`;
  const e = fmtEta(svc.etas[0]);
  const status = svc.mon ? 'LIVE' : 'SCHEDULED';
  const route = ['Bishan Int', 'Blk 511', 'Opp CPF Bldg', s.name, 'Sin Ming Ave', 'Thomson Plaza', svc.dest];
  const youIdx = 3;
  return `<div class="page">
    ${topbar({ right: [`<div class="iconbtn">${ic('eye')}</div>`, `<div class="iconbtn">${ic('star')}</div>`] })}
    <div style="display:flex;align-items:center;gap:12px">
      ${badge(svc.no, 'lg')}
      <div><div class="detail-title" style="font-size:24px">${svc.dest}</div>
      <div class="detail-sub">from ${s.name}</div></div>
    </div>
    <div class="hero">
      <div class="statuspill"><span class="live-dot" style="${svc.mon?'':'background:var(--faint);animation:none'}"></span> ${status}</div>
      <div class="hero__eta">${(!svc.mon && svc.etas[0]>0)?'<span class="eta-tilde">~</span>':''}${e.big}${e.big==='Arr'?'':' <small>min</small>'}</div>
      <div style="margin-top:6px">${crowd(svc.load, true)}</div>
    </div>
    <div class="t-section">Route</div>
    <div class="card">
      <div class="routeline">
        ${route.map((r, i) => `<div class="rl-stop ${i<youIdx?'is-past':''} ${i===youIdx?'is-you':''}"><span class="rl-line"></span><span class="rl-dot"></span><span class="rl-name">${r}${i===youIdx?' · your stop':''}</span></div>`).join('')}
      </div>
    </div>
    <div class="t-section">If you miss this one</div>
    <div class="card"><div style="display:flex;align-items:center;gap:12px">${badge(svc.no,'sm')}<div style="flex:1" class="rl-name">${svc.dest}</div><div class="eta-big">${svc.etas[1]??'–'}<span class="eta-unit" style="margin-left:3px">min</span></div></div></div>
  </div>`;
}
function screenSearch() {
  const recents = RECENTS.map(r => `<div class="listrow" data-nav="${/^\d/.test(r)?'home':'home'}">${ic('clock')}<span style="flex:1">${r}</span></div>`).join('');
  return `<div class="page">
    <div class="t-title t-title--sm">Search</div>
    <div class="card" style="padding:2px 14px">
      <div class="searchfield">${ic('search')}<input placeholder="Search for stops, services or places" /></div>
    </div>
    <div class="segmented">
      <button class="seg is-on">All</button><button class="seg">Stops</button>
      <button class="seg">Buses</button><button class="seg">MRT</button>
    </div>
    <div class="t-section" style="margin-top:6px">Recent</div>
    ${recents}
  </div>`;
}
function screenSaved() {
  const stops = STOPS.filter(s => s.saved);
  return `<div class="page">
    <div class="t-title">Saved</div>
    <div class="segmented">
      <button class="seg is-on">All</button><button class="seg">Stops</button>
      <button class="seg">Buses</button><button class="seg">MRT</button>
    </div>
    <div class="t-section">Stops</div>
    ${stops.length ? stops.map(s => stopCard(s)).join('') : '<div class="quiet">No saved stops yet.</div>'}
    <div class="t-section">Services</div>
    <div class="card"><div style="display:flex;align-items:center;gap:12px">${badge('88','sm')}<div style="flex:1"><div class="rl-name">To Clementi Int</div><div class="stopcard__sub">at Bef Bishan Stn</div></div><div class="eta-big">2<span class="eta-unit" style="margin-left:3px">min</span></div></div></div>
    <div class="nudge">${ic('search')} Add a stop or service</div>
  </div>`;
}
function screenMrt() {
  const lineTile = (l) => `<div class="card mrt-tile"><span class="mrt-pill" style="background:var(${l.v})">${l.code}</span><span class="mrt-tile__name" style="flex:1">${l.name}</span>${crowd(l.crowd)}<span class="chev">${ic('chev')}</span></div>`;
  const stationTile = (st) => `<div class="card mrt-tile"><span class="mrt-tile__codes">${st.codes.map(c => `<span class="mrt-pill" style="background:var(--${c[0].toLowerCase()})">${c[1]}</span>`).join('')}</span><span class="mrt-tile__name" style="flex:1">${st.name}</span><span class="stopcard__sub">${st.walk}m</span></div>`;
  return `<div class="page">
    <div class="t-title">MRT</div>
    ${alertCard(ALERTS[0])}
    <div class="t-section">Closest to you</div>
    ${MRT_STATIONS.map(stationTile).join('')}
    <div class="t-section">Lines</div>
    ${MRT_LINES.map(lineTile).join('')}
  </div>`;
}
function screenAlerts() {
  return `<div class="page">
    <div class="t-title">Alerts</div>
    <div class="t-section">Network</div>
    ${ALERTS.map(alertCard).join('')}
    <div class="t-section">Your buses</div>
    <div class="watching">
      <div class="watching__head">WATCHING · alerted 3 &amp; 1 min before</div>
      <div class="watching__row"><div class="watching__ic">${ic('eye')}</div><div style="flex:1"><div class="rl-name">Bus 88 · To Clementi Int</div><div class="stopcard__sub">at Bef Bishan Stn</div></div></div>
    </div>
  </div>`;
}
function screenSettings() {
  return `<div class="page">
    ${topbar()}
    <div class="t-title">Settings</div>
    <div class="t-section">Preferences</div>
    <div class="set-group">
      <div class="set-row"><span class="set-row__label">Appearance</span><span class="set-row__value">System</span><span class="chev">${ic('chev')}</span></div>
      <div class="set-row"><span class="set-row__label">Haptics</span><span class="toggle is-on" data-toggle-cls></span></div>
    </div>
    <div class="t-section">Notifications</div>
    <div class="set-group">
      <div class="set-row"><span class="set-row__label">Arrival alerts</span><span class="toggle is-on" data-toggle-cls></span></div>
      <div class="set-row"><span class="set-row__label">Bus-coming alerts</span><span class="toggle" data-toggle-cls></span></div>
    </div>
    <div class="footer-note">Leyne v2.8.5 · Data from LTA DataMall.</div>
  </div>`;
}
function alertCard(a) {
  return `<div class="alert-card"><span class="alert-card__edge" style="background:var(${a.v})"></span>
    <div class="alert-card__body"><div class="alert-card__title">${a.code}: ${a.title}</div><div class="alert-card__detail">${a.detail}</div></div></div>`;
}

// ─── Tabs + navigation stack ────────────────────────────────────────────────
const TABS = [
  { id: 'bus',    label: 'Bus',    icon: 'bus',    root: 'home' },
  { id: 'mrt',    label: 'MRT',    icon: 'tram',   root: 'mrt' },
  { id: 'saved',  label: 'Saved',  icon: 'star',   root: 'saved' },
  { id: 'search', label: 'Search', icon: 'search', root: 'search' },
  { id: 'alerts', label: 'Alerts', icon: 'bell',   root: 'alerts', badge: ALERTS.length },
];
const RENDER = {
  home: screenHome, mrt: screenMrt, saved: screenSaved, search: screenSearch,
  alerts: screenAlerts, settings: screenSettings,
  stop: (p) => screenStop(p.code), bus: (p) => screenBus(p.code, p.no),
};
let state = { tab: 'bus', stack: [{ screen: 'home' }] };

function render() {
  const top = state.stack[state.stack.length - 1];
  document.getElementById('screen').innerHTML = RENDER[top.screen](top);
  document.getElementById('screen').scrollTop = 0;
  renderTabbar();
}
function renderTabbar() {
  document.getElementById('tabbar').innerHTML = TABS.map(t => `
    <div class="tab ${state.tab === t.id ? 'is-on' : ''}" data-tab="${t.id}">
      ${ic(t.icon)}<span class="tab__label">${t.label}</span>
      ${t.badge ? `<span class="tab__badge">${t.badge}</span>` : ''}
    </div>`).join('');
}
function switchTab(id) {
  const t = TABS.find(x => x.id === id); if (!t) return;
  state = { tab: id, stack: [{ screen: t.root }] };
  render();
}
function navigate(screen, params = {}) {
  if (screen === 'home') { switchTab('bus'); return; }
  state.stack.push({ screen, ...params });
  render();
}
function back() { if (state.stack.length > 1) { state.stack.pop(); render(); } }

// ─── Event delegation ───────────────────────────────────────────────────────
document.addEventListener('click', (ev) => {
  const tab = ev.target.closest('[data-tab]');
  if (tab) return switchTab(tab.dataset.tab);
  const backBtn = ev.target.closest('[data-back]');
  if (backBtn) return back();
  const nav = ev.target.closest('[data-nav]');
  if (nav) {
    const [screen, code, no] = nav.dataset.nav.split(':');
    return navigate(screen, { code, no });
  }
  const tog = ev.target.closest('[data-toggle]');
  if (tog) { tog.classList.toggle('iconbtn--on'); return; }
  const togc = ev.target.closest('[data-toggle-cls]');
  if (togc) { togc.classList.toggle('is-on'); return; }
  const seg = ev.target.closest('.seg');
  if (seg) { seg.parentElement.querySelectorAll('.seg').forEach(s => s.classList.remove('is-on')); seg.classList.add('is-on'); return; }
});

// ─── Controls: theme + dynamic type + clock ─────────────────────────────────
document.getElementById('themeBtn').addEventListener('click', () => {
  const r = document.documentElement;
  r.dataset.theme = r.dataset.theme === 'dark' ? 'light' : 'dark';
});
let dyna = 1;
document.getElementById('dynaBtn').addEventListener('click', () => {
  dyna = dyna >= 1.3 ? 1 : dyna + 0.1;
  document.documentElement.style.setProperty('--dyna', dyna.toFixed(2));
});
(function clock() {
  const t = new Date().toLocaleTimeString('en-SG', { hour: 'numeric', minute: '2-digit' });
  const el = document.getElementById('sbTime'); if (el) el.textContent = t;
  setTimeout(clock, 10000);
})();

render();
