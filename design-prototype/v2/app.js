/* ============================================================================
   Leyne — "Glance" redesign · app logic (vanilla JS, no build)
   Departures-first, glanceable, alive. Every screen built to one bar:
   Now · Rail · Line diagram · Station · Bus · GO trip · Search · Trip results ·
   Settings · About · Onboarding. Live countdowns tick each second.
   Research-applied (Transit / Citymapper / Apple Maps / TfL diagram standard).
   ========================================================================== */

const SVG = {
  search:`<svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.2-4.2"/></svg>`,
  bus:`<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><path d="M4 5a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2v2a1 1 0 0 1-2 0v-1H8v1a1 1 0 0 1-2 0v-2a2 2 0 0 1-2-2V5zm2 1v4h12V6H6zm1.6 8a1.4 1.4 0 1 0 0-2.8 1.4 1.4 0 0 0 0 2.8zm8.8 0a1.4 1.4 0 1 0 0-2.8 1.4 1.4 0 0 0 0 2.8z"/></svg>`,
  tram:`<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><path d="M7 3h10a3 3 0 0 1 3 3v9a3 3 0 0 1-3 3l1.2 1.8a.7.7 0 0 1-1.1.9L15.6 18H8.4l-1.5 2.4a.7.7 0 0 1-1.1-.9L7 18a3 3 0 0 1-3-3V6a3 3 0 0 1 3-3zM6.5 7v4h11V7zM8.2 16a1.2 1.2 0 1 0 0-2.4 1.2 1.2 0 0 0 0 2.4zm7.6 0a1.2 1.2 0 1 0 0-2.4 1.2 1.2 0 0 0 0 2.4z"/></svg>`,
  star:`<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2.5l2.9 5.9 6.5.9-4.7 4.6 1.1 6.5L12 17.8 6.2 20.4l1.1-6.5L2.6 9.3l6.5-.9z"/></svg>`,
  staro:`<svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M12 3.5l2.7 5.5 6 .9-4.3 4.2 1 6L12 17.3 6.6 20.1l1-6L3.3 9.9l6-.9z"/></svg>`,
  chev:`<svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M9 5l7 7-7 7"/></svg>`,
  back:`<svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M15 5l-7 7 7 7"/></svg>`,
  walk:`<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><circle cx="13" cy="4" r="2"/><path d="M11 7.5L8.4 9.2a2 2 0 0 0-.9 1.7V16a1 1 0 0 0 2 0v-3.3l1.4-.9-1 4.7 1.5 1 1.6 4a1 1 0 0 0 1.9-.7l-1.7-4.4-1.3-1 .8-3.4 1 2a1 1 0 0 0 .8.5l2.4.2a1 1 0 0 0 .1-2l-2-.2-1.4-2.8a2 2 0 0 0-2.6-.9z"/></svg>`,
  alert:`<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2L1 21h22L12 2zm0 6a1 1 0 0 1 1 1v5a1 1 0 0 1-2 0V9a1 1 0 0 1 1-1zm0 9.5a1.3 1.3 0 1 1 0 2.6 1.3 1.3 0 0 1 0-2.6z"/></svg>`,
  loc:`<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><path d="M21 3L3 10.6l7.4 2.5L13 21z"/></svg>`,
  locpin:`<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2a7 7 0 0 0-7 7c0 5 7 13 7 13s7-8 7-13a7 7 0 0 0-7-7zm0 9.5A2.5 2.5 0 1 1 12 6.5a2.5 2.5 0 0 1 0 5z"/></svg>`,
  home:`<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><path d="M12 3L2 11h3v9h6v-6h2v6h6v-9h3z"/></svg>`,
  work:`<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><path d="M9 4a2 2 0 0 0-2 2v1H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3V6a2 2 0 0 0-2-2H9zm0 2h6v1H9V6z"/></svg>`,
  plus:`<svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>`,
  clock:`<svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M12 7.5v5l3 2"/></svg>`,
  accessible:`<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="4" r="2"/><path d="M7 8l5 1v4l3 6 1.8-.8L14 13v-5l-7-1z" opacity=".0"/><path d="M6.5 8.5l4.5.9V14l2.6 5.6 1.8-.8-2.4-5.1V8.8L6.9 7.7z"/><circle cx="11" cy="16" r="6" fill="none" stroke="currentColor" stroke-width="1.6"/></svg>`,
  door:`<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><path d="M6 3h9a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6V3zm6 8a1 1 0 1 0 0 2 1 1 0 0 0 0-2z"/></svg>`,
  info:`<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm0 5a1.3 1.3 0 1 1 0 2.6A1.3 1.3 0 0 1 12 7zm1.2 10h-2.4v-6h2.4z"/></svg>`,
  coffee:`<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><path d="M4 8h12v6a4 4 0 0 1-4 4H8a4 4 0 0 1-4-4V8zm12 1h2a2 2 0 0 1 0 4h-2V9zM6 3l1 2M10 3l1 2M14 3l1 2"/></svg>`,
  bell:`<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2a6 6 0 0 0-6 6c0 5-2 6-2 7h16c0-1-2-2-2-7a6 6 0 0 0-6-6zm0 20a3 3 0 0 0 3-3H9a3 3 0 0 0 3 3z"/></svg>`,
  moon:`<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/></svg>`,
  lock:`<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><path d="M6 10V8a6 6 0 1 1 12 0v2h1a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-9a1 1 0 0 1 1-1h1zm2 0h8V8a4 4 0 1 0-8 0v2z"/></svg>`,
  person:`<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="7" r="4"/><path d="M4 21v-1a8 8 0 0 1 16 0v1z"/></svg>`,
  play:`<svg class="ico" viewBox="0 0 24 24" fill="currentColor"><path d="M7 4l13 8-13 8z"/></svg>`,
  swap:`<svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M7 4v16M7 4L4 7M7 4l3 3M17 20V4M17 20l-3-3M17 20l3-3"/></svg>`,
};
const WAVE = `<svg class="wave" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M4 18a16 16 0 0 1 16 0"/><path d="M7.5 15a11 11 0 0 1 9 0"/><path d="M11 12.2a5 5 0 0 1 2 0"/></svg>`;

