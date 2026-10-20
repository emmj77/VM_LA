/* LA — le tableau de bord, le geste. Aucune dependance, aucune ressource externe. */
'use strict';
const $ = (s) => document.querySelector(s);
const el = (t, c, x) => { const e = document.createElement(t); if (c) e.className = c;
  if (x !== undefined && x !== null) e.textContent = String(x); return e; };
const S = { state: null, page: 'chat', hist: null, live: null, busy: false, pollMs: 1500,
            timer: null, filter: '', skill: null, project: null };

async function api(path, body) {
  const o = body === undefined ? {} : { method: 'POST', headers: { 'Content-Type': 'application/json' },
                                         body: JSON.stringify(body) };
  const r = await fetch(path, o);
  let d = {};
  try { d = await r.json(); } catch (e) { d = { ok: false, text: 'reponse illisible (' + r.status + ')' }; }
  if (!r.ok && d.ok === undefined) d.ok = false;
  return d;
}

function toast(txt, kind) {
  const t = $('#toast');
  t.textContent = txt;
  t.className = 'toast ' + (kind || '');
  clearTimeout(toast._t);
  toast._t = setTimeout(() => t.className = 'toast hid', kind === 'ko' ? 9000 : 5200);
}

/* ------------------------------------------------------------------ l entete */
function head() {
  const s = S.state; if (!s) return;
  S.pollMs = s.poll_ms || 1500;
  const sel = $('#model');
  const want = (s.model && s.model.alias) || '';
  if (sel.dataset.sig !== JSON.stringify(s.engines.map((e) => e.alias))) {
    sel.dataset.sig = JSON.stringify(s.engines.map((e) => e.alias));
    sel.innerHTML = '';
    s.engines.forEach((e) => {
      const o = el('option', null, e.alias + ' · ' + e.model);
      o.value = e.alias; o.title = e.provider; sel.appendChild(o);
    });
  }
  if (sel.value !== want) sel.value = want;
  $('#tok-session').textContent = (s.tokens.session_tokens || 0).toLocaleString('fr-FR');
  $('#tok-last').textContent = (s.tokens.last_turn || 0).toLocaleString('fr-FR');
  const turn = $('#turn');
  turn.textContent = s.turn.running ? 'en cours' : 'libre';
  turn.className = s.turn.running ? 'on' : '';
  $('#skill').textContent = s.skill || '—';
  $('#project').textContent = s.project || '—';
  $('#clock').textContent = (s.ts || '').replace('T', ' ').replace('Z', ' UTC');
  agentsMini(s.agents);
}

function doctorBadge(d) {
  const b = $('#doctor-badge');
  if (!d) return;
  b.className = 'kv ' + (d.rc === 0 ? 'ok' : 'ko');
  b.querySelector('b').textContent = d.rc === 0 ? (d.text || 'ok').split('\n')[0].slice(0, 40) : 'défaut';
  b.title = d.text || '';
}

function agentsMini(ags) {
  if (S.page === 'agents') return;
  // dans l entete on ne montre que le nombre d agents actifs
  const n = (ags || []).filter((a) => a.status === 'active').length;
  const b = $('#turn').parentElement;
  b.title = 'tour ' + (S.state.turn.running ? 'en cours (pid ' + S.state.turn.pid + ')' : 'libre') +
            ' — ' + n + ' agent(s) actif(s)';
}

/* ------------------------------------------------------------------ le chat */
const GLYPH = { toi: 'V', la: 'L', refus: '!', tableau: 'i', agent: 'A', doctor: 'D', frontière: '·' };

function glyph(who) {
  const k = String(who || '').toLowerCase();
  for (const g in GLYPH) if (k.indexOf(g) === 0) return GLYPH[g];
  return (who || '·').trim().charAt(0).toUpperCase();
}

function shortTime(ts) {
  const m = String(ts || '').match(/[T ](\d\d:\d\d)/);
  return m ? m[1] : '';
}

function bubble(kind, who, text, extra, ts) {
  const m = el('div', 'msg ' + kind);
  let w = null;
  if (who || ts) {
    w = el('div', 'who');
    w.appendChild(el('span', 'g', glyph(who)));
    if (who) w.appendChild(el('span', null, who));
    if (ts) w.appendChild(el('span', 't', ts));
    m.appendChild(w);
  }
  if (text) {
    m.appendChild(el('div', 'body', text));
    // LIRE CE MESSAGE : la voix de LA (le resident la-tts), pas celle du navigateur.
    const sp = el('button', 'sp', '♪');
    sp.type = 'button';
    sp.title = 'lire ce message à voix haute';
    sp.addEventListener('click', (e) => { e.stopPropagation(); speak(text, sp); });
    (w || m).appendChild(sp);
  }
  if (extra) m.appendChild(extra);
  return m;
}

function turnSep(t) {
  const d = el('div', 'turn-sep');
  d.appendChild(el('span', 'n', 'tour ' + (t.exchange != null ? t.exchange : '?')));
  const bits = [];
  if (t.ts) bits.push(shortTime(t.ts));
  if (t.tokens) bits.push(Number(t.tokens).toLocaleString('fr-FR') + ' jetons');
  if (bits.length) d.appendChild(el('span', null, bits.join(' · ')));
  return d;
}

