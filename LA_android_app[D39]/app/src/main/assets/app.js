/* Jarvis — l'interface. Aucune connexion réseau ici : tout passe par la passerelle native
   (window.Android). Les événements du natif arrivent dans window.JarvisApply. */

(() => {
  'use strict';

  const A = () => (window.Android && typeof window.Android === 'object' ? window.Android : null);
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
  const KEY = 'jarvis.thread.v3';
  const MAX = 120;

  const S = {
    online: null, address: '', fallback: false, jarvis: false, service: false,
    overlay: false, mic: false, notif: false, expired: false,
    recording: false, busy: false, lastMode: 'text', startedAt: 0, timer: null,
    lastFailed: false, pingAsked: false, mainName: 'Agent One', toolmap: {}
  };

  let msgs = [];
  let lastHistSig = '';   // garde anti-repaint : on ne redessine que si le contenu change
  let live = { tools: [], thinking: [] };
  let pinged = false;
  let toastTimer = null;
  let tab = 'chat';
  let skillList = [], projectList = [], engineList = [];

  const el = {
    thread: $('#thread'), empty: $('#empty'),
    statusLine: $('#statusLine'), jarvisBtn: $('#jarvisBtn'), residentsBtn: $('#residentsBtn'), activityBtn: $('#activityBtn'),
    orb: $('#orb'), orbHint: $('#orbHint'),
    input: $('#input'), composer: $('#composer'), sendBtn: $('#sendBtn'),
    micBtn: $('#micBtn'), attachBtn: $('#attachBtn'),
    recBar: $('#recBar'), recTime: $('#recTime'), recCancel: $('#recCancel'), recSend: $('#recSend'),
    sheet: $('#sheet'), pickGallery: $('#pickGallery'), pickCamera: $('#pickCamera'), sheetCancel: $('#sheetCancel'),
    actBadge: $('#actBadge'), actState: $('#actState'), actTools: $('#actTools'),
    actThinking: $('#actThinking'), actPlan: $('#actPlan'), planRefresh: $('#planRefresh'),
    addr: $('#addr'), saveAddr: $('#saveAddr'), testBtn: $('#testBtn'), fallback: $('#fallback'),
    certNote: $('#certNote'), pingTag: $('#pingTag'),
    permMic: $('#permMic'), permNotif: $('#permNotif'), permOverlay: $('#permOverlay'),
    btnOverlay: $('#btnOverlay'), btnAppSettings: $('#btnAppSettings'),
    serviceSw: $('#serviceSw'), engines: $('#engines'), enginesRefresh: $('#enginesRefresh'),
    clearBtn: $('#clearBtn'), toast: $('#toast'),
    banner: $('#banner'), bannerModel: $('#bannerModel'), bannerProvider: $('#bannerProvider'),
    speakingPill: $('#speakingPill'), speakingWho: $('#speakingWho'),
    actSkill: $('#actSkill'), actProject: $('#actProject'), actAgents: $('#actAgents'), actBoard: $('#actBoard'),
    approvalBar: $('#approvalBar'), approvalWho: $('#approvalWho'),
    approvalYes: $('#approvalYes'), approvalNo: $('#approvalNo'),
    btnUpdate: $('#btnUpdate'), updateState: $('#updateState'), appVer: $('#appVer'), toolBand: $('#toolBand'), palette: $('#palette'), modelMenu: $('#modelMenu'),
    voiceApproval: $('#voiceApproval'), wakeWord: $('#wakeWord')
  };

  /* ------------------------------------------------------------ outils */

  function load() {
    try {
      const a = JSON.parse(localStorage.getItem(KEY) || '[]');
      return Array.isArray(a) ? a.filter(m => m && m.role && typeof m.text === 'string') : [];
    } catch (e) { return []; }
  }

  function save() {
    try { localStorage.setItem(KEY, JSON.stringify(msgs.slice(-MAX))); } catch (e) { /* quota */ }
  }

  /** la pastille de marche : verte quand les residents tournent, rouge quand ils sont arretes */
  function paintPower(up, total) {
    const b = el.residentsBtn;
    if (!b) return;
    const on = (typeof up === 'number' ? up > 0 : !!up);
    b.classList.toggle('on', on);
    b.classList.toggle('off', !on);
    b.setAttribute('aria-pressed', on ? 'true' : 'false');
    const sp = b.querySelector('span');
    if (sp) sp.textContent = on ? 'Arret' : 'Marche';
    if (typeof up === 'number') b.title = (on ? 'Residents en marche : ' + up + '/' + (total || up) : 'Residents arretes') + ' — appuyer pour ' + (on ? 'arreter' : 'demarrer');
  }

  function call(name, ...args) {
    const a = A();
    if (!a || typeof a[name] !== 'function') { toast('Disponible seulement dans l’application'); return; }
    try { a[name](...args); } catch (e) { toast('Action indisponible'); }
  }

  function toast(text) {
    el.toast.textContent = text;
    el.toast.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.toast.classList.remove('show'), 2600);
  }

  function hostOf(u) {
    try { return new URL(u).host; } catch (e) { return u || '—'; }
  }

  function timeOf(ts) {
    try { return new Date(ts).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }); }
    catch (e) { return ''; }
  }

  function scrollBottom(force) {
    const t = el.thread;
    const near = t.scrollHeight - t.scrollTop - t.clientHeight < 140;
    if (force || near) requestAnimationFrame(() => { t.scrollTop = t.scrollHeight; });
  }

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, c => (
      { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
    ));
  }

  /* ------------------------------------------------------------ markdown léger */

  function md(text) {
    if (!text) return '';
    const blocks = [];
    let s = esc(text).replace(/\r\n/g, '\n');

    s = s.replace(/```([a-zA-Z0-9+#._-]*)\n([\s\S]*?)```/g, (m, lang, code) => {
      const head = lang ? `<span class="code-lang">${esc(lang)}</span>` : '';
      blocks.push(`<pre class="code">${head}<code>${code.replace(/\n$/, '')}</code></pre>`);
      return `\u0000C${blocks.length - 1}\u0000`;
    });

    s = s.replace(/`([^`\n]+)`/g, '<code>$1</code>');
    s = s.replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>');
    s = s.replace(/(^|[\s(])\*([^*\n]+)\*/g, '$1<em>$2</em>');
    s = s.replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g,
      '<a href="$2" rel="noreferrer">$1</a>');
    s = s.replace(/^###\s+(.+)$/gm, '<h3>$1</h3>');
    s = s.replace(/^##\s+(.+)$/gm, '<h2>$1</h2>');
    s = s.replace(/^#\s+(.+)$/gm, '<h1>$1</h1>');
    s = s.replace(/^&gt;\s?(.+)$/gm, '<blockquote>$1</blockquote>');
    s = s.replace(/(?:^|\n)[-*]\s+(.+)(?=\n|$)/g, '\n<li>$1</li>');
    s = s.replace(/(<li>[\s\S]*?<\/li>)(?!\n?<li>)/g, '<ul>$1</ul>');

    s = s.split(/\n{2,}/).map(p => {
      const t = p.trim();
      if (!t) return '';
      if (/^<(h\d|ul|pre|blockquote)/.test(t)) return t;
      if (/^\u0000C\d+\u0000$/.test(t)) return t;
      return `<p>${t.replace(/\n/g, '<br>')}</p>`;
    }).join('');

    s = s.replace(/\u0000C(\d+)\u0000/g, (m, i) => blocks[Number(i)] || '');
    return s;
  }

  function shortPath(p) {
    p = String(p == null ? '' : p).trim();
    if (!p || p.length > 120 || !/[\/\\.]/.test(p)) return '';
    const parts = p.split('/').filter(Boolean);
    return parts.slice(-2).join('/');
  }
  function toolLabel(line) {
    const r = resolveTool(line);
    if (isSpeech(r.name)) return (r.name === 'reply' || r.name === 'talk') ? 'parole' : r.name;
    const sp = shortPath(r.path);
    return sp ? (r.name + ' (' + sp + ')') : (r.name || 'outil');
  }

  /* ------------------------------------------------------------ rendu du fil */

  function renderThread() {
    const t = el.thread;
    const nearBottom = (t.scrollHeight - t.scrollTop - t.clientHeight) < 140;
    const keep = t.scrollTop;
    t.innerHTML = '';
    msgs.forEach(m => t.appendChild(nodeOf(m)));
    t.classList.toggle('empty-thread', msgs.length === 0 && !S.busy);
    el.empty.classList.toggle('hidden', msgs.length > 0);
    if (S.busy) t.appendChild(liveCard());
    // on ne fait JAMAIS sauter l'ecran : on reste en bas seulement si on y etait, sinon on garde la place
    if (nearBottom) requestAnimationFrame(() => { t.scrollTop = t.scrollHeight; });
    else t.scrollTop = keep;
  }

  function nodeOf(m) {
    const wrap = document.createElement('div');
    wrap.className = 'msg ' + (m.role === 'user' ? 'user' : 'bot') + (m.kind === 'error' ? ' error' : '');

    if (m.role === 'user') {
      const b = document.createElement('div');
      b.className = 'bubble';
      b.textContent = m.text || '🎙️';
      if (m.pending) b.style.opacity = '.6';
      wrap.appendChild(b);
      if (!m.pending) {
        const meta = document.createElement('div');
        meta.className = 'meta user-meta';
        const copy = document.createElement('button');
        copy.type = 'button';
        copy.textContent = 'Copier';
        copy.addEventListener('click', () => copyText(m.text));
        meta.appendChild(copy);
        wrap.appendChild(meta);
      }
      return wrap;
    }

    const top = document.createElement('div');
    top.className = 'row-top';
    const av = document.createElement('div');
    av.className = 'avatar';
    av.innerHTML = '<i></i>';
    const b = document.createElement('div');
    b.className = 'bubble-bot md';
    if (m.text) b.innerHTML = md(m.text);
    else if (m.thinking && m.thinking.length) b.classList.add('sans-texte');   // la pensee seule ne fait pas une bulle
    else b.innerHTML = '—';
    top.appendChild(av);
    top.appendChild(b);
    // la pensee vit hors de la bulle, juste au-dessus : elle n habille pas le message
    const th = (m.thinking && m.thinking.length) ? thinkNode(m.thinking) : null;
    if (th) wrap.appendChild(th);
    wrap.appendChild(top);

    const meta = document.createElement('div');
    meta.className = 'meta';
    const t = document.createElement('span');
    t.textContent = timeOf(m.ts);
    meta.appendChild(t);

    if (m.code && m.code !== 0) {
      const c = document.createElement('span');
      c.className = 'code-bad';
      c.textContent = 'code ' + m.code;
      meta.appendChild(c);
    }

    if (m.audios && m.audios.length) {
      const listen = document.createElement('button');
      listen.type = 'button';
      listen.innerHTML = '<svg viewBox="0 0 24 24" class="ic"><path d="M4 9v6h4l5 4V5L8 9H4zM17 9a4 4 0 0 1 0 6"/></svg>Écouter';
      listen.addEventListener('click', () => call('playAudio', m.audios[m.audios.length - 1]));
      meta.appendChild(listen);
    }

    const copy = document.createElement('button');
    copy.type = 'button';
    copy.textContent = 'Copier';
    copy.addEventListener('click', () => copyText(m.text));
    meta.appendChild(copy);

    wrap.appendChild(meta);
    return wrap;
  }

  function parseCell(x) {
    if (typeof x === 'string') {
      const t = x.trim();
      if (t.charAt(0) === '{' || t.charAt(0) === '[') { try { return JSON.parse(t); } catch (e) {} }
    }
    return x;
  }
  function flatItems(src) {
    const out = [];
    const push = v => {
      const p = parseCell(v);
      if (Array.isArray(p)) p.forEach(push);
      else out.push(p);
    };
    (Array.isArray(src) ? src : [src]).forEach(push);
    return out;
  }
  function thinkText(lines) {
    return flatItems(lines)
      .map(x => (x && typeof x === 'object') ? (x.text || '') : String(x == null ? '' : x))
      .filter(t => t && t.trim()).join('\n\n');
  }

  function thinkNode(lines) {
    const text = thinkText(lines);
    if (!text.trim()) return null;
    const wrap = document.createElement('div');
    wrap.className = 'think-wrap';
    const lab = document.createElement('div');
    lab.className = 'think-label';
    lab.textContent = 'Raisonnement';
    const line = document.createElement('div');
    line.className = 'think-line';
    line.textContent = text;
    wrap.appendChild(lab);
    wrap.appendChild(line);
    wrap.addEventListener('click', () => wrap.classList.toggle('open'));
    return wrap;
  }

  function liveCard() {
    let card = $('#liveCard');
    if (card) return card;
    card = document.createElement('div');
    card.id = 'liveCard';
    card.className = 'msg bot live-card';
    card.innerHTML = `
      <div class="avatar"><i></i></div>
      <div class="live-body">
        <div class="live-title">
          <span class="dots"><i></i><i></i><i></i></span>
          <span id="liveTitle">Jarvis réfléchit…</span>
          <button id="liveStop" class="ghost sm" type="button" style="margin-left:auto">Arrêter</button>
        </div>
        <div id="liveThinkPrev" class="think-line" style="display:none"></div>
      </div>`;
    card.querySelector('#liveStop').addEventListener('click', () => {
      call('stopTurn');
      toast('Arrêt demandé');
    });
    return card;
  }

  function isSpeech(n) { return n === 'reply' || n === 'talk' || n === 'answer' || n === 'ask'; }

  function resolveTool(line) {
    if (!line) return { name: '', path: '' };
    if (typeof line === 'object') {
      if (line.name) return { name: line.name, path: line.path || '' };
      if (line.la) {
        const g = line.la.g;
        const a = Array.isArray(line.la.a) ? line.la.a : [];
        const nm = (S.toolmap && S.toolmap[String(g)]) ? S.toolmap[String(g)] : String(g);
        const p = (a[0] != null && !isSpeech(String(a[0]))) ? String(a[0]) : '';
        return { name: nm, path: p };
      }
      return { name: line.tool || '', path: line.path || '' };
    }
    return { name: String(line), path: '' };
  }

  function lastBotTools() {
    for (let i = msgs.length - 1; i >= 0; i--) if (msgs[i].role === 'bot') return Array.isArray(msgs[i].tools) ? msgs[i].tools : [];
    return [];
  }

  function paintToolBand() {
    const b = el.toolBand; if (!b) return;
    const raw = (S.busy && Array.isArray(live.tools) && live.tools.length) ? live.tools : lastBotTools();
    const compte = new Map();
    raw.forEach(line => {
      const r = resolveTool(line);
      if (!r.name || isSpeech(r.name)) return;
      const sp = shortPath(r.path);
      const lab = sp ? (r.name + ' (' + sp + ')') : r.name;
      compte.set(lab, (compte.get(lab) || 0) + 1);
    });
    const chips = [...compte].map(([t, n]) => (n > 1 ? t + ' \u00d7' + n : t));
    if (!chips.length) { b.classList.add('hidden'); b.innerHTML = ''; return; }
    b.classList.remove('hidden'); b.innerHTML = '';
    const cap = document.createElement('span'); cap.className = 'band-cap'; cap.textContent = 'Outils';
    b.appendChild(cap);
    chips.slice(-8).forEach(t => { const s = document.createElement('span'); s.className = 'tool'; s.textContent = t; b.appendChild(s); });
  }

  function renderLive(title) {
    const card = liveCard();
    if (!el.thread.contains(card)) el.thread.appendChild(card);
    paintToolBand();
    const cap = card.querySelector('#liveTitle');
    if (title) cap.textContent = title;
    const tp = card.querySelector('#liveThinkPrev');
    if (live.thinking.length) {
      const txt = live.thinking.join('\n\n');
      if (tp) { tp.style.display = 'block'; tp.textContent = txt; }
    }
    scrollBottom(false);
  }

  function dropLive() {
    const c = $('#liveCard');
    if (c) c.remove();
  }

  /* ------------------------------------------------------------ messages */

  function addMsg(m) {
    m.ts = m.ts || Date.now();
    msgs.push(m);
    if (msgs.length > MAX) msgs = msgs.slice(-MAX);
    save();
    el.thread.classList.remove('empty-thread');
    el.empty.classList.add('hidden');
    const node = nodeOf(m);
    el.thread.appendChild(node);
    scrollBottom(true);
    return m;
  }

  function pendingUser() {
    for (let i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].role === 'user' && msgs[i].pending) return msgs[i];
    }
    return null;
  }

  function copyText(text) {
    try {
      const ta = document.createElement('textarea');
      ta.value = text || '';
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
      toast('Copié');
    } catch (e) { toast('Copie impossible'); }
  }

  /* ------------------------------------------------------------ voix */

  function toggleRec() {
    if (S.busy) { toast('Un tour tourne : attends ou arrête-le'); return; }
    if (S.recording) call('stopVoice');
    else call('startVoice');
  }

  function startTimer() {
    S.startedAt = Date.now();
    clearInterval(S.timer);
    el.recTime.textContent = '0:00';
    S.timer = setInterval(() => {
      const s = Math.floor((Date.now() - S.startedAt) / 1000);
      el.recTime.textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
    }, 250);
  }

  function setRecording(on) {
    S.recording = !!on;
    document.body.classList.toggle('recording', S.recording);
    el.recBar.classList.toggle('hidden', !S.recording);
    el.composer.classList.toggle('hidden', S.recording || tab !== 'chat');
    el.orbHint.textContent = S.recording ? 'Appuie pour envoyer' : 'Appuie pour parler';
    if (S.recording) startTimer();
    else { clearInterval(S.timer); S.timer = null; }
  }

  function sendText(text) {
    hidePalette();
    if (el.modelMenu) el.modelMenu.classList.add('hidden');
    const t = (text || '').trim();
    if (!t) return;
    if (t.charAt(0) === '/') { runCommand(t); return; }
    if (S.busy) { toast('Un tour tourne déjà'); return; }
    addMsg({ role: 'user', text: t, ts: Date.now() });
    el.input.value = '';
    resize();
    updateSend();
    S.busy = true;
    S.lastMode = 'text';
    live = { tools: [], thinking: [] };
    renderLive('Jarvis réfléchit…');
    call('send', t);
  }

  function runCommand(t) {
    el.input.value = '';
    resize();
    updateSend();
    call('command', t);
  }

  function applyCommand(d) {
    d = d || {};
    const kind = d.kind || 'note';
    const ok = d.ok !== false;
    const txt = (d.text || '').trim();
    if (kind === 'boundary') {
      msgs = [];
      renderThread();
      toast(txt || 'Nouvelle session');
      syncShared();
      return;
    }
    if (kind === 'reply') {
      if (txt) addMsg({ role: 'bot', text: txt, ts: Date.now(), code: 0 });
      syncShared();
      return;
    }
    if (txt) addMsg({ role: 'bot', kind: ok ? 'note' : 'error', text: (ok ? '' : '⚠️ ') + txt, ts: Date.now() });
  }

  let approvalTimer = 0;

  function applyApproval(d) {
    if (!el.approvalBar) return;
    const pending = !!(d && d.pending);
    if (!pending) {
      el.approvalBar.classList.add('hidden');
      S.awaitApproval = false;
      S.lastApprovalKey = '';
      if (approvalTimer) { clearInterval(approvalTimer); approvalTimer = 0; }
      return;
    }
    // l ecran parle francais : le pont envoie l objet, la phrase se fait ici
    const who = (d.tool || d.gesture || 'un geste').trim();
    const left = Number(d.left || 0);
    const say = 'Le moteur demande : ' + who + (left ? ' — ' + left + ' s' : '');
    el.approvalWho.textContent = say;
    el.approvalBar.classList.remove('hidden');
    if (!approvalTimer) approvalTimer = setInterval(() => call('approval'), 5000);
    const key = who + '|' + (d.age || 0);
    if (S.lastApprovalKey === key) return;
    S.lastApprovalKey = key;
    // une demande laisse une trace dans le fil : on ne demande jamais dans le vide
    addMsg({ role: 'bot', kind: 'note', text: '⏸ ' + say, ts: Date.now() });
    if (S.voiceApproval !== false) { S.awaitApproval = true; call('speak', who); }
  }

  function norm(s) {
    return (s || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z ]/g, '').replace(/\s+/g, ' ').trim();
  }
  function lev(a, b) {
    const m = a.length, n = b.length;
    const d = Array.from({ length: m + 1 }, (_, i) => [i, ...Array(n).fill(0)]);
    for (let j = 0; j <= n; j++) d[0][j] = j;
    for (let i = 1; i <= m; i++) for (let j = 1; j <= n; j++)
      d[i][j] = Math.min(d[i-1][j] + 1, d[i][j-1] + 1, d[i-1][j-1] + (a[i-1] === b[j-1] ? 0 : 1));
    return d[m][n];
  }
  function sim(a, b) { a = a.replace(/ /g, ''); b = b.replace(/ /g, ''); const m = Math.max(a.length, b.length); return m ? 1 - lev(a, b) / m : 1; }
  function handleHeard(t) {
    const n = norm(t);
    if (!n) { toast('Je n\'ai rien entendu — touche Valider ou Refuser'); return; }
    const a = Math.max(sim(n, 'valider'), sim(n, 'valide'), sim(n, 'accord'), sim(n, 'accepter'));
    const r = Math.max(sim(n, 'refuser'), sim(n, 'refuse'), sim(n, 'annuler'), sim(n, 'rejeter'));
    if (a >= 0.45 && a >= r) { toast('Entendu « ' + t + ' » — j\'autorise'); call('approve'); }
    else if (r >= 0.45) { toast('Entendu « ' + t + ' » — je refuse'); call('deny'); }
    else toast('Entendu « ' + t + ' » — pas reconnu, touche Valider ou Refuser');
  }

  /* ------------------------------------------------------------ état natif */

  function applyState(e) {
    if (typeof e.address === 'string' && e.address) S.address = e.address;
    if (typeof e.fallback === 'boolean') S.fallback = e.fallback;
    if (typeof e.jarvis === 'boolean') S.jarvis = e.jarvis;
    if (typeof e.service === 'boolean') S.service = e.service;
    if (typeof e.overlay === 'boolean') S.overlay = e.overlay;
    if (typeof e.mic === 'boolean') S.mic = e.mic;
    if (typeof e.notif === 'boolean') S.notif = e.notif;
    if (typeof e.expired === 'boolean') S.expired = e.expired;
    if (typeof e.running === 'boolean' && !e.running && S.busy) S.busy = false;
    paint();
    if (!pinged && S.address) { pinged = true; call('ping'); }
  }

  function paint() {
    const host = hostOf(S.address);
    if (S.online === true) {
      el.statusLine.textContent = 'En ligne · ' + host;
    } else if (S.online === false) {
      el.statusLine.textContent = 'Injoignable · ' + host;
    } else {
      el.statusLine.textContent = S.address ? 'Connexion à ' + host + '…' : 'Connexion…';
    }
    document.body.classList.toggle('offline', S.online === false);
    el.jarvisBtn.setAttribute('aria-pressed', S.jarvis ? 'true' : 'false');

    el.pingTag.textContent = S.online === true ? 'en ligne' : S.online === false ? 'injoignable' : '?';
    el.pingTag.className = 'tag ' + (S.online === true ? 'ok' : S.online === false ? 'bad' : '');

    if (document.activeElement !== el.addr) el.addr.value = S.address || '';
    el.fallback.checked = !!S.fallback;
    el.serviceSw.checked = !!S.service;
    el.certNote.classList.toggle('hidden', !S.expired);

    perm(el.permMic, S.mic);
    perm(el.permNotif, S.notif);
    perm(el.permOverlay, S.overlay);
  }

  function perm(node, ok) {
    node.textContent = ok ? 'accordé' : 'refusé';
    node.className = 'tag ' + (ok ? 'ok' : 'bad');
  }

  /* ------------------------------------------------------------ vue unifiée (poste) */

  function prettyAgent(id) {
    return String(id || '').replace(/[_-]+/g, ' ').replace(/\b\w/g, c => c.toUpperCase()).trim();
  }

  function setBanner(st) {
    const m = st && st.model ? st.model : {};
    const model = m.model || m.alias || '—';
    const prov = m.provider && m.provider !== model ? m.provider : '';
    el.bannerModel.textContent = model;
    el.bannerProvider.textContent = prov ? '· ' + prov : '';
    if (st && st.names && st.names.main) S.mainName = prettyAgent(st.names.main);
  }

  function renderSharedState(st) {
    if (!st) return;
    setBanner(st);
    if (el.actSkill) el.actSkill.textContent = st.skill || '—';
    if (el.actProject) el.actProject.textContent = st.project || '—';
    if (st.turn && typeof st.turn.running === 'boolean' && !S.busy) {
      el.actBadge.textContent = st.turn.running ? 'en cours' : 'repos';
      el.actBadge.className = 'tag ' + (st.turn.running ? 'bad' : '');
    }
  }

  function renderAgentsData(d) {
    const list = d && Array.isArray(d.agents) ? d.agents : [];
    if (!list.length) {
      el.actAgents.innerHTML = '<p class="muted small">Aucun agent.</p>';
    } else {
      el.actAgents.innerHTML = '';
      list.forEach(a => {
        const row = document.createElement('div');
        row.className = 'agent-row' + (a.main ? ' main' : '');
        const dot = document.createElement('span');
        dot.className = 'dot' + (a.status === 'idle' ? ' idle' : '');
        const an = document.createElement('span');
        an.className = 'an';
        an.textContent = prettyAgent(a.name) + (a.main ? ' ★' : '');
        const role = document.createElement('span');
        role.className = 'role';
        role.textContent = a.status || '';
        row.appendChild(dot); row.appendChild(an); row.appendChild(role);
        el.actAgents.appendChild(row);
      });
    }
    if (d && Array.isArray(d.board)) renderBoard(d.board);
  }

  function renderBoard(items) {
    if (!items.length) {
      el.actBoard.innerHTML = '<p class="muted small">Pas encore d’échange inter-agent.</p>';
      return;
    }
    el.actBoard.innerHTML = '';
    items.slice(-40).forEach(it => {
      const p = document.createElement('div');
      p.className = 'board-msg';
      const who = it.name || it.from || it.agent || 'agent';
      const txt = it.text || it.content || it.message || '';
      const t = it.ts || it.time || '';
      p.innerHTML = '<b>' + esc(prettyAgent(who)) + '</b>' +
        (t ? '<time>' + esc(timeOf(t)) + '</time>' : '') + '<br>' + esc(String(txt));
      el.actBoard.appendChild(p);
    });
    el.actBoard.scrollTop = el.actBoard.scrollHeight;
  }

  function applyHistory(h) {
    const turns = h && Array.isArray(h.turns) ? h.turns : [];
    const out = [];
    turns.forEach(t => {
      const ts = Date.parse(t.ts) || Date.now();
      const outils = (Array.isArray(t.tool_calls) && t.tool_calls.length) ? t.tool_calls
                    : (Array.isArray(t.tools) ? t.tools : []);
      let lastBot = null, thought = '';
      (Array.isArray(t.thread) ? t.thread : []).forEach((b, i) => {
        const txt = (b && b.text) ? String(b.text) : '';
        if (!txt.trim()) return;
        if (b.role === 'user') { thought = ''; out.push({ role: 'user', text: txt, ts: ts + i }); return; }
        // une pensee n est pas un message : elle se pose au-dessus de la reponse qui la suit
        if (b.role === 'reasoning') { thought = thought ? thought + '\n\n' + txt : txt; return; }
        const own = (b && b.reasoning) ? String(b.reasoning) : '';
        lastBot = { role: 'bot', text: txt, ts: ts + 1 + i,
                    thinking: [own || thought].filter(Boolean), tools: [], code: 0 };
        thought = '';
        out.push(lastBot);
      });
      if (outils.length && lastBot) lastBot.tools = outils;
    });
    // an empty answer from the base is not a reason to erase what the phone already holds
    if (!out.length) return;
    const next = out.slice(-MAX);
    const last = next.length ? next[next.length - 1] : null;
    const sig = next.length + '|' + (last ? (last.role + ':' + (last.text || '').length + ':' + last.ts) : '');
    if (sig === lastHistSig) return;   // rien n'a change -> on ne redessine pas (fin des sauts a repetition)
    lastHistSig = sig;
    msgs = next;
    renderThread();
    paintToolBand();
  }

  function syncShared() {
    call('refreshShared');
  }

  function showSpeaking(on) {
    if (!el.speakingPill) return;
    if (on) {
      el.speakingWho.textContent = (S.mainName || 'Agent One') + ' parle…';
      el.speakingPill.classList.remove('hidden');
    } else {
      el.speakingPill.classList.add('hidden');
    }
  }

  /* ------------------------------------------------------------ événements */

  window.JarvisApply = function (raw) {
    let e;
    try { e = typeof raw === 'string' ? JSON.parse(raw) : raw; } catch (x) { return; }
    if (!e || !e.type) return;

    switch (e.type) {
      case 'state':
        applyState(e);
        break;

      case 'toast': { toast(m.text || ''); break; }

      case 'residentsReport': { paintPower(m.up, m.total); break; }
      case 'ping':
        S.online = !!e.online;
        S.expired = !!e.expired;
        if (e.target) S.address = e.target;
        if (S.pingAsked) {
          toast(e.online ? 'Pont joignable' : 'Pont injoignable');
          S.pingAsked = false;
        }
        paint();
        break;

      case 'recording': {
        const on = !!e.on;
        if (!on) { setRecording(false); }
        else {
          setRecording(true);
          live = { tools: [], thinking: [] };
          dropLive();
        }
        break;
      }

      case 'uploading': {
        if (!pendingUser()) addMsg({ role: 'user', text: '', pending: true, ts: Date.now() });
        S.busy = true;
        live = { tools: [], thinking: [] };
        renderLive('Je transcris ta voix…');
        break;
      }

      case 'turnStart':
        S.busy = true;
        S.lastMode = e.mode || 'text';
        live = { tools: [], thinking: [] };
        el.actBadge.textContent = 'en cours';
        el.actBadge.className = 'tag bad';
        el.actState.textContent = e.mode === 'voice' ? 'Tour vocal : transcription, modèle, voix.' :
          e.mode === 'image' ? 'Tour avec image.' : 'Tour écrit.';
        renderLive(e.mode === 'voice' ? 'Je transcris et je réfléchis…' : 'Jarvis réfléchit…');
        break;

      case 'tools':
        live.tools = flatItems(e.items);
        renderLive();
        paintActivityTools();
        break;

      case 'thinking': {
        live.thinking = flatItems(e.items)
          .map(x => (x && typeof x === 'object') ? (x.text || '') : String(x || ''))
          .filter(s => s && s.trim().length);
        renderLive();
        el.actThinking.textContent = live.thinking.length ? live.thinking.join('\n\n') : '—';
        break;
      }

      case 'turn':
        onTurn(e);
        break;

      case 'command':
        applyCommand(e.data);
        break;

      case 'skills':
        skillList = (e.data && Array.isArray(e.data.skills)) ? e.data.skills : [];
        renderPalette();
        break;

      case 'projects':
        projectList = (e.data && Array.isArray(e.data.projects)) ? e.data.projects : [];
        renderPalette();
        break;

      case 'toolmap':
        S.toolmap = (e.data && e.data.map) ? e.data.map : {};
        paintToolBand();
        break;

      case 'approval':
        applyApproval(e.data);
        break;

      case 'approveResult': {
        const d = e.data || {};
        toast(d.ok === false ? ('Refusé : ' + (d.text || '')) : (d.text || 'Feu vert signé'));
        if (d.ok !== false && d.text && /feu vert/i.test(d.text)) {
          const last = [...msgs].reverse().find(m => m.role === 'user' && m.text && m.text.charAt(0) !== '/');
          if (last && !S.busy) sendText(last.text);
        }
        syncShared();
        break;
      }

      case 'version':
        if (el.appVer) el.appVer.textContent = 'v' + (e.version || '?');
        break;

      case 'update':
        if (el.updateState) {
          el.updateState.classList.remove('hidden');
          el.updateState.textContent = e.state === 'download' ? 'Téléchargement de la mise à jour…' : 'APK prête : suis l\u2019installeur système.';
        }
        if (e.state === 'ready') toast('APK téléchargée : valide l\u2019installation');
        break;

      case 'error':
        S.busy = false;
        S.lastFailed = true;
        setRecording(false);
        dropLive();
        toast(e.message || 'Échec');
        {
          const p = pendingUser();
          if (p && !p.text) { p.pending = false; p.text = '🎙️ (voix non transcrite)'; save(); renderThread(); }
        }
        addMsg({ role: 'bot', kind: 'error', text: '⚠️ ' + (e.message || 'Échec du tour'), ts: Date.now() });
        el.actBadge.textContent = 'erreur';
        el.actBadge.className = 'tag bad';
        el.actState.textContent = e.message || 'Échec';
        break;

      case 'stopped':
        S.busy = false;
        dropLive();
        toast('Tour arrêté');
        el.actBadge.textContent = 'arrêté';
        el.actBadge.className = 'tag';
        break;

      case 'engines':
        engineList = Array.isArray(e.items) ? e.items : [];
        renderEngines(engineList);
        renderModelMenu(engineList);
        break;

      case 'engine':
        toast('Adresse : ' + e.alias);
        break;

      case 'plan':
        el.actPlan.textContent = (e.text || '').trim() || '—';
        break;

      case 'heard':
        handleHeard(e.text || '');
        break;

      case 'wake':
        toast("Mot d'éveil reconnu — je t'écoute.");
        break;

      case 'playing':
        document.body.classList.add('speaking');
        break;

      case 'idle':
        document.body.classList.remove('speaking');
        if (S.awaitApproval && S.voiceApproval !== false) { S.awaitApproval = false; call('approvalListen', 6000); }
        maybeReListen();
        break;

      case 'user':
        addMsg({ role: 'user', text: e.text || '📷 Photo', kind: e.kind || '', ts: Date.now() });
        break;

      case 'history':
        applyHistory(e.data || {});
        break;

      case 'sharedState':
        renderSharedState(e.data);
        break;

      case 'agentsData':
        renderAgentsData(e.data);
        break;

      case 'speaking':
        showSpeaking(!!e.on);
        break;
    }
  };

  function onTurn(e) {
    S.busy = false;
    setRecording(false);

    // La transcription du tour vocal remplace la bulle en attente.
    const p = pendingUser();
    const said = (e.request || '').trim();
    if (p) {
      p.pending = false;
      p.text = said || (e.mode === 'voice' ? '🎙️ (rien de transcrit)' : '🎙️');
      save();
    } else if (said && e.mode === 'voice') {
      msgs.push({ role: 'user', text: said, ts: Date.now() });
      save();
    }

    dropLive();

    if (e.queued) {
      toast(e.note || 'Message mis en file pour le prochain tour');
      renderThread();
    } else {
      const code = Number(e.code || 0);
      const text = (e.response || '').trim();
      S.lastFailed = code !== 0 || !text;
      addMsg({
        role: 'bot',
        text: text || (code !== 0 ? `Le poste a rendu le code ${code}.` : 'Réponse vide.'),
        kind: code !== 0 ? 'error' : '',
        code: code,
        audios: Array.isArray(e.audios) ? e.audios : [],
        thinking: live.thinking.slice(),
        tools: live.tools.slice(),
        ts: Date.now()
      });
      if (said && e.mode === 'voice' && p) renderThread();
      el.actBadge.textContent = code === 0 ? 'terminé' : 'code ' + code;
      el.actBadge.className = 'tag ' + (code === 0 ? 'ok' : 'bad');
      el.actState.textContent = text ? text.slice(0, 240) : 'Réponse vide';
      if (document.hidden && code === 0 && text) call('notifyMessage', (S.mainName || 'Agent One'), text.slice(0, 240));
    }

    live = { tools: [], thinking: [] };
    updateSend();
    paintToolBand();
    if (!e.queued) setTimeout(syncShared, 300);
  }

  function maybeReListen() {
    if (!S.jarvis || S.busy || S.recording || S.lastFailed) return;
    if (S.lastMode !== 'voice') return;
    if (document.visibilityState !== 'visible') return;
    setTimeout(() => {
      if (S.jarvis && !S.busy && !S.recording && document.visibilityState === 'visible') call('startVoice');
    }, 450);
  }

  function paintActivityTools() {
    el.actTools.innerHTML = '';
    live.tools.forEach(line => {
      const c = document.createElement('span');
      c.className = 'tool';
      c.textContent = toolLabel(line);
      c.title = line;
      el.actTools.appendChild(c);
    });
  }

  function renderEngines(items) {
    if (!items.length) {
      el.engines.innerHTML = '<p class="muted small">Aucune adresse lue.</p>';
      return;
    }
    el.engines.innerHTML = '';
    items.forEach(it => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'engine' + (it.active ? ' active' : '');
      b.innerHTML = `<span><span class="alias">${esc(it.alias || '—')}</span><br>
        <span class="model">${esc(it.model || '')}</span></span>
        <span class="tag ${it.active ? 'ok' : ''}">${it.active ? 'active' : 'prendre'}</span>`;
      b.addEventListener('click', () => call('takeEngine', it.alias || ''));
      el.engines.appendChild(b);
    });
  }

  /* ------------------------------------------------------------ interface */

  function resize() {
    el.input.style.height = 'auto';
    el.input.style.height = Math.min(el.input.scrollHeight, 132) + 'px';
  }

  function updateSend() {
    const has = el.input.value.trim().length > 0;
    el.sendBtn.disabled = !has;
  }

  function switchTab(name) {
    tab = name;
    $$('.tab').forEach(t => t.classList.toggle('on', t.dataset.tab === name));
    $('#viewChat').classList.toggle('hidden', name !== 'chat');
    $('#viewActivity').classList.toggle('hidden', name !== 'activity');
    $('#viewSettings').classList.toggle('hidden', name !== 'settings');
    el.composer.classList.toggle('hidden', name !== 'chat' || S.recording);
    if (name === 'activity') { call('plan'); call('refreshShared'); }
    if (name === 'settings') { paint(); call('appVersion'); }
    if (name === 'chat') scrollBottom(true);
  }

  /* ------------------------------------------------ palette + menu modeles */

  const CMDS = [
    { c: '/new',     d: 'Nouvelle session',   arg: false },
    { c: '/stop',    d: 'Arrêter le tour',    arg: false },
    { c: '/model',   d: 'Choisir le modèle',  arg: true  },
    { c: '/skill',   d: 'Charger une skill',  arg: true  },
    { c: '/project', d: 'Charger un projet',  arg: true  },
    { c: '/doctor',  d: 'État du poste',      arg: false },
    { c: '/tools',   d: 'Chercher un outil',  arg: true  },
    { c: '/to',      d: 'Écrire à un agent',  arg: true  },
    { c: '/delegate',d: 'Déléguer',           arg: true  }
  ];

  function hidePalette() {
    if (el.palette) { el.palette.classList.add('hidden'); el.palette.innerHTML = ''; }
  }

  function palItems() {
    const v = el.input.value || '';
    if (v.charAt(0) !== '/') return null;
    const sp = v.indexOf(' ');
    if (sp === -1) {
      const q = v.toLowerCase();
      return CMDS.filter(c => c.c.indexOf(q) === 0).map(c => ({
        label: c.c, hint: c.d,
        run: () => {
          if (c.arg) { el.input.value = c.c + ' '; resize(); updateSend(); renderPalette(); el.input.focus(); }
          else { sendText(c.c); hidePalette(); }
        }
      }));
    }
    const head = v.slice(0, sp).toLowerCase();
    const rest = v.slice(sp + 1).trim().toLowerCase();
    const match = n => !rest || (n || '').toLowerCase().indexOf(rest) >= 0;
    if (head === '/skill') return skillList.filter(s => match(s.name)).slice(0, 60)
      .map(s => ({ label: s.name, hint: s.active ? 'active' : (s.tools + ' outils'),
                   run: () => { sendText('/skill ' + s.name); hidePalette(); } }));
    if (head === '/project') return projectList.filter(p => match(p.name)).slice(0, 60)
      .map(p => ({ label: p.name, hint: p.active ? 'active' : '',
                   run: () => { sendText('/project ' + p.name); hidePalette(); } }));
    if (head === '/model') return engineList.filter(e => match(e.alias))
      .map(e => ({ label: e.alias, hint: e.model || '',
                   run: () => { sendText('/model ' + e.alias); hidePalette(); } }));
    return null;
  }

  function renderPalette() {
    if (!el.palette) return;
    const v = (el.input.value || '').toLowerCase();
    if ((v.indexOf('/skill') === 0 && !skillList.length) ||
        (v.indexOf('/project') === 0 && !projectList.length) ||
        (v.indexOf('/model') === 0 && !engineList.length)) call('refreshShared');
    const items = palItems();
    if (!items) { hidePalette(); return; }
    el.palette.innerHTML = '';
    if (!items.length) { el.palette.classList.add('hidden'); return; }
    items.forEach(it => {
      const b = document.createElement('button');
      b.type = 'button'; b.className = 'pal';
      b.innerHTML = '<span class="pal-l">' + esc(it.label) + '</span>' +
        (it.hint ? '<span class="pal-h">' + esc(it.hint) + '</span>' : '');
      b.addEventListener('mousedown', ev => ev.preventDefault());
      b.addEventListener('click', ev => { ev.preventDefault(); it.run(); });
      el.palette.appendChild(b);
    });
    el.palette.classList.remove('hidden');
  }

  function renderModelMenu(items) {
    if (!el.modelMenu) return;
    el.modelMenu.innerHTML = '';
    if (!items.length) { el.modelMenu.innerHTML = '<p class="muted small">Aucune adresse lue.</p>'; return; }
    items.forEach(it => {
      const b = document.createElement('button');
      b.type = 'button'; b.className = 'pal' + (it.active ? ' on' : '');
      b.innerHTML = '<span class="pal-l">' + esc(it.alias || '—') + '</span>' +
        '<span class="pal-h">' + esc(it.model || '') + '</span>';
      b.addEventListener('click', () => { call('takeEngine', it.alias || ''); el.modelMenu.classList.add('hidden'); });
      el.modelMenu.appendChild(b);
    });
  }

  function wire() {
    el.micBtn.addEventListener('click', toggleRec);
    el.orb.addEventListener('click', toggleRec);
    el.recCancel.addEventListener('click', () => { call('cancelVoice'); setRecording(false); });
    el.recSend.addEventListener('click', () => call('stopVoice'));

    el.composer.addEventListener('submit', ev => {
      ev.preventDefault();
      sendText(el.input.value);
    });

    el.input.addEventListener('input', () => { resize(); updateSend(); renderPalette(); });
    el.input.addEventListener('keydown', ev => {
      if (ev.key === 'Enter' && !ev.shiftKey && !ev.isComposing) {
        ev.preventDefault();
        sendText(el.input.value);
      }
    });
    el.input.addEventListener('focus', () => setTimeout(() => scrollBottom(true), 250));
    el.input.addEventListener('blur', () => setTimeout(hidePalette, 180));

    el.attachBtn.addEventListener('click', () => {
      if (S.busy) { toast('Un tour tourne déjà'); return; }
      el.sheet.classList.remove('hidden');
    });
    el.sheetCancel.addEventListener('click', () => el.sheet.classList.add('hidden'));
    el.sheet.addEventListener('click', ev => { if (ev.target === el.sheet) el.sheet.classList.add('hidden'); });
    el.pickGallery.addEventListener('click', () => { el.sheet.classList.add('hidden'); call('pickImage'); });
    el.pickCamera.addEventListener('click', () => { el.sheet.classList.add('hidden'); call('takePhoto'); });

    $$('.suggest button').forEach(b => b.addEventListener('click', () => sendText(b.dataset.say)));

    if (el.residentsBtn) el.residentsBtn.addEventListener('click', () => {
      call('residents');
      toast('Residents : demarrage / arret');
    });
    el.jarvisBtn.addEventListener('click', () => {
      S.jarvis = !S.jarvis;
      call('jarvisMode', S.jarvis);
      paint();
      toast(S.jarvis ? 'Mode Jarvis : la voix enchaîne' : 'Mode Jarvis arrêté');
      if (S.jarvis) setTimeout(() => { if (!S.busy && !S.recording) call('startVoice'); }, 380);
    });
    el.activityBtn.addEventListener('click', () => switchTab('activity'));

    $$('.tab').forEach(t => t.addEventListener('click', () => switchTab(t.dataset.tab)));

    el.saveAddr.addEventListener('click', () => {
      const v = el.addr.value.trim();
      if (!v) { toast('Adresse vide'); return; }
      call('setAddress', v);
      S.pingAsked = true;
      toast('Adresse gardée');
    });
    el.testBtn.addEventListener('click', () => { S.pingAsked = true; toast('Test du pont…'); call('ping'); });
    el.fallback.addEventListener('change', () => call('setFallback', el.fallback.checked));

    el.btnOverlay.addEventListener('click', () => call('overlaySettings'));
    el.btnAppSettings.addEventListener('click', () => call('appSettings'));
    if (el.approvalYes) el.approvalYes.addEventListener('click', () => { toast('Approbation…'); call('approve'); });
    if (el.approvalNo) el.approvalNo.addEventListener('click', () => { call('deny'); });
    if (el.btnUpdate) el.btnUpdate.addEventListener('click', () => { toast('Mise à jour…'); call('updateApp'); });
    S.voiceApproval = localStorage.getItem('voiceApproval') !== '0';
    S.wakeWord = localStorage.getItem('wakeWord') === '1';
    if (el.voiceApproval) {
      el.voiceApproval.checked = S.voiceApproval;
      el.voiceApproval.addEventListener('change', () => { S.voiceApproval = el.voiceApproval.checked; localStorage.setItem('voiceApproval', S.voiceApproval ? '1' : '0'); });
    }
    if (el.wakeWord) {
      el.wakeWord.checked = S.wakeWord;
      el.wakeWord.addEventListener('change', () => { S.wakeWord = el.wakeWord.checked; localStorage.setItem('wakeWord', S.wakeWord ? '1' : '0'); call('setWake', S.wakeWord); });
    }
    if (S.wakeWord) call('setWake', true);

    el.serviceSw.addEventListener('change', () => {
      if (el.serviceSw.checked) call('startService'); else call('stopService');
      setTimeout(() => call('state'), 350);
    });

    el.enginesRefresh.addEventListener('click', () => { call('engines'); toast('Lecture des adresses…'); });
    if (el.banner) el.banner.addEventListener('click', () => {
      if (!el.modelMenu) return;
      if (!el.modelMenu.classList.contains('hidden')) { el.modelMenu.classList.add('hidden'); return; }
      call('engines');
      renderModelMenu(engineList);
      el.modelMenu.classList.remove('hidden');
    });
    el.planRefresh.addEventListener('click', () => { call('plan'); toast('Lecture du plan…'); });

    el.clearBtn.addEventListener('click', () => {
      if (!confirm('Vider l’affichage ? La conversation reste sur le poste (sessions.db).')) return;
      msgs = [];
      renderThread();
      el.empty.classList.remove('hidden');
      toast('Affichage vidé');
    });

    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') { call('state'); call('ping'); syncShared(); }
    });

    window.addEventListener('resize', () => scrollBottom(true));
  }

  /* ------------------------------------------------------------ départ */

  wire();
  renderThread();
  paintToolBand();
  paint();
  updateSend();
  const a = A();
  if (a) {
    a.ready();
    setTimeout(syncShared, 250);
    setInterval(() => {
      if (document.visibilityState === 'visible' && !S.busy && !S.recording) syncShared();
    }, 5000);
  } else {
    el.statusLine.textContent = 'Aperçu hors application';
  }
})();