// ─── Data ───────────────────────────────────────────────────────────────────
const T0 = Date.now();
const tgt = secs => secs.map(s => T0 + s * 1000);
const STOPS = [
  { code:'53061', name:'Bef Bishan Stn', road:'Bishan Rd', walk:3, saved:true, alert:false, svc:[
    { no:'88',  dest:'Clementi Int',  secs:[150, 540, 1200], crowd:'l', mon:true },
    { no:'156', dest:'Toa Payoh Int', secs:[540, 1140],      crowd:'m', mon:true },
    { no:'410', dest:'Bishan Int',    secs:[35, 960],        crowd:'h', mon:false },
    { no:'13',  dest:'Tampines Int',  secs:[720, 1440],      crowd:'l', mon:true },
  ]},
  { code:'53069', name:'Opp Bishan Stn', road:'Bishan Rd', walk:4, saved:true, alert:false, svc:[
    { no:'52', dest:'Toa Payoh Int', secs:[20, 840],  crowd:'m', mon:true },
    { no:'59', dest:'Hougang Ctrl',  secs:[360, 840], crowd:'l', mon:true },
  ]},
  { code:'59039', name:'Blk 217', road:'Ang Mo Kio Ave 1', walk:7, saved:false, alert:true, svc:[
    { no:'162',  dest:'Marymount',  secs:[180, 660], crowd:'l', mon:true },
    { no:'162M', dest:'AMK Int',    secs:[480],      crowd:'m', mon:false },
  ]},
];
STOPS.forEach(s => s.svc.forEach(v => v.t = tgt(v.secs)));
const stopBy = Object.fromEntries(STOPS.map(s => [s.code, s]));

const LINES = [
  { code:'NS', name:'North South',        v:'--ns', status:'normal' },
  { code:'EW', name:'East West',          v:'--ew', status:'normal' },
  { code:'NE', name:'North East',         v:'--ne', status:'normal' },
  { code:'CC', name:'Circle',             v:'--cc', status:'warn', note:'Delays Bishan ↔ Newton', loop:true },
  { code:'DT', name:'Downtown',           v:'--dt', status:'normal' },
  { code:'TE', name:'Thomson–East Coast', v:'--te', status:'normal' },
];
const lineBy = Object.fromEntries(LINES.map(l => [l.code, l]));
const STATIONS = [
  { name:'Bishan',     codes:['NS','CC'], walk:5, crowd:'m', line:'NS' },
  { name:'Marina Bay', codes:['NS','TE','CC'], walk:12, crowd:'l', line:'NS' },
];
// [name, [interchange codes], crowd]
const LINE_STATIONS = {
  NS: [['Jurong East',['EW'],'l'],['Woodlands',['TE'],'m'],['Bishan',['CC'],'h'],['Novena',[],'m'],['Newton',['DT'],'h'],['Orchard',['TE'],'h'],['Marina Bay',['TE','CC'],'l']],
  EW: [['Pasir Ris',[],'l'],['Tampines',['DT'],'h'],['Paya Lebar',['CC'],'m'],['Bugis',['DT'],'h'],['City Hall',['NS'],'m'],['Outram Park',['NE','TE'],'h'],['Jurong East',['NS'],'m']],
  NE: [['HarbourFront',['CC'],'m'],['Outram Park',['EW','TE'],'h'],['Dhoby Ghaut',['NS','CC'],'h'],['Serangoon',['CC'],'m'],['Hougang',[],'l'],['Punggol',[],'l']],
  CC: [['Dhoby Ghaut',['NS','NE'],'h'],['Bishan',['NS'],'h'],['Serangoon',['NE'],'m'],['Paya Lebar',['EW'],'m'],['MacPherson',['DT'],'l'],['HarbourFront',['NE'],'m']],
  DT: [['Bukit Panjang',[],'l'],['Newton',['NS'],'h'],['Little India',['NE'],'m'],['Bugis',['EW'],'h'],['MacPherson',['CC'],'l'],['Tampines',['EW'],'m'],['Expo',[],'l']],
  TE: [['Woodlands',['NS'],'m'],['Caldecott',['CC'],'m'],['Orchard',['NS'],'h'],['Outram Park',['EW','NE'],'h'],['Gardens by the Bay',[],'l'],['Marina Bay',['NS','CC'],'l']],
};
const RECENTS = [['Orchard','MRT station'],['88','Bus · to Clementi'],['Tampines Hub','Place'],['Bishan','MRT station']];