function chips(tools) {
  if (!tools || !tools.length) return null;
  const d = el('div', 'tools');
  const compte = new Map();
  tools.forEach((t) => {
    const name = typeof t === 'string' ? t : t.tool;
    if (!name) return;
    const v = compte.get(name) || { n: 0, text: '' };
    v.n += 1;
    if (typeof t !== 'string' && t.text && !v.text) v.text = t.text;
    compte.set(name, v);
  });
  compte.forEach((v, name) => {
    const c = el('span', 'chip' + (name === 'reply' ? ' reply' : name === 'talk' ? ' talk' : ''),
                 v.n > 1 ? name + ' ×' + v.n : name);
    if (v.text) c.title = v.text;
    d.appendChild(c);
  });
  return d;
}

function thinkBox(list, ouvert) {
  if (!list || !list.length) return null;
  const d = el('details', 'think');
  if (ouvert) d.open = true;
  d.appendChild(el('summary', null, list.length > 1 ? 'raisonnement · ' + list.length + ' bloc(s)' : 'raisonnement'));
  d.appendChild(el('pre', null, list.join('\n\n')));
  return d;
}

function renderFeed() {
  const f = $('#feed');
  f.innerHTML = '';
  const h = S.hist;
  if (!h) {
    f.appendChild(el('div', 'skel'));
    const s2 = el('div', 'skel'); s2.style.width = '70%'; f.appendChild(s2);
    const s3 = el('div', 'skel'); s3.style.width = '45%'; f.appendChild(s3);
    return;
  }
  if (h.error) f.appendChild(bubble('note ko', 'sessions.db', h.error));
  const turns = h.turns || [];
  turns.forEach((t) => {
    f.appendChild(turnSep(t));
    if (t.demand) f.appendChild(bubble('me', 'toi', t.demand, null, shortTime(t.ts)));
    let last = null;
    const pas = (t.steps || []).filter((x) => x && (x.kind === 'think' || x.kind === 'say'));
    if (pas.length) {
      pas.forEach((x) => {
        if (x.kind === 'think') {
          const tb = thinkBox([x.text], true);
          if (tb) f.appendChild(tb);
        } else {
          last = bubble('la', 'LA', x.text, null, shortTime(t.ts));
          f.appendChild(last);
        }
      });
    } else {
      const th = thinkBox(t.think);
      if (th) f.appendChild(th);
      const lines = (t.speech || []).filter((x) => x && String(x).trim());
      if (lines.length) {
        last = bubble('la', 'LA', lines.join('\n\n'), null, shortTime(t.ts));
        f.appendChild(last);
      }
    }
    const ch = chips(t.tools);
    if (ch) {
      if (last) last.appendChild(ch);
      else { const wrap = el('div', 'msg la'); wrap.appendChild(ch); f.appendChild(wrap); }
    }
    const ref = (t.refused || []).filter((x) => x && String(x).trim());
    if (ref.length) {
      const d = el('details', 'refus-box');
      d.appendChild(el('summary', null, 'refus · ' + ref.length));
      ref.forEach((r) => d.appendChild(el('div', 'body', r)));
      f.appendChild(d);
    }
  });
  if (!turns.length) {
    const e = el('div', 'empty');
    e.appendChild(el('div', null, 'Aucun tour dans cette session.'));
    e.appendChild(el('div', null, 'Écris en bas — une ligne qui commence par / est un geste.'));
    f.appendChild(e);
  }
  drawLive();
  f.scrollTop = f.scrollHeight;
}

function liveRow(txt, cls, nm) {
  const r = el('div', 'lrow-live' + (cls ? ' ' + cls : ''));
  r.appendChild(el('span', 'tm', txt.tm));
  const tx = el('span', 'tx');
  if (nm) tx.appendChild(el('span', 'nm', nm + ' '));
  tx.appendChild(document.createTextNode(txt.body));
  r.appendChild(tx);
  return r;
}

function drawLive() {
  const L = S.live || {};
  const box = $('#live');
  const st = S.state && S.state.turn;
  const running = !!(st && st.running);
  const th = (L.thinking || []).slice(-8);
  const j = (L.journal || []).slice(-14);
  // le bloc ne vit QUE pendant le tour : un tour fini se relit dans le fil, pas ici
  if (!running) { box.classList.add('hid'); return; }
  box.classList.remove('hid');
  $('#live-pid').textContent = 'pid ' + st.pid;
  const b = $('#live-body');
  b.innerHTML = '';
  th.forEach((x) => {
    const txt = String(x.text || x.raw || '').trim();
    if (txt) b.appendChild(liveRow({ tm: shortTime(x.ts), body: txt.slice(0, 900) }, 'think'));
  });
  j.forEach((x) => {
    b.appendChild(liveRow({ tm: shortTime(x.ts), body: String(x.line || x.args || x.result || '').slice(0, 200) },
      'tool', x.tool || x.name || '?'));
  });
  // LA PHRASE PROVISOIRE : le modele parle en flux, sse.py l ecrit, on la montre AVANT la
  // validation du tour. Provisoire se dit : le message peut etre refuse et rejoue.
  const rep = ((L.reply || {}).text || '').trim();
  if (rep) b.appendChild(liveRow({ tm: shortTime((L.reply || {}).ts), body: rep.slice(0, 900) }, 'reply', 'provisoire'));
  $('#live-count').textContent = th.length + ' raisonnement(s) · ' + j.length + ' outil(s)';
  if (!b.childNodes.length) b.appendChild(el('div', 'live-empty', 'il travaille…'));
}

async function loadHistory() {
  const h = await api('/api/history?turns=' + (S.state?.feed_turns || 12));
  S.hist = h; renderFeed();
}

async function loadLive() {
  S.live = await api('/api/live'); drawLive();
}

