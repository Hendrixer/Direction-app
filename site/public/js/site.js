// Direction marketing page: nav, title-card timecode, the premise read, the five rooms, and the notes player.
(() => {
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
  const seen = (el, fn, opts) => { const io = new IntersectionObserver(es => es.forEach(e => fn(e.isIntersecting, e)), opts); io.observe(el); return io; };

  /* ---------- Nav ---------- */
  const nav = $('#nav');
  let ticking = false;
  addEventListener('scroll', () => {
    if (ticking) return; ticking = true;
    requestAnimationFrame(() => { nav.classList.toggle('scrolled', scrollY > 24); readPremise(); readSteps(); ticking = false; });
  }, { passive: true });
  nav.classList.toggle('scrolled', scrollY > 24);

  /* ---------- Title card timecode: runs at 24 fps while it's on screen ---------- */
  const tc = $('#tc');
  const fmt = fr => [Math.floor(fr / 86400), Math.floor(fr / 1440) % 60, Math.floor(fr / 24) % 60, fr % 24].map(n => String(n).padStart(2, '0')).join(':');
  let tcRun = false, tcStart = 0, tcLast = -1;
  const startFrame = (60 + 48) * 24 + 12;
  const tick = now => {
    if (!tcRun) return;
    const fr = startFrame + Math.floor((now - tcStart) / (1000 / 24));
    if (fr !== tcLast) { tc.textContent = fmt(fr); tcLast = fr; }
    requestAnimationFrame(tick);
  };
  if (!reduce) seen($('.hero'), on => {
    if (on && !tcRun) { tcRun = true; tcStart = performance.now() - Math.max(0, tcLast - startFrame) * (1000 / 24); requestAnimationFrame(tick); }
    if (!on) tcRun = false;
  });

  /* ---------- The premise reads in as you scroll ---------- */
  const prem = $('#premise');
  const words = [];
  for (const node of [...prem.childNodes]) {
    const isQ = node.nodeType === 1 && node.tagName === 'Q';
    const text = isQ ? `“${node.textContent}”` : node.textContent;
    const frag = document.createDocumentFragment();
    for (const part of text.split(/(\s+)/)) {
      if (!part) continue;
      if (/^\s+$/.test(part)) { frag.append(part); continue; }
      const w = document.createElement('span'); w.className = isQ ? 'w q' : 'w'; w.textContent = part; frag.append(w); words.push(w);
    }
    node.replaceWith(frag);
  }
  let lit = -1;
  function readPremise() {
    if (reduce) { if (lit < 0) { words.forEach(w => w.classList.add('on')); lit = words.length; } return; }
    const r = prem.getBoundingClientRect();
    const p = clamp((innerHeight * .82 - r.top) / (r.height + innerHeight * .3), 0, 1);
    const n = Math.round(p * words.length);
    if (n === lit) return;
    words.forEach((w, i) => w.classList.toggle('on', i < n)); lit = n;
  }
  readPremise();

  /* ---------- Reveal ---------- */
  const rv = new IntersectionObserver(es => es.forEach(e => { if (e.isIntersecting) { e.target.classList.add('in'); rv.unobserve(e.target); } }), { rootMargin: '0px 0px -8% 0px' });
  $$('.rv').forEach(el => rv.observe(el));

  /* ---------- The five rooms ---------- */
  const win = $('#win'), steps = $$('.step'), screens = $('#screens'), scrs = $$('.scr', screens);
  const desk = matchMedia('(min-width: 1000px)');
  const fit = new ResizeObserver(es => es.forEach(e => e.target.firstElementChild.style.setProperty('--k', e.contentRect.width / 760)));
  fit.observe($('.win-body', win));
  const rooms = {
    1: { crumb: 'Brief', room: null, agent: '', gem: 'gem grey', text: 'Waiting for footage' },
    2: { crumb: 'Dailies', room: 'dailies', agent: 'working', gem: 'gem', text: 'Logging 42 of 64' },
    3: { crumb: 'Cut 1', room: 'cut', agent: '', gem: 'gem', text: 'Cut 1 ready' },
    4: { crumb: 'Cut 1', room: 'cut', agent: 'ion', gem: 'gem ion', text: 'Reading back' },
    5: { crumb: 'Cut 6', room: 'finish', agent: 'working', gem: 'gem', text: 'Delivering 3 files' },
  };
  const agent = $('#agent');
  let step = 1;

  function place() {
    if (desk.matches) {
      scrs.forEach(s => { screens.appendChild(s); s.classList.toggle('on', +s.dataset.s === step); });
    } else {
      scrs.forEach(s => {
        const slot = $('.slot', steps[+s.dataset.s - 1]);
        let body = $('.win-body', slot);
        if (!body) { body = document.createElement('div'); body.className = 'win-body'; body.innerHTML = '<div class="screens"></div>'; slot.appendChild(body); fit.observe(body); }
        body.firstElementChild.appendChild(s); s.classList.add('on');
      });
    }
  }
  desk.addEventListener('change', place);
  place();

  function setStep(n) {
    if (n === step && win.dataset.ready) return;
    win.dataset.ready = 1;
    step = n; win.dataset.step = n;
    steps.forEach(s => s.classList.toggle('on', +s.dataset.step === n));
    if (desk.matches) scrs.forEach(s => s.classList.toggle('on', +s.dataset.s === n));
    const r = rooms[n];
    $('#crumb-cut').textContent = r.crumb;
    $$('.rooms span', win).forEach(s => s.classList.toggle('on', s.dataset.room === r.room));
    agent.className = 'agent ' + r.agent;
    agent.firstElementChild.className = r.gem;
    agent.children[1].textContent = r.text;
    begin(n);
  }

  // Each room plays its moment when it comes up.
  const shapes = [['As shot', 208, 117, 'As shot'], ['16:9', 208, 117, '16 : 9'], ['9:16', 88, 156, '9 : 16'], ['1:1', 138, 138, '1 : 1'], ['4:5', 120, 150, '4 : 5']];
  let shapeTimer = 0, shapeAt = 1, typeTimer = 0;
  function showShape(i) {
    const [, w, h, label] = shapes[i];
    const f = $('#shape'); f.style.width = w + 'px'; f.style.height = h + 'px';
    $('#shape-tc').textContent = label;
    $$('#seg span').forEach((s, j) => s.classList.toggle('on', j === i));
  }
  function begin(n) {
    clearInterval(shapeTimer); clearTimeout(typeTimer);
    if (n === 1 && !reduce) shapeTimer = setInterval(() => { shapeAt = shapeAt % 4 + 1; showShape(shapeAt); }, 1900);
    if (n === 3) typeNote();
  }
  const note = "Let her be small here. She's alone up there.";
  const typed = $('#typed span');
  function typeNote() {
    if (reduce) { typed.textContent = note; return; }
    let i = 0; typed.textContent = '';
    const next = () => { typed.textContent = note.slice(0, ++i); if (i < note.length) typeTimer = setTimeout(next, 38 + Math.random() * 60); };
    typeTimer = setTimeout(next, 600);
  }
  // The room on screen is the last step whose top has passed a little below the middle of the window.
  function readSteps() {
    const mid = innerHeight * .58;
    let n = 1;
    for (const s of steps) if (s.getBoundingClientRect().top < mid) n = +s.dataset.step;
    setStep(n);
  }
  readSteps();

  // Keep the sticky window centred whatever its height.
  const stage = $('.stage');
  new ResizeObserver(() => stage.style.setProperty('--stage-h', stage.offsetHeight + 'px')).observe(stage);

  /* ---------- Notes, answered ---------- */
  const player = $('#player'), noteBtns = $$('.note', player);
  const layer = Object.fromEntries($$('.n-layer', player).map(l => [l.dataset.l, l]));
  const zoomG = $('.zoom', layer.garage), zoomR = $('.zoom', layer.ridge);
  const region = $('.n-pic .region', player), ab = $('.n-ab', player), audio = $('.n-audio', player);
  const chip = $('#n-chip'), ntc = $('#n-tc'), sc1 = $('.n-strip [data-sc="1"]', player);
  const dur = { 1: 6200, 2: 7600, 3: 6800, 4: 6400, 5: 5600 };
  const leak = $('.n-leak', player);
  let cur = 1, auto = !reduce, inView = false, timers = [], cycle = 0;

  // Frame a picture on a point at a scale, never showing past its edges.
  function frame(el, fx, fy, s) {
    const tx = clamp(50 - fx * 100 * s, (1 - s) * 100, 0), ty = clamp(50 - fy * 100 * s, (1 - s) * 100, 0);
    el.style.transform = s === 1 ? 'none' : `translate(${tx}%, ${ty}%) scale(${s})`;
  }
  const later = (ms, fn) => timers.push(setTimeout(fn, reduce ? 0 : ms));
  const show = name => Object.entries(layer).forEach(([k, l]) => l.classList.toggle('on', k === name));
  const answer = text => { chip.textContent = text; chip.classList.add('show'); };

  function play(n) {
    timers.forEach(clearTimeout); timers = []; clearTimeout(cycle);
    cur = n;
    noteBtns.forEach(b => { const on = +b.dataset.n === n; b.classList.toggle('on', on); b.setAttribute('aria-pressed', on); b.classList.remove('timing'); });
    region.classList.remove('show'); ab.classList.remove('show'); audio.classList.remove('show', 'duck'); chip.classList.remove('show');
    if (n !== 1) sc1.style.flexGrow = .55;

    if (n === 1) {
      show('street'); sc1.style.flexGrow = .8; ntc.textContent = '00:00:04';
      later(1500, () => { show('face'); sc1.style.flexGrow = .55; ntc.textContent = '00:00:09'; answer('−4.2 s'); });
    } else if (n === 2) {
      show('garage'); frame(zoomG, .5, .5, 1); ntc.textContent = '00:00:41'; ab.classList.add('show');
      const pick = which => $$('span', ab).forEach(s => s.classList.toggle('on', s.dataset.ab === which));
      pick('a');
      later(500, () => { frame(zoomG, .45, .8, 1.45); answer('A / B'); });
      later(3600, () => { pick('b'); frame(zoomG, .25, .42, 1.7); });
    } else if (n === 3) {
      show('ridge'); frame(zoomR, .5, .5, 1); ntc.textContent = '00:01:48';
      later(300, () => region.classList.add('show'));
      later(1900, () => { region.classList.remove('show'); frame(zoomR, .625, .8, 1.6); answer('crop 1.6×'); });
    } else if (n === 4) {
      show('ridge'); frame(zoomR, .625, .8, 1.6); ntc.textContent = '00:01:52'; audio.classList.add('show');
      later(900, () => { audio.classList.add('duck'); answer('−6 dB'); });
    } else if (n === 5) {
      show('garage'); frame(zoomG, .5, .5, 1); ntc.textContent = '00:01:31';
      later(900, () => { leak.classList.toggle('go', false); void leak.offsetWidth; leak.classList.add('go'); });
      later(1450, () => { show('ridge'); frame(zoomR, .5, .5, 1); ntc.textContent = '00:01:32'; answer('Light leak · 14 fr'); });
    }
    if (auto && inView) {
      const b = noteBtns[n - 1]; b.style.setProperty('--dur', dur[n] + 'ms'); void b.offsetWidth; b.classList.add('timing');
      cycle = setTimeout(() => play(n % noteBtns.length + 1), dur[n]);
    }
  }
  noteBtns.forEach(b => b.addEventListener('click', () => { auto = false; play(+b.dataset.n); }));
  seen(player, on => {
    inView = on;
    if (on) play(cur);
    else { timers.forEach(clearTimeout); clearTimeout(cycle); noteBtns.forEach(b => b.classList.remove('timing')); }
  }, { threshold: .35 });

  /* ---------- Learn: a style studied, a move learned ---------- */
  const study = $('#study');
  if (study) seen(study, on => {
    if (!on || study.classList.contains('go')) return;
    study.classList.add('go');
    const st = $('.st', study);
    setTimeout(() => { st.textContent = 'Studied'; st.className = 'chip ok st'; }, reduce ? 0 : 900);
  }, { threshold: .3 });

  const flash = $('#flash');
  if (flash) {
    const cells = $('.cells', flash);
    for (let i = 0; i < 40; i++) {
      const c = document.createElement('i'), x = i % 8, y = Math.floor(i / 8);
      c.style.setProperty('--d', (Math.abs(x - 3.5) * .045 + Math.abs(y - 2) * .05 + Math.random() * .08).toFixed(3) + 's');
      cells.append(c);
    }
    let flashTimer = 0;
    const once = () => {
      flash.classList.toggle('go', false); void flash.offsetWidth; flash.classList.add('go');
      setTimeout(() => flash.classList.toggle('b'), 260);
    };
    if (!reduce) seen(flash, on => { clearInterval(flashTimer); if (on) { once(); flashTimer = setInterval(once, 2600); } });
  }

  // Waveforms for the sync tile: the same sound heard by a camera and a recorder.
  (function syncWaves() {
    const ns = 'http://www.w3.org/2000/svg';
    let seed = 3; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
    const hs = []; for (let x = 0; x < 200; x += 3) hs.push(3 + 18 * Math.abs(Math.sin(x / 11)) * (.35 + rnd() * .65));
    for (const g of $$('.tv-sync g')) hs.forEach((h, i) => {
      const r = document.createElementNS(ns, 'rect');
      r.setAttribute('x', i * 3); r.setAttribute('y', 12 - h / 2); r.setAttribute('width', 1.8); r.setAttribute('height', h); r.setAttribute('rx', .9);
      g.append(r);
    });
  })();

  // Waveforms for the sound note: her line in the middle, music the whole way, the middle of it can duck.
  (function waves() {
    const ns = 'http://www.w3.org/2000/svg';
    let seed = 7; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
    const bar = (g, x, h) => { const r = document.createElementNS(ns, 'rect'); r.setAttribute('x', x); r.setAttribute('y', 13 - h / 2); r.setAttribute('width', 2); r.setAttribute('height', h); r.setAttribute('rx', 1); g.append(r); };
    const d = $('#wave-d'), m = $('#wave-m'), duck = document.createElementNS(ns, 'g'); duck.setAttribute('class', 'duckable');
    let env = .5;
    for (let x = 0; x < 400; x += 4) {
      env = clamp(env + (rnd() - .5) * .25, .35, .9);
      const target = x >= 132 && x < 276 ? duck : m;
      bar(target, x, 4 + env * 16 * (.6 + rnd() * .4));
      if (x >= 140 && x < 270) bar(d, x, 3 + 20 * Math.abs(Math.sin(x / 9)) * (.4 + rnd() * .6));
    }
    m.append(duck);
  })();
})();