// ─── Live countdown engine ──────────────────────────────────────────────────
function fmt(remSec) {
  if (remSec <= 30) return { n: 'Arr', u: 'now', go: true };
  const m = Math.ceil(remSec / 60);
  return { n: String(m), u: 'min', go: m <= 1 };
}
function paintDep(el) {
  const times = el.dataset.times.split(',').map(Number);
  const mon = el.dataset.mon === '1';
  const now = Date.now();
  const f = fmt((times[0] - now) / 1000);
  const c = el.querySelector('.count'); if (!c) return;
  const tilde = (!mon && f.n !== 'Arr') ? '<span class="tilde">~</span>' : '';
  const rolled = c.dataset.n !== f.n ? ' rolled' : '';
  c.dataset.n = f.n;
  c.className = 'count' + (f.go && mon ? ' is-go' : '') + (!mon ? ' is-sched' : '');
  c.innerHTML = `${mon ? WAVE : ''}<div class="count__n${rolled}">${tilde}${f.n}</div><div class="count__u">${f.u}</div>`;
  const then = el.querySelector('.dep__then');
  if (then) {
    const fol = times.slice(1).map(t => { const r = (t - now) / 1000; return r <= 30 ? 'Arr' : Math.ceil(r / 60); });
    then.textContent = fol.length ? 'then ' + fol.join(' · ') + (typeof fol[fol.length - 1] === 'number' ? ' min' : '') : '';
  }
}
function paintStation(el) {
  const times = el.dataset.times.split(',').map(Number);
  const mon = el.dataset.mon === '1'; // live vs scheduled — drives the wave/tilde, not hardcoded
  const now = Date.now();
  const labels = times.map(t => { const r = (t - now) / 1000; return r <= 30 ? 'Arr' : Math.ceil(r / 60); });
  const big = el.querySelector('.big');
  big.className = 'big' + (mon ? '' : ' is-sched');
  big.innerHTML = `${mon ? WAVE : ''}${mon ? '' : '<span class="tilde">~</span>'}${labels[0]}<span class="u" style="margin-left:4px">min</span>`;
  el.querySelectorAll('.more').forEach((m, i) => { m.textContent = labels[i + 1] != null ? labels[i + 1] + ' min' : ''; });
}
function paintGo() {
  const c = document.querySelector('.go__count[data-target]'); if (!c) return;
  const r = (Number(c.dataset.target) - Date.now()) / 1000;
  const f = fmt(r);
  c.textContent = f.n === 'Arr' ? '0' : f.n;
}
function tick() {
  document.querySelectorAll('#screen .dep[data-times], #screen .bushero[data-times]').forEach(paintDep);
  document.querySelectorAll('#screen .st-times[data-times]').forEach(paintStation);
  document.querySelectorAll('#overlay [data-mini]').forEach(el => {
    const r = (Number(el.dataset.mini) - Date.now()) / 1000;
    el.textContent = r <= 30 ? 'now' : Math.ceil(r / 60) + ' min';
  });
  paintGo();
}

// ─── Components ─────────────────────────────────────────────────────────────
function crowd(level, label) {
  const txt = { l: 'Seats', m: 'Standing', h: 'Crowded', na: 'No data' }[level] || '';
  return `<span class="crowd ${level}"><i></i><i></i><i></i></span>${label ? `<span class="crowd__lbl">${txt}</span>` : ''}`;
}
function lineChip(code) {
  const dark = (code === 'CC' || code === 'EW') ? ' txt-dark' : ''; // light line colours need dark text (AA)
  return `<span class="linechip${dark}" style="background:var(${(lineBy[code] || {}).v || '--ink'})">${code}</span>`;
}
function depCard(svc, code) {
  return `<div class="dep tapfx" data-nav="bus:${code}:${svc.no}" data-times="${svc.t.join(',')}" data-mon="${svc.mon ? 1 : 0}">
      <div class="badge badge--bus badge--md">${svc.no}</div>
      <div class="dep__mid"><div class="dep__dest">${svc.dest}</div>
        <div class="dep__sub">${crowd(svc.crowd)}<span class="dep__then"></span></div></div>
      <div class="count"></div></div>`;
}
function stopSection(stop) {
  return `<section class="stopsec">
      <div class="stophead">
        <div><div class="stophead__name">${stop.name}</div>
        <div class="stophead__meta"><span class="stophead__walk">${stop.walk} min walk</span> · Stop ${stop.code}</div></div>
        ${stop.alert ? `<span class="alertdot" title="alert"></span>` : ''}
        <span class="pin tapfx ${stop.saved ? 'on' : ''}" data-stop="${stop.code}">${stop.saved ? SVG.star : SVG.staro}</span>
      </div>
      ${stop.svc.map(v => depCard(v, stop.code)).join('')}</section>`;
}
function skeletonDep() {
  return `<div class="sk-dep"><div class="skel sk-badge"></div><div style="flex:1"><div class="skel sk-line w60"></div><div class="skel sk-line w40"></div></div><div class="skel sk-eta"></div></div>`;
}
function emptyState(icon, t, b, cta) {
  return `<div class="empty"><div class="empty__ic">${SVG[icon]}</div><div class="empty__t">${t}</div><div class="empty__b">${b}</div>${cta ? `<div class="empty__cta tapfx" data-nav="${cta.nav}">${cta.label}</div>` : ''}</div>`;
}

// ─── Onboarding ─────────────────────────────────────────────────────────────
let onbStep = 0; let onboarded = false;
const ONB = [
  { art: `<div class="onb__art">${SVG.tram}</div>`, t: 'Leyne', b: 'Live bus & MRT arrivals for Singapore — the next departure, before you even ask.', cta: 'Get started' },
  { tile: 'g-blue', tIco: 'locpin', t: 'See stops near you', b: 'Leyne uses your location to show the closest stops and stations with live arrivals. It stays on your device.', cta: 'Allow location' },
  { tile: 'g-green', tIco: 'bus', t: "You're set", b: 'Your nearby departures are live and counting down. Pin the stops you use to keep them up top.', cta: 'Enter Leyne' },
];
function renderOnb() {
  const s = ONB[onbStep];
  const art = s.art || `<div class="onb__art"><div class="onb__tile ${s.tile}">${SVG[s.tIco]}</div></div>`;
  return `<div class="onb">
    ${art}
    <div class="onb__t">${s.t}</div>
    <div class="onb__b">${s.b}</div>
    <div class="onb__dots">${ONB.map((_, i) => `<i class="${i === onbStep ? 'on' : ''}"></i>`).join('')}</div>
    <div class="onb__cta tapfx" data-onb-next>${s.cta}</div>
    ${onbStep < ONB.length - 1 ? `<div class="onb__skip" data-onb-skip>Skip</div>` : ''}
  </div>`;
}