/* --- envoyer : une demande au modele, ou une commande --- */
async function send(text) {
  text = (text || '').trim();
  if (!text || S.busy) return;
  $('#say').value = '';
  if (text[0] === '/') {
    const d = await api('/api/cmd', { line: text });
    const kind = d.kind === 'boundary' ? 'boundary' : d.kind === 'agent' ? 'agent'
      : d.kind === 'doctor' ? 'doct' : (d.ok ? 'note' : 'note ko');
    const m = bubble(kind, kind === 'boundary' ? 'session' : ('geste · ' + text.split(' ')[0]), d.text || '');
    $('#feed').appendChild(m);
    $('#feed').scrollTop = $('#feed').scrollHeight;
    if (d.kind === 'doctor') doctorBadge(d);
    refresh(true);
    return;
  }
  const mine = bubble('me', 'toi', text);
  $('#feed').appendChild(mine);
  $('#feed').scrollTop = $('#feed').scrollHeight;
  S.busy = true; $('#send').disabled = true; $('#send').textContent = '…';
  try {
    const d = await api('/api/say', { text });
    if (d.ok) {
      const br = d.bridge || {};
      const txt = br.response || br.note || '';
      if (br.queued) toast('un tour tourne : ton mot est dans la file, le modèle le lira à sa prochaine parole.', 'ok');
      if (!br.queued && txt) $('#feed').appendChild(bubble('la', 'LA', txt));
    } else {
      $('#feed').appendChild(bubble('note ko', 'le pont', (d.bridge && (d.bridge.error || d.bridge.raw)) || d.error || 'échec'));
    }
  } catch (e) {
    $('#feed').appendChild(bubble('note ko', 'réseau', String(e)));
  }
  S.busy = false; $('#send').disabled = false; $('#send').textContent = 'Envoyer';
  refresh(true);
}

/* --- le head secondaire, en direct --- */
const FOLD = new Set();

function headSection(sec) {
  const box = el('div', 'hp-sec');
  const lb = el('div', 'lb');
  lb.appendChild(el('span', 'nm', sec.label));
  lb.appendChild(el('span', 'n', sec.lines + ' l · ' + sec.bytes + ' o'));
  const cp = el('button', 'cp', '⧉');
  cp.title = 'copier cette section';
  cp.addEventListener('click', (e) => {
    e.stopPropagation();
    copyText(sec.label + '\n' + (sec.body || ''));
  });
  lb.appendChild(cp);
  const bd = el('div', 'bd', sec.body || '(vide)');
  if (FOLD.has(sec.label)) box.classList.add('fold');
  lb.addEventListener('click', () => {
    if (FOLD.has(sec.label)) FOLD.delete(sec.label); else FOLD.add(sec.label);
    box.classList.toggle('fold');
  });
  box.appendChild(lb); box.appendChild(bd);
  const l = sec.label.toUpperCase();
  if (l.indexOf('MESSAGE') >= 0) box.classList.add('msg');
  if (l.indexOf('AGENT') >= 0) box.classList.add('agents');
  if (l.indexOf('PLAN') >= 0) box.classList.add('plan');
  return box;
}

function relAge(d) {
  if (d.age_s == null) return '';
  const s = d.age_s;
  if (s < 60) return 'écrit il y a ' + s + ' s';
  if (s < 3600) return 'écrit il y a ' + Math.floor(s / 60) + ' min';
  return 'écrit il y a ' + Math.floor(s / 3600) + ' h';
}

/* LE HEAD VIENT DU PIPELINE. Le tableau ne le fabrique pas : il lit le fichier que la boucle
   dépose à chaque tour, et il le dit franchement quand le dépôt n'existe pas encore. */
async function loadHead() {
  if (!$('#head-panel') || $('#head-panel').classList.contains('hid')) return;
  const d = await api('/api/head');
  S.head = d;
  // LE HEAD EST CELUI DE L AGENT PRINCIPAL, ET L HUMAIN Y PORTE SON NOM (loi 2006).
  const nm = (S.state && S.state.names) || {};
  const who = $('#hp-who');
  if (who) {
    const u = (nm.user || '').replace(/^./, (c) => c.toUpperCase());
    who.textContent = (nm.main ? nm.main + (u ? ' · vous : ' + u : '') : (u ? 'vous : ' + u : ''));
  }
  const b = $('#hp-body');
  if (!d.present) {
    $('#hp-meta').textContent = 'aucun dépôt';
    $('#hp-demand').textContent = d.file || '';
    b.innerHTML = '';
    b.appendChild(el('div', 'hp-none',
      'Le pipeline n’a pas déposé son head. Le tableau ne le refabrique pas : il attend le fichier ' +
      'que la boucle écrit à chaque tour.'));
    return;
  }
  const all = d.sections || [];
  $('#hp-meta').textContent = all.length + ' sections · ' + (d.raw_bytes || 0) + ' octets';
  $('#hp-demand').textContent = relAge(d) + ' · ' + d.file;
  const q = ($('#hp-filter') && $('#hp-filter').value || '').trim().toLowerCase();
  const keep = q
    ? all.filter((s) => (s.label + ' ' + s.body).toLowerCase().indexOf(q) >= 0)
    : all;
  b.innerHTML = '';
  keep.forEach((s) => b.appendChild(headSection(s)));
  if (!keep.length) b.appendChild(el('div', 'hp-none', 'aucune section ne porte « ' + q + ' ».'));
}

/* ------------------------------------------------------------------ la voix */
/* LIRE UN MESSAGE. Le wav est fabriqué par le resident la-tts (via /api/tts du tableau), puis joué
   par le navigateur. Aucun tour n'est ouvert : lire n'est pas demander. */
let _AUDIO = null, _TTS = false, _TTS_URL = null;

async function speak(text, btn) {
  const t = String(text || '').trim();
  if (!t) return;
  if (_TTS) return;   // une lecture à la fois : on ne coupe pas la voix en cours de phrase
  if (!_AUDIO) { _AUDIO = new Audio(); _AUDIO.preload = 'auto'; }
  _TTS = true;
  if (btn) { btn.classList.add('busy'); btn.textContent = '…'; }
  try {
    const r = await fetch('/api/tts', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: t })
    });
    if (!r.ok) {
      let m = 'la voix a refusé (' + r.status + ')';
      try { const d = await r.json(); if (d && d.error) m = d.error; } catch (e) { /* wav ou rien */ }
      toast(m, 'ko');
      return;
    }
    const blob = await r.blob();
    if (_TTS_URL) URL.revokeObjectURL(_TTS_URL);
    _TTS_URL = URL.createObjectURL(blob);
    _AUDIO.src = _TTS_URL;
    await _AUDIO.play().catch(() => toast('le navigateur a bloqué la lecture : clique dans la page', 'ko'));
  } catch (e) {
    toast('lecture impossible : ' + e.message, 'ko');
  } finally {
    _TTS = false;
    if (btn) { btn.classList.remove('busy'); btn.textContent = '♪'; }
  }
}

/* LE DERNIER MESSAGE DE L AGENT, tel qu il est à l écran. */
function lastAgentText() {
  const feed = $('#feed');
  if (!feed) return '';
  const items = feed.querySelectorAll('.msg.agent');
  return items.length ? msgText(items[items.length - 1]) : '';
}

/* LA VOIX AUTOMATIQUE : on ne relit pas l historique, seulement ce qui arrive APRÈS l allumage. */
function maybeRead() {
  if (!S.autoAudio) return;
  const t = lastAgentText();
  if (!t || t === S.audioLast) return;
  if (!S.audioArmed) { S.audioArmed = true; S.audioLast = t; return; }
  if (_TTS) return;   // la voix finit sa phrase : ce message attend son tour, il n'est pas perdu
  S.audioLast = t;
  speak(t);
}

/* ------------------------------------------------------------------ copier */
function copyText(t) {
  const txt = String(t || '');
  if (!txt.trim()) { toast('rien à copier', 'ko'); return; }
  const ok = () => toast('copié — ' + txt.length + ' caractères', 'ok');
  const old = () => {
    const a = document.createElement('textarea');
    a.value = txt;
    a.style.position = 'fixed';
    a.style.top = '-1000px';
    a.setAttribute('readonly', '');
    document.body.appendChild(a);
    a.select();
    let done = false;
    try { done = document.execCommand('copy'); } catch (e) { done = false; }
    a.remove();
    if (done) ok(); else toast('le navigateur a refusé la copie', 'ko');
  };
  if (navigator.clipboard && window.isSecureContext) navigator.clipboard.writeText(txt).then(ok, old);
  else old();
}

function msgText(m) {
  if (!m) return '';
  if (m.tagName === 'DETAILS') return m.innerText.trim();
  if (!m.classList.contains('msg')) return m.innerText.trim();
  const out = [];
  const who = m.querySelector('.who');
  if (who) out.push(who.innerText.replace(/\s+/g, ' ').trim());
  if (m.classList.contains('boundary')) return m.innerText.trim();
  const body = m.querySelector('.body');
  if (body) out.push(body.innerText.trim());
  const chips = Array.prototype.map.call(m.querySelectorAll('.chip'), (c) => c.textContent);
  if (chips.length) out.push('[' + chips.join(' · ') + ']');
  return out.filter(Boolean).join('\n');
}

function turnText(node) {
  let start = node, end = node;
  while (start.previousElementSibling && !start.previousElementSibling.classList.contains('turn-sep')) {
    start = start.previousElementSibling;
  }
  while (end.nextElementSibling && !end.nextElementSibling.classList.contains('turn-sep')) {
    end = end.nextElementSibling;
  }
  const out = [];
  let n = start;
  while (n) {
    out.push(msgText(n));
    if (n === end) break;
    n = n.nextElementSibling;
  }
  return out.filter((x) => x && x.trim()).join('\n\n');
}

function closeCtx() { const c = $('#ctx'); if (c) c.classList.add('hid'); }

function ctxItems(x, y, items) {
  const m = $('#ctx');
  m.innerHTML = '';
  items.forEach((it) => {
    if (it === '-') { m.appendChild(el('div', 'sep')); return; }
    const b = el('button', null, it.label);
    b.setAttribute('role', 'menuitem');
    b.addEventListener('click', () => { closeCtx(); it.fn(); });
    m.appendChild(b);
  });
  m.classList.remove('hid');
  m.style.left = '0px'; m.style.top = '0px';
  const r = m.getBoundingClientRect();
  m.style.left = Math.max(4, Math.min(x, window.innerWidth - r.width - 6)) + 'px';
  m.style.top = Math.max(4, Math.min(y, window.innerHeight - r.height - 6)) + 'px';
}

document.addEventListener('contextmenu', (e) => {
  const target = e.target;
  const box = target.closest && target.closest('.msg, details.think, details.refus-box');
  if (!box || !box.closest('#feed')) return;
  e.preventDefault();
  const items = [{ label: 'copier ce message', fn: () => copyText(msgText(box)) }];
  if (box.tagName === 'DETAILS') {
    const what = box.classList.contains('think') ? 'le raisonnement' : 'les refus';
    items.unshift({ label: 'copier ' + what, fn: () => copyText(box.innerText) });
  }
  items.push('-', { label: 'copier le tour entier', fn: () => copyText(turnText(box)) });
  ctxItems(e.clientX, e.clientY, items);
});
document.addEventListener('click', closeCtx);
document.addEventListener('scroll', closeCtx, true);
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeCtx(); });