// ─── Screens ────────────────────────────────────────────────────────────────
let nowBooted = false;
function topScreen() { return state.stack[state.stack.length - 1].s; }

function screenNow() {
  const now = new Date(), h = now.getHours();
  const greet = h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening';
  const clock = now.toLocaleTimeString('en-SG', { hour: 'numeric', minute: '2-digit' });
  const head = `<div class="searchbar tapfx" data-search>${SVG.search}<span class="searchbar__ph">Where to?</span><span class="searchbar__me tapfx" data-nav="settings">R</span></div>
    <div class="places">
      <div class="place tapfx" data-nav="stop:53061"><div class="place__ic">${SVG.home}</div><span class="place__l">Home</span></div>
      <div class="place tapfx" data-nav="stop:59039"><div class="place__ic">${SVG.work}</div><span class="place__l">Work</span></div>
      <div class="place tapfx" data-search><div class="place__ic dashed">${SVG.plus}</div><span class="place__l">Add</span></div>
    </div>`;
  if (!nowBooted) {
    return `<div class="page">${head}<div class="hdr">Saved</div>${skeletonDep()}${skeletonDep()}<div class="hdr">Nearby</div>${skeletonDep()}${skeletonDep()}</div>`;
  }
  const saved = STOPS.filter(s => s.saved), near = STOPS.filter(s => !s.saved);
  const alerted = STOPS.find(s => s.alert);
  return `<div class="page">
    ${head}
    <div class="context"><b>${greet}</b><span class="live sp"><span class="dot"></span>LIVE</span></div>
    ${alerted ? `<div class="alert tapfx"><span class="alert__ic">${SVG.alert}</span><div><div class="alert__t">Service alert · ${alerted.name}</div><div class="alert__d">Bus 162 diverted — boards at the temporary stop opposite.</div></div></div>` : ''}
    <div class="stagger">
      <div class="hdr">Saved <span class="stamp" style="margin-left:auto">updated 8s ago</span></div>
      ${saved.length ? saved.map(stopSection).join('') : emptyState('staro', 'No saved stops yet', 'Pin a stop and it floats to the top here.', { nav: 'rail', label: 'Find a stop' })}
      <div class="hdr">Nearby</div>
      ${near.map(stopSection).join('')}
    </div></div>`;
}

function screenRail() {
  const warn = LINES.find(l => l.status === 'warn');
  return `<div class="page">
    <div class="searchbar tapfx" data-search>${SVG.search}<span class="searchbar__ph">Search stations</span><span class="searchbar__me tapfx" data-nav="settings">R</span></div>
    ${warn ? `<div class="alert tapfx" data-nav="line:${warn.code}"><span class="alert__ic">${SVG.alert}</span><div><div class="alert__t">${warn.code} · ${warn.name}</div><div class="alert__d">${warn.note}. Add ~10 min. Free bridging buses at affected stations.</div></div></div>` : ''}
    <div class="hdr">Network</div>
    <div class="stagger">
      ${LINES.map(l => `<div class="linerow tapfx" data-nav="line:${l.code}">
        ${lineChip(l.code)}<span class="linerow__name">${l.name}</span>
        <span class="status ${l.status === 'warn' ? 'warn' : ''}"><span class="sdot"></span>${l.status === 'warn' ? 'Delays' : 'Normal'}</span>
        <span class="pin">${SVG.chev}</span></div>`).join('')}
    </div>
    <div class="hdr">Near you</div>
    ${STATIONS.map(st => `<div class="station tapfx" data-nav="station:${st.line}:${encodeURIComponent(st.name)}">
      <span class="station__codes">${st.codes.map(lineChip).join('')}</span>
      <span class="station__name">${st.name}</span>${crowd(st.crowd, true)}
      <span class="stophead__meta">${st.walk}m</span></div>`).join('')}
  </div>`;
}

function screenLine(code, dir) {
  const l = lineBy[code]; const v = l.v;
  let sts = (LINE_STATIONS[code] || []).slice();
  if (dir === 1) sts.reverse();
  const youName = 'Bishan';
  const termA = sts[0][0], termB = sts[sts.length - 1][0];
  return `<div class="page">
    <div class="floatback tapfx" data-back>${SVG.back}</div>
    <div class="linehead">
      <div class="linehead__name">${lineChip(code)} ${l.name} Line</div>
      <div class="linehead__band" style="background:var(${v})"></div>
      <div class="dirseg">
        <button class="${dir !== 1 ? 'on' : ''}" data-dir="0:${code}">Towards ${termB}</button>
        <button class="${dir === 1 ? 'on' : ''}" data-dir="1:${code}">Towards ${termA}</button>
      </div>
    </div>
    ${l.loop ? `<div class="loop"><svg width="34" height="34" viewBox="0 0 34 34" fill="none" stroke="var(${v})" stroke-width="5"><circle cx="17" cy="17" r="13"/></svg>Loop line — runs both directions</div>` : ''}
    <div class="diagram">
      <span class="dg-spine" style="background:var(${v})"></span>
      ${sts.map((s, i) => {
        const cls = (i === 0 || i === sts.length - 1) ? 'term' : (s[1].length ? 'ix' : '');
        const you = s[0] === youName ? ' you' : '';
        return `<div class="dg-stop tapfx ${cls}${you}" style="color:var(${v})" data-nav="station:${code}:${encodeURIComponent(s[0])}">
          <span class="dg-node"></span>
          <span class="dg-name">${s[0]}${you ? ' · nearest' : ''}</span>
          <span class="dg-codes">${s[1].map(lineChip).join('')}</span>
          ${crowd(s[2])}</div>`;
      }).join('')}
    </div>
    <div class="hdr" style="gap:6px">${crowd('l')} Seats &nbsp;&nbsp; ${crowd('m')} Standing &nbsp;&nbsp; ${crowd('h')} Crowded</div>
  </div>`;
}

function stationDetail(code, name) {
  const l = lineBy[code] || LINES[0];
  const sts = LINE_STATIONS[code] || [];
  const here = sts.find(s => s[0] === name) || [name, [], 'm'];
  const termA = sts[0] ? sts[0][0] : 'one end', termB = sts[sts.length - 1] ? sts[sts.length - 1][0] : 'the other';
  const codes = [code, ...here[1]];
  const walk = (STATIONS.find(s => s.name === name) || {}).walk || (4 + (name.length % 6));
  return { name, codes, walk, crowd: here[2],
    dirs: [
      { dest: termB, plat: 'B', crowd: here[2], t: tgt([130, 320, 560]) },
      { dest: termA, plat: 'A', crowd: 'l', t: tgt([260, 480, 720]) },
    ] };
}
function screenStation(code, nameEnc) {
  const name = decodeURIComponent(nameEnc);
  const d = stationDetail(code, name);
  const dir = (x) => `<div class="st-dir">
      <div class="st-dir__h">Towards ${x.dest}<span class="st-dir__plat">Platform ${x.plat}</span>${crowd(x.crowd, true)}</div>
      <div class="st-times" data-times="${x.t.join(',')}" data-mon="0">
        <span class="big"></span><span class="more"></span><span class="more"></span>
      </div></div>`;
  return `<div class="page">
    <div class="floatback tapfx" data-back>${SVG.back}</div>
    <div class="st-head">
      <div class="st-name">${d.name}</div>
      <div class="st-sub">${d.codes.map(lineChip).join('')}<span class="st-walk">${d.walk} min walk</span></div>
    </div>
    <div class="hdr">Next trains · scheduled</div>
    ${d.dirs.map(dir).join('')}
    <div class="hdr">Station</div>
    <div class="disclose tapfx"><span class="disclose__g g-green">${SVG.accessible}</span><span class="disclose__l">Lifts</span><span class="disclose__v">All operational</span>${SVG.chev}</div>
    <div class="disclose tapfx"><span class="disclose__g g-gray">${SVG.door}</span><span class="disclose__l">Exits & entrances</span><span class="disclose__v">A–F</span>${SVG.chev}</div>
    <div class="disclose tapfx"><span class="disclose__g g-indigo">${SVG.clock}</span><span class="disclose__l">First / last train</span><span class="disclose__v">05:31 · 00:18</span>${SVG.chev}</div>
    <div class="disclose tapfx" data-nav="stop:53061"><span class="disclose__g g-green">${SVG.bus}</span><span class="disclose__l">Buses nearby</span><span class="disclose__v">4</span>${SVG.chev}</div>
  </div>`;
}

function screenBus(code, no) {
  const stop = stopBy[code]; const svc = stop && stop.svc.find(s => s.no === no);
  if (!svc) return `<div class="page"><div class="floatback tapfx" data-back>${SVG.back}</div>${emptyState('bus', 'Service not found', 'It may have finished for the day.')}</div>`;
  const route = ['Bishan Int', 'Blk 511', 'Opp CPF Bldg', stop.name, 'Sin Ming Ave', 'Thomson Plaza', svc.dest];
  const youIdx = 3, busIdx = 2;
  const fillPct = (busIdx / (route.length - 1)) * 100;
  return `<div class="page">
    <div class="floatback tapfx" data-back>${SVG.back}</div>
    <div class="bushero" data-times="${svc.t.join(',')}" data-mon="${svc.mon ? 1 : 0}" style="padding-top:60px">
      <div class="badge badge--bus badge--lg">${svc.no}</div>
      <div class="dep__mid"><div class="bushero__d">${svc.dest}</div>
        <div class="bushero__s">from ${stop.name} · ${stop.code}</div>
        <div style="margin-top:7px"><span class="statuspill ${svc.mon ? 'live' : ''}">${svc.mon ? WAVE + ' LIVE' : 'SCHEDULED'}</span></div></div>
      <div class="count"></div>
    </div>
    <div class="map"><div class="map__route"></div><div class="map__bus">${SVG.bus}</div><div class="map__me"></div></div>
    <div class="btn-primary tapfx" data-go="${code}:${no}" style="margin:0 0 6px;display:flex;align-items:center;justify-content:center;gap:8px">${SVG.play} Start trip</div>
    <div class="hdr">On the way</div>
    <div class="card"><div class="tl">
      <span class="tl-rail"></span><span class="tl-rail__fill" style="height:${fillPct}%"></span>
      ${route.map((r, i) => `<div class="tl-stop ${i < busIdx ? 'past' : ''} ${i === youIdx ? 'you' : ''}">
        ${i === busIdx ? `<span class="tl-bus">${SVG.bus}</span>` : `<span class="tl-node"></span>`}
        <span class="tl-name">${r}${i === youIdx ? ' · your stop' : ''}</span>
        <span class="tl-eta">${i <= busIdx ? '' : (i - busIdx) * 2 + ' min'}</span></div>`).join('')}
    </div></div>
    <div class="hdr">Service</div>
    <div class="set-card">
      <div class="set-row"><span class="set-row__l">First / last bus</span><span class="set-row__v">05:30 · 00:00</span></div>
      <div class="set-row"><span class="set-row__l">Frequency now</span><span class="set-row__v">every 6–9 min</span></div>
      <div class="set-row"><span class="set-row__l">Crowd</span><span class="set-row__v">${crowd(svc.crowd, true)}</span></div>
    </div>
  </div>`;
}