/* ------------------------------------------------------------------ la config */
function cfgRow(s, val) {
  const row = el('div', 'cfg');
  row.appendChild(el('div', 'k', s.key));
  row.appendChild(el('div', 'why', s.why || ''));
  const v = el('div', 'val');
  let ctl;
  if (s.kind === 'int') {
    ctl = el('input'); ctl.type = 'number'; ctl.min = s.min; ctl.max = s.max;
    ctl.step = s.step || 1; ctl.value = val;
  } else if (s.kind === 'choice') {
    ctl = el('select');
    s.choices.forEach((c) => { const o = el('option', null, c || '(vide)'); o.value = c; ctl.appendChild(o); });
    ctl.value = val;
  } else if (s.kind === 'order') {
    ctl = orderCtl(s, val);
  }
  const st = el('span', 'ok', '');
  const push = async () => {
    const value = s.kind === 'order' ? ctl.dataset.value : ctl.value;
    const d = await api('/api/config', { section: s.section, key: s.key, value });
    st.className = d.ok ? 'ok' : 'ko';
    st.textContent = d.ok ? 'écrit' : (d.text || 'refusé');
    toast(s.key + ' : ' + (d.text || ''), d.ok ? 'ok' : 'ko');
    if (d.ok) loadConfig();
  };
  if (s.kind === 'order') { v.appendChild(ctl); v.appendChild(mkBtn('enregistrer', push)); }
  else { ctl.addEventListener('change', push); v.appendChild(ctl); }
  v.appendChild(st);
  row.appendChild(v);
  return row;
}

function mkBtn(txt, fn, cls) {
  const b = el('button', cls || null, txt);
  b.addEventListener('click', fn);
  return b;
}

function orderCtl(s, val) {
  // L ORDRE EST UNE LISTE FERMEE : on ne tape rien, on MONTE et on DESCEND les onze sections.
  const box = el('div', 'val');
  const cur = (val || '').split(/\s+/).filter(Boolean);
  const rest = s.choices.filter((c) => !cur.includes(c));
  const list = cur.concat(rest);
  box.dataset.value = list.join(' ');
  const redraw = () => { box.dataset.value = list.join(' '); render(); };
  const render = () => {
    box.innerHTML = '';
    list.forEach((name, i) => {
      const c = el('span', 'chip', name);
      c.style.cursor = 'pointer';
      c.title = 'monter';
      c.addEventListener('click', (ev) => {
        if (ev.shiftKey) { if (i < list.length - 1) { [list[i], list[i + 1]] = [list[i + 1], list[i]]; } }
        else if (i > 0) { [list[i], list[i - 1]] = [list[i - 1], list[i]]; }
        redraw();
      });
      box.appendChild(c);
    });
    box.appendChild(el('span', 'dim small', 'clic : monter · maj+clic : descendre'));
  };
  render();
  return box;
}

async function loadConfig() {
  const d = await api('/api/config');
  const eng = $('#engines'); eng.innerHTML = '';
  (d.engines || []).forEach((e) => {
    const card = el('div', 'eng' + (e.active ? ' act' : ''));
    const top = el('div', 'top');
    top.appendChild(el('span', 'alias', e.alias));
    if (e.active) top.appendChild(el('span', 'chip reply', 'chargé'));
    top.appendChild(el('span', 'id', e.provider + ' · ' + e.model));
    const g = el('div', 'grow'); top.appendChild(g);
    const take = mkBtn('prendre', async () => {
      const r = await api('/api/cmd', { line: '/model ' + e.alias });
      toast(r.text || '', r.ok ? 'ok' : 'ko'); loadConfig(); refresh(true);
    });
    if (e.active) take.disabled = true;
    top.appendChild(take);
    card.appendChild(top);
    const grid = el('div', 'grid');
    [['thinking', d.engine_choices.thinking], ['reasoning_effort', d.engine_choices.reasoning_effort],
     ['reasoning_field', d.engine_choices.reasoning_field],
     ['stream', d.engine_choices.stream],
     ['reasoning_echo', d.engine_choices.reasoning_echo], ['tool_choice', d.engine_choices.tool_choice],
     ['max_tokens', d.engine_choices.max_tokens]].forEach(([k, list]) => {
      const f = el('div', 'f');
      f.appendChild(el('span', null, k));
      const sel = el('select');
      list.forEach((c) => { const o = el('option', null, c || '(défaut)'); o.value = c; sel.appendChild(o); });
      sel.value = e[k] === undefined ? '' : e[k];
      sel.addEventListener('change', async () => {
        const r = await api('/api/config', { section: 'engines', key: k, alias: e.alias, value: sel.value });
        toast(k + ' → ' + sel.value + ' : ' + (r.text || ''), r.ok ? 'ok' : 'ko');
      });
      f.appendChild(sel);
      grid.appendChild(f);
    });
    card.appendChild(grid);
    eng.appendChild(card);
  });

  const put = (host, kinds) => {
    host.innerHTML = '';
    (d.schema || []).filter((s) => kinds.includes(s.section)).forEach((s) => {
      host.appendChild(cfgRow(s, d.values[s.section + '.' + s.key]));
    });
  };
  put($('#cfg-loop'), ['loop']);
  put($('#cfg-second'), ['second']);
  put($('#cfg-agents'), ['agents']);
  put($('#cfg-dash'), ['dashboard']);
  put($('#cfg-bridge'), ['bridge']);
}