// ─── GO trip companion ──────────────────────────────────────────────────────
let goPhase = 0; let goCtx = null; let goTimer = null;
const GO_PHASES = [
  { status: 'Walk to stop', verb: 'Walk to', sub: 'Bef Bishan Stn · 240 m', secs: 180, prog: ['now', '', '', ''] },
  { status: 'Wait', verb: 'Board in', sub: 'Bus 88 · to Clementi Int', secs: 120, prog: ['done', 'now', '', ''] },
  { status: 'On bus 88', verb: 'Stops to go', sub: '4 stops · sit tight', secs: 0, count: '4', prog: ['done', 'done', 'now', ''], alert: false },
  { status: 'On bus 88', verb: 'Get off', sub: 'Your stop is next', secs: 0, count: 'next', prog: ['done', 'done', 'now', ''], alert: true },
  { status: 'Arrived', verb: '', sub: "You've arrived. Enjoy Clementi.", secs: 0, count: '✓', prog: ['done', 'done', 'done', 'done'], done: true },
];
function renderGo() {
  const p = GO_PHASES[goPhase];
  const big = p.count != null ? p.count : '';
  return `<div class="go">
    <div class="go__status"><span class="live"><span class="dot"></span></span>${p.status}<span class="x tapfx" data-closego>✕</span></div>
    <div class="go__hero">
      ${p.verb ? `<div class="go__verb">${p.verb}</div>` : ''}
      <div class="go__count ${p.alert || p.done ? 'arr' : (p.secs ? '' : 'arr')}" ${p.secs ? `data-target="${Date.now() + p.secs * 1000}"` : ''}>${p.secs ? Math.ceil(p.secs / 60) : big}</div>
      <div class="go__sub">${p.sub}</div>
    </div>
    ${p.alert ? `<div class="go__alert">${SVG.alert} Get off at the next stop</div>` : ''}
    <div class="go__prog">${p.prog.map(s => `<i class="${s}"></i>`).join('')}</div>
    <div class="go__steps">
      <div class="gostep ${goPhase > 0 ? 'done' : 'now'}">${SVG.walk} Walk to Bef Bishan Stn</div>
      <div class="gostep ${goPhase > 1 ? (goPhase > 3 ? 'done' : 'now') : (goPhase === 1 ? 'now' : '')}">${SVG.bus} Ride 88 · 4 stops</div>
      <div class="gostep ${goPhase >= 4 ? 'now' : ''}">${SVG.walk} Walk to destination</div>
    </div>
    ${!p.done ? `<div class="btn-primary tapfx" data-gonext>${goPhase === GO_PHASES.length - 2 ? 'Arrive' : 'Next'}</div>` : `<div class="btn-primary tapfx" data-closego>Done</div>`}
  </div>`;
}
function openGo(code, no) { goCtx = { code, no }; goPhase = 0; mountOverlay('go', renderGo()); autoGo(); }
function autoGo() { clearTimeout(goTimer); if (goPhase < GO_PHASES.length - 1) goTimer = setTimeout(() => { goPhase++; mountOverlay('go', renderGo()); autoGo(); }, 5000); }
function closeGo() { clearTimeout(goTimer); document.getElementById('overlay').hidden = true; document.getElementById('overlay').innerHTML = ''; }