/* ------------------------------------------------------------------ les skills */
async function loadSkills() {
  const d = await api('/api/skills');
  const box = $('#skill-list'); box.innerHTML = '';
  const act = (d.skills || []).filter((s) => s.active).map((s) => s.name)[0];
  $('#skill-count').textContent = '(' + (d.skills || []).length + ')' + (act ? ' · ' + act : '');
  (d.skills || []).forEach((s) => {
    if (S.filter && !s.name.includes(S.filter)) return;
    const it = el('div', 'item' + (S.skill === s.name ? ' on' : ''));
    it.appendChild(el('span', 'n', s.name));
    if (s.active) it.appendChild(el('span', 'tag', 'active'));
    if (s.long_lines) it.appendChild(el('span', 'tag', s.long_lines + ' >100o'));
    it.appendChild(el('span', 'tag', s.tools + ' tools'));
    it.addEventListener('click', () => openSkill(s.name));
    box.appendChild(it);
  });
  // #skills/<nom> : on peut viser une skill par l adresse, comme le reste du tableau
  const parts = location.hash.slice(1).split('/');
  if (parts[0] === 'skills' && parts[1] && parts[1] !== S.skill) openSkill(decodeURIComponent(parts[1]));
}

const SEC_ORDER = ['SUMMARY', 'RULES', 'TOOLS', 'DOCS', 'PLAN', 'PERIMETER', 'ERROR'];

async function openSkill(name) {
  S.skill = name;
  loadSkills();
  const d = await api('/api/skill/' + encodeURIComponent(name));
  const host = $('#skill-editor');
  if (d.error) { host.innerHTML = ''; host.appendChild(el('p', 'dim', d.error)); return; }
  $('#skill-head').innerHTML = '';
  $('#skill-head').appendChild(el('h2', null, 'skill · ' + d.name));
  const sub = el('p', 'dim small', d.path + ' — ' + d.raw_lines + ' lignes. ' +
    'La liste des tools connus est celle de la table (' + (d.tools_known || []).length + ' noms).');
  $('#skill-head').appendChild(sub);
  host.innerHTML = '';
  SEC_ORDER.forEach((sec) => {
    const s = d.sections[sec];
    if (!s) return;
    host.appendChild(sectionBox(d.name, sec, s));
  });
}

function sectionBox(name, sec, s) {
  const box = el('div', 'sec');
  const head = el('div', 'sec-head');
  head.appendChild(el('span', 'name', sec));
  const rows = (s.rows || []).map((r) => Object.assign({}, r));
  const cnt = el('span', 'cnt', rows.length + ' / ' + s.max + ' lignes');
  if (rows.length > s.max) cnt.className = 'cnt over';
  head.appendChild(cnt);
  head.appendChild(el('span', 'grow'));
  if (s.range) head.appendChild(el('span', 'cnt', 'ids ' + s.range[0] + '–' + s.range[1]));
  box.appendChild(head);
  const body = el('div', 'body');
  const draw = () => {
    body.innerHTML = '';
    rows.forEach((r, i) => {
      const line = el('div', 'lrow');
      const id = el('input'); id.value = r.id; id.style.textAlign = 'right';
      id.addEventListener('input', () => { rows[i].id = id.value.trim(); });
      line.appendChild(id);
      // (ici vivait le champ en trois morceaux des STEPS : ils n existent plus, le 19/10.)
      body.appendChild(line);
    });
    const actions = el('div', 'sec-actions');
    const add = mkBtn('+ ligne', () => {
      const last = rows.length ? parseInt(rows[rows.length - 1].id, 10) : (s.range ? s.range[0] : 0);
      const next = isNaN(last) ? '' : String(last + 1);
      rows.push({ id: next, text: '' });
      draw();
    });
    const save = mkBtn('enregistrer la section', async () => {
      const payload = rows.map((r) => ({ id: r.id, text: r.text }));
      const d = await api('/api/skill', { name, section: sec, rows: payload });
      msg.className = 'sec-msg ' + (d.ok ? 'ok' : 'ko');
      msg.textContent = d.text || '';
      toast(sec + ' : ' + (d.text || ''), d.ok ? 'ok' : 'ko');
      if (d.ok) { openSkill(name); loadSkills(); }
    });
    const msg = el('span', 'sec-msg', '');
    actions.appendChild(add); actions.appendChild(save);
    actions.appendChild(el('span', 'grow')); actions.appendChild(msg);
    body.appendChild(actions);
    const c2 = rows.length + ' / ' + s.max + ' lignes';
    cnt.textContent = c2;
    cnt.className = 'cnt' + (rows.length > s.max ? ' over' : '');
  };
  draw();
  box.appendChild(body);
  return box;
}

/* ------------------------------------------------------------------ les agents */
/* UN NOM D AGENT SE LIT : agent_001_jarvis = le sous-agent n°1, du prénom jarvis. `agent_one` est
   le principal : il porte le head et il répond ici. Le tableau ne renomme rien, il déplie. */
function agentParts(name) {
  const m = /^agent_(\d{2,3})_(.+)$/.exec(name || '');
  if (m) return { tag: '#' + m[1], label: m[2], sub: true };
  return { tag: null, label: name || '', sub: false };
}