// ─── Search + Trip ──────────────────────────────────────────────────────────
function openSearch() {
  const near = STOPS[0];
  const res = [
    ...STOPS.map(s => ({ t: s.name, s: `Stop ${s.code} · next ${nextEta(s)}`, ico: SVG.bus, nav: `stop:${s.code}` })),
    ...LINES.slice(0, 2).map(l => ({ chip: l.code, t: `${l.name} Line`, s: l.status === 'warn' ? l.note : 'Normal service', nav: `line:${l.code}` })),
  ];
  mountOverlay('search', `
    <div class="sheet__bar">
      <div class="sheet__field">${SVG.search}<input placeholder="Where to?" autofocus /></div>
      <span class="sheet__cancel tapfx" data-closesearch>Cancel</span>
    </div>
    <div class="whereto tapfx" data-where>${SVG.swap}<span class="whereto__t">Plan a trip — pick a destination</span></div>
    <div class="places" style="margin:6px 0 14px">
      <div class="place tapfx" data-where><div class="place__ic">${SVG.home}</div><span class="place__l">Home</span></div>
      <div class="place tapfx" data-where><div class="place__ic">${SVG.work}</div><span class="place__l">Work</span></div>
      <div class="place tapfx" data-where><div class="place__ic dashed">${SVG.plus}</div><span class="place__l">Add</span></div>
    </div>
    <div class="hdr">Recent</div>
    ${RECENTS.map(r => `<div class="recent tapfx" data-soft="stop:53061">${SVG.clock}<div style="flex:1"><div class="recent__t">${r[0]}</div></div><span class="set-row__v">${r[1]}</span></div>`).join('')}
    <div class="hdr">Nearby now</div>
    ${near.svc.slice(0, 2).map(v => `<div class="sresult tapfx" data-soft="bus:${near.code}:${v.no}"><div class="badge badge--bus badge--sm">${v.no}</div><div style="flex:1"><div class="sresult__t">${v.dest}</div><div class="sresult__s">${near.name}</div></div><span class="set-row__v" data-mini="${v.t[0]}">${nextSvc(v)}</span></div>`).join('')}
  `);
}
function screenTrip() {
  const strip = legs => `<div class="modestrip">${legs.map((g, i) => `${i ? `<span class="arrow">${SVG.chev}</span>` : ''}<span class="seg-ico">${g.m === 'walk' ? SVG.walk + g.v : g.m === 'bus' ? `<span class="badge badge--bus" style="width:24px;height:24px;font-size:12px;border-radius:7px">${g.no}</span>` : lineChip(g.code)}</span>`).join('')}</div>`;
  const trips = [
    { dur: '24 min', clock: '10:42 – 11:06', fare: '$1.79', meta: 'Leave now · 1 transfer · live', legs: [{ m: 'walk', v: 4 }, { m: 'bus', no: '67' }, { m: 'walk', v: 2 }, { m: 'mrt', code: 'EW' }, { m: 'walk', v: 3 }] },
    { dur: '27 min', clock: '10:44 – 11:11', fare: '$1.55', meta: 'Fewest transfers', legs: [{ m: 'walk', v: 6 }, { m: 'mrt', code: 'NS' }, { m: 'walk', v: 4 }] },
    { dur: '31 min', clock: '10:42 – 11:13', fare: '$1.40', meta: 'Least walking · Rain-safe', legs: [{ m: 'walk', v: 2 }, { m: 'bus', no: '156' }, { m: 'bus', no: '88' }, { m: 'walk', v: 1 }] },
  ];
  return `<div class="page">
    <div class="floatback tapfx" data-back>${SVG.back}</div>
    <div class="st-head"><div class="st-name" style="font-size:22px">Bishan → Marina Bay</div>
      <div class="st-sub"><span class="set-row__v">Leave now</span></div></div>
    <div class="seg" style="margin:14px 0"><button class="on">Best</button><button>Fewest transfers</button><button>Least walking</button></div>
    ${trips.map(t => `<div class="trip tapfx" data-nav="bus:53061:88">
      <div class="trip__top"><span class="trip__dur">${t.dur}</span><span class="trip__clock">${t.clock}</span><span class="trip__fare">${t.fare}</span></div>
      ${strip(t.legs)}
      <div class="trip__meta">${t.meta}</div></div>`).join('')}
  </div>`;
}
function nextEta(stop) { const r = (stop.svc[0].t[0] - Date.now()) / 1000; return r <= 30 ? 'now' : Math.ceil(r / 60) + ' min'; }
function nextSvc(v) { const r = (v.t[0] - Date.now()) / 1000; return r <= 30 ? 'now' : Math.ceil(r / 60) + ' min'; }

// ─── Settings + About ───────────────────────────────────────────────────────
function setRow(g, ico, label, val, nav) {
  return `<div class="set-row tapfx" ${nav ? `data-nav="${nav}"` : ''}><span class="disclose__g ${g}">${SVG[ico]}</span><span class="set-row__l">${label}</span>${val ? `<span class="set-row__v">${val}</span>` : ''}${SVG.chev}</div>`;
}
function screenSettings() {
  return `<div class="page">
    <div class="floatback tapfx" data-back>${SVG.back}</div>
    <div style="padding-top:52px"></div>
    <div class="id-card"><div class="id-icon">L</div><div><div class="id-name">Leyne</div><div class="id-sub">Singapore bus & MRT · v2.8.5</div></div></div>
    <div class="hdr">Preferences</div>
    <div class="set-card">
      ${setRow('g-green', 'bus', 'Default mode', 'Bus')}
      <div class="set-row"><span class="disclose__g g-indigo">${SVG.moon}</span><span class="set-row__l">Appearance</span><span class="set-row__v">System</span>${SVG.chev}</div>
      <div class="set-row"><span class="disclose__g g-orange">${SVG.locpin}</span><span class="set-row__l">Haptics</span><span class="toggle on" data-tog></span></div>
    </div>
    <div class="set-foot">Choose what opens first and how Leyne looks.</div>
    <div class="hdr">Notifications</div>
    <div class="set-card">
      <div class="set-row"><span class="disclose__g g-red">${SVG.bell}</span><span class="set-row__l">Arrival alerts</span><span class="toggle on" data-tog></span></div>
      <div class="set-row"><span class="disclose__g g-blue">${SVG.locpin}</span><span class="set-row__l">Bus-coming alerts</span><span class="toggle" data-tog></span></div>
    </div>
    <div class="set-foot">Get a heads-up before your bus arrives so you never run for it.</div>
    <div class="hdr">About</div>
    <div class="set-card">
      ${setRow('g-gray', 'info', 'About Leyne', '', 'about')}
      ${setRow('g-gold', 'star', 'Rate Leyne', '')}
      ${setRow('g-brown', 'coffee', 'Buy me a coffee', '')}
    </div>
    <div class="set-foot" style="text-align:center;padding-top:16px">Transit data from LTA DataMall · Made in Singapore</div>
  </div>`;
}
function screenAbout() {
  return `<div class="page">
    <div class="floatback tapfx" data-back>${SVG.back}</div>
    <div style="text-align:center;max-width:280px;margin:70px auto 24px">
      <div class="id-icon" style="width:84px;height:84px;border-radius:22px;font-size:38px;margin:0 auto 14px">L</div>
      <div class="empty__t">Leyne</div><div class="empty__b">Version 2.8.5 (46)<br>Live bus & MRT arrivals for Singapore.</div>
    </div>
    <div class="set-card">
      ${setRow('g-green', 'info', 'Transit data from LTA DataMall', '')}
      ${setRow('g-gold', 'star', 'Rate on the App Store', '')}
      ${setRow('g-blue', 'bell', 'Send feedback', '')}
      ${setRow('g-gray', 'lock', 'Privacy policy', '')}
    </div>
    <div class="set-foot" style="text-align:center;padding-top:16px">Made in Singapore 🇸🇬</div>
  </div>`;
}