async function loadAgents() {
  const d = await api('/api/agents');
  const box = $('#agent-list'); box.innerHTML = '';
  (d.agents || []).forEach((a) => {
    const p = agentParts(a.name);
    const r = el('div', 'ag' + (a.main ? ' main' : ''));
    const nm = el('div', 'nm');
    if (p.tag) nm.appendChild(el('span', 'tg', p.tag));
    nm.appendChild(el('span', null, p.label));
    if (a.main) nm.appendChild(el('span', 'tg pr', 'principal'));
    nm.title = a.name;
    r.appendChild(nm);
    r.appendChild(el('div', 'dim', a.pid ? 'pid ' + a.pid : '—'));
    r.appendChild(el('div', 'st ' + a.status, a.status === 'active' ? 'travaille' :
      a.status === 'ended' ? 'fini' : 'à l\'arrêt'));
    r.appendChild(el('div', 'tk', a.task || (a.status === 'idle' ? '' : '(sans tâche écrite)')));
    box.appendChild(r);
  });
  const sub = (d.agents || []).length - (d.agents || []).filter((a) => a.main).length;
  $('#agent-count').textContent = (d.agents || []).length ?
    (d.agents.length + ' noms · ' + sub + ' sous-agent' + (sub > 1 ? 's' : '')) : '';
  const sel = $('#to-who');
  const cur = sel.value;
  sel.innerHTML = '';
  (d.agents || []).forEach((a) => {
    const o = el('option', null, agentParts(a.name).label);
    o.value = a.name; sel.appendChild(o);
  });
  if (cur) sel.value = cur;

  const b = $('#board'); b.innerHTML = '';
  (d.board || []).slice().reverse().forEach((m) => {
    const d0 = el('div', 'bmsg' + (m.from === 'user' ? ' mine' : ''));
    d0.appendChild(el('div', 'h', agentParts(m.from).label + ' → ' + agentParts(m.to).label +
      ' · ' + (m.ts || '')));
    d0.appendChild(el('div', null, m.body));
    b.appendChild(d0);
  });
  if (!(d.board || []).length) b.appendChild(el('p', 'dim', 'le tableau est vide.'));
}

/* ------------------------------------------------------------------ la mise à jour */
async function loadMaj() {
  const d = await api('/api/update/check');
  const v = await api('/api/version');
  $('#maj-version').textContent = (v && v.version) ? v.version : '';
  const box = $('#maj-etat'); box.innerHTML = '';
  const cm = $('#maj-commits'); cm.innerHTML = '';
  if (d.error) {
    box.appendChild(el('p', 'dim', 'l état n a pas pu être lu : ' + d.error));
    return;
  }
  if (d.dirty) box.appendChild(el('p', 'dim', "l'arbre est sale : un update refusera (commite ou range d'abord)."));
  const n = d.behind === null || d.behind === undefined ? '?' : d.behind;
  if (d.behind === 0) box.appendChild(el('p', 'dim', 'à jour sur ' + (d.upstream || '?')));
  else box.appendChild(el('p', 'dim', n + ' commit(s) attendent sur ' + (d.upstream || '?')));
  (d.commits || []).forEach((c) => {
    const it = el('div', 'item');
    it.appendChild(el('span', 'n', c));
    cm.appendChild(it);
  });
  if (!(d.commits || []).length) cm.appendChild(el('p', 'dim', 'rien à appliquer.'));
  $('#maj-note').textContent = '';
}

async function majApply() {
  if (!confirm("Appliquer la mise à jour ?\nElle refuse si l'arbre est sale ou si un tour tourne.\\nLe pont redémarre en dernier : la page clignotera une seconde.")) return;
  const r = await api('/api/update/apply', {});
  if (r.ok) {
    $('#maj-note').textContent = 'mise à jour lancée ; sa trace : ' + (r.log || 'config/state/update.log');
    toast('mise à jour lancée', 'ok');
  } else {
    toast(r.error || 'je n ai pas pu la lancer', 'ko');
  }
}

/* ------------------------------------------------------------------ la navigation */
const LOAD = { config: loadConfig, skills: loadSkills, agents: loadAgents, maj: loadMaj };

function goto(page) {
  S.page = page;
  document.querySelectorAll('#rail button').forEach((b) => b.classList.toggle('on', b.dataset.page === page));
  document.querySelectorAll('.page').forEach((p) => p.classList.toggle('on', p.id === 'page-' + page));
  const cur = location.hash.slice(1);
  if (cur.split('/')[0] !== page) history.replaceState(null, '', '#' + page);
  if (page === 'chat') { $('#feed').scrollTop = $('#feed').scrollHeight; $('#say').focus(); }
  else if (LOAD[page]) LOAD[page]();
}

/* ------------------------------------------------------------------ le pouls */
async function refresh(force) {
  const before = S.state && S.state.tokens && S.state.tokens.session;
  S.state = await api('/api/state');
  head();
  const now = S.state.tokens && S.state.tokens.session;
  if (S.page === 'chat') {
    await loadLive();
    if (force || before !== now || !S.hist) await loadHistory();
    // LA VOIX : si le bouton est allumé, la dernière réponse arrivée se dit à voix haute.
    maybeRead();
    // LE HEAD SECONDAIRE ARRIVE : le pipeline le dépose à chaque tour, et le tableau guette le
    // dépôt (mtime dans /api/state). Rien n'est relu tant que le fichier n'a pas changé.
    const st = S.state || {};
    const sig = [st.tokens && st.tokens.session, st.model, st.skill, st.project,
                 st.turn && st.turn.pid, st.head && st.head.mtime].join('|');
    if (force || !S.headAt || S.headSig !== sig) {
      S.headAt = Date.now(); S.headSig = sig; loadHead();
    }
  }
  if (S.page === 'agents' && (force || S.state.turn.running)) loadAgents();
  if (S.page === 'skills' && force) loadSkills();
}

function startPoll() {
  clearInterval(S.timer);
  S.timer = setInterval(() => { refresh(false).catch(() => {}); }, S.pollMs || 1500);
}

/* ------------------------------------------------------------------ le demarrage */
function bind() {
  document.querySelectorAll('#rail button').forEach((b) => {
    b.addEventListener('click', () => goto(b.dataset.page));
  });
  $('#model').addEventListener('change', async (e) => {
    const d = await api('/api/cmd', { line: '/model ' + e.target.value });
    toast(d.text || '', d.ok ? 'ok' : 'ko');
    refresh(true);
  });
  $('#say-form').addEventListener('submit', (e) => { e.preventDefault(); send($('#say').value); });
  $('#maj-check').addEventListener('click', () => loadMaj());
  $('#maj-apply').addEventListener('click', () => majApply());
  $('#say').addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); send($('#say').value); }
  });
  $('#stop').addEventListener('click', async () => {
    const d = await api('/api/cmd', { line: '/stop' });
    toast(d.text || '', d.ok ? 'ok' : 'ko');
  });
  $('#clear').addEventListener('click', () => { S.hist = { turns: [] }; renderFeed(); });
  // LA VOIX AUTOMATIQUE : un interrupteur, retenu d une visite a l autre.
  const au = $('#say-audio');
  if (au) {
    S.autoAudio = localStorage.getItem('la.audio') === '1';
    const paint = () => {
      au.classList.toggle('on', !!S.autoAudio);
      au.setAttribute('aria-pressed', S.autoAudio ? 'true' : 'false');
      au.textContent = S.autoAudio ? '♪ voix · on' : '♪ voix';
    };
    paint();
    au.addEventListener('click', () => {
      S.autoAudio = !S.autoAudio;
      localStorage.setItem('la.audio', S.autoAudio ? '1' : '0');
      if (S.autoAudio) { S.audioArmed = true; S.audioLast = lastAgentText(); }
      paint();
      toast(S.autoAudio ? 'les nouvelles réponses seront lues à voix haute'
                        : 'lecture automatique coupée', S.autoAudio ? 'ok' : '');
    });
  }
  // LE HEAD SECONDAIRE : on le relit a la main, on le replie, on le deplie. Son etat se retient.
  const foldHead = (off) => {
    $('#head-panel').classList.toggle('hid', off);
    $('#hp-open').classList.toggle('hid', !off);
    try { localStorage.setItem('la.head.folded', off ? '1' : '0'); } catch (e) {}
    if (!off) loadHead();
  };
  $('#hp-refresh').addEventListener('click', () => loadHead());
  $('#hp-filter').addEventListener('input', () => loadHead());
  $('#hp-copy').addEventListener('click', () => {
    const h = S.head;
    if (!h || !h.present) { toast('rien à copier : aucun head déposé', 'ko'); return; }
    copyText((h.sections || []).map((s) => '== ' + s.label + ' ==\n' + s.body).join('\n\n'));
  });
  $('#hp-close').addEventListener('click', () => foldHead(true));
  $('#hp-open').addEventListener('click', () => foldHead(false));
  try { if (localStorage.getItem('la.head.folded') === '1') foldHead(true); } catch (e) {}

  // le compteur de la demande : des octets, comme les bornes du harnais
  const sayBox = $('#say');
  const countSay = () => {
    const v = sayBox.value;
    const n = new TextEncoder().encode(v).length;
    $('#say-count').textContent = v ? n + ' octets · ' + v.split('\n').length + ' ligne(s)' : '';
  };
  sayBox.addEventListener('input', countSay);
  countSay();
  $('#skill-filter').addEventListener('input', (e) => { S.filter = e.target.value.trim(); loadSkills(); });
  $('#to-text').addEventListener('input', (e) => {
    const n = new TextEncoder().encode(e.target.value).length;
    $('#to-count').textContent = n + ' / 1024';
    $('#to-count').className = 'dim small';
  });
  $('#to-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const who = $('#to-who').value, txt = $('#to-text').value.trim();
    if (!who || !txt) return;
    const d = await api('/api/cmd', { line: '/to ' + who + ' ' + txt });
    $('#to-log').textContent = d.text || '';
    if (d.ok) { $('#to-text').value = ''; $('#to-count').textContent = '0 / 1024'; loadAgents(); }
    toast(d.text || '', d.ok ? 'ok' : 'ko');
  });
  document.addEventListener('keydown', (e) => {
    if (e.ctrlKey && e.key >= '1' && e.key <= '9') {
      e.preventDefault();
      const pages = ['chat', 'config', 'skills', 'agents', 'maj'];
      goto(pages[parseInt(e.key, 10) - 1]);
    } else if (e.ctrlKey && (e.key === 'k' || e.key === 'K')) {
      e.preventDefault(); goto('chat'); $('#say').focus();
    } else if (e.key === 'Escape') {
      if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
    }
  });
}

(async function boot() {
  bind();
  try {
    S.state = await api('/api/state');
    head();
    startPoll();
    doctorBadge(await api('/api/cmd', { line: '/doctor' }));
    await loadHistory();
    const h = location.hash.slice(1).split('/')[0];
    if (h && h !== 'chat' && LOAD[h]) goto(h);
    $('#say').focus();
  } catch (e) {
    $('#feed').appendChild(bubble('note ko', 'démarrage', 'le tableau ne joint pas son serveur : ' + e));
  }
})();