// ─── Nav ────────────────────────────────────────────────────────────────────
const TABS = [{ id: 'now', label: 'Now', icon: 'bus', root: 'now' }, { id: 'rail', label: 'Rail', icon: 'tram', root: 'rail' }];
const RENDER = {
  now: screenNow, rail: screenRail, settings: screenSettings, about: screenAbout, trip: screenTrip,
  line: p => screenLine(p.a, p.dir || 0), station: p => screenStation(p.a, p.b), bus: p => screenBus(p.a, p.b),
  stop: p => screenBus(p.a, stopBy[p.a].svc[0].no),
};
let state = { tab: 'now', stack: [{ s: 'now' }] };

function render() {
  document.getElementById('screen').innerHTML = RENDER[topScreen()](state.stack[state.stack.length - 1]);
  document.getElementById('screen').scrollTop = 0;
  navbar(); tick();
  if (topScreen() === 'now' && !nowBooted) setTimeout(() => { nowBooted = true; if (topScreen() === 'now') render(); }, 850);
}
function navbar() {
  document.getElementById('nav').innerHTML = TABS.map(t =>
    `<div class="navbtn tapfx ${state.tab === t.id ? 'on' : ''}" data-tab="${t.id}" role="tab" aria-label="${t.label}" aria-selected="${state.tab === t.id}">${SVG[t.icon]}<span>${t.label}</span></div>`).join('');
}
function switchTab(id) { const t = TABS.find(x => x.id === id); if (t) { state = { tab: id, stack: [{ s: t.root }] }; render(); } }
function navigate(s, a, b) { state.stack.push({ s, a, b }); render(); }
function back() { if (state.stack.length > 1) { state.stack.pop(); render(); } }
function mountOverlay(kind, html) { const o = document.getElementById('overlay'); o.innerHTML = html; o.hidden = false; tick(); }
function closeOverlay() { const o = document.getElementById('overlay'); o.hidden = true; o.innerHTML = ''; }

// ─── Events ─────────────────────────────────────────────────────────────────
document.addEventListener('click', e => {
  // onboarding
  if (e.target.closest('[data-onb-skip]')) { onboarded = true; closeOverlay(); return; }
  if (e.target.closest('[data-onb-next]')) {
    // Location step actually requests the permission (priming done; one real shot).
    if (onbStep === 1 && navigator.geolocation) { try { navigator.geolocation.getCurrentPosition(() => {}, () => {}); } catch (_) {} }
    if (onbStep < ONB.length - 1) { onbStep++; mountOverlay('onb', renderOnb()); } else { onboarded = true; closeOverlay(); }
    return;
  }
  // GO
  const go = e.target.closest('[data-go]'); if (go) { const [c, n] = go.dataset.go.split(':'); return openGo(c, n); }
  if (e.target.closest('[data-gonext]')) { if (goPhase < GO_PHASES.length - 1) { goPhase++; mountOverlay('go', renderGo()); autoGo(); } return; }
  if (e.target.closest('[data-closego]')) return closeGo();
  // search
  const sb = e.target.closest('[data-search]'); if (sb && !e.target.closest('[data-nav]')) return openSearch();
  if (e.target.closest('[data-closesearch]')) return closeOverlay();
  if (e.target.closest('[data-where]')) { closeOverlay(); return navigate('trip'); }
  const soft = e.target.closest('[data-soft]'); if (soft) { closeOverlay(); const [s, a, b] = soft.dataset.soft.split(':'); return navigate(s, a, b); }
  // direction segmented (line)
  const dirb = e.target.closest('[data-dir]'); if (dirb) { const [d, code] = dirb.dataset.dir.split(':'); state.stack[state.stack.length - 1].dir = Number(d); render(); return; }
  // chrome
  const tab = e.target.closest('[data-tab]'); if (tab) return switchTab(tab.dataset.tab);
  if (e.target.closest('[data-back]')) return back();
  const pin = e.target.closest('[data-stop]'); if (pin) { const st = stopBy[pin.dataset.stop]; st.saved = !st.saved; render(); return; }
  const tog = e.target.closest('[data-tog]'); if (tog) { tog.classList.toggle('on'); return; }
  const seg = e.target.closest('.seg button'); if (seg) { seg.parentElement.querySelectorAll('button').forEach(b => b.classList.remove('on')); seg.classList.add('on'); return; }
  const nav = e.target.closest('[data-nav]'); if (nav) { const [s, a, b] = nav.dataset.nav.split(':'); return navigate(s, a, b); }
});
document.getElementById('themeBtn').addEventListener('click', () => { const r = document.documentElement; r.dataset.theme = r.dataset.theme === 'dark' ? 'light' : 'dark'; });
(function clock() { const el = document.getElementById('sbTime'); if (el) el.textContent = new Date().toLocaleTimeString('en-SG', { hour: 'numeric', minute: '2-digit' }); setTimeout(clock, 10000); })();

// boot: onboarding first, then the app
render();
mountOverlay('onb', renderOnb());
setInterval(tick, 1000);
