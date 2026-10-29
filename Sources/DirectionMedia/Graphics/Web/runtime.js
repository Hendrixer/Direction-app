/*
 * Direction's graphics runtime (design/spec/specs/graphics.md › The contract).
 *
 * Direction injects this before any of the page's own scripts. It gives the page `direction`:
 *   direction.graphic({ duration, words, render })   declare the graphic; render(t, words) draws time t
 *   direction.ease.{linear, in, out, inOut, spring}  easing curves, 0…1 in, 0…1 out
 *   direction.clamp(x, lo = 0, hi = 1), direction.lerp(a, b, t), direction.random(seed)
 *
 * Time is Direction's. Date.now, new Date(), performance.now and requestAnimationFrame only move
 * when Direction asks for the next frame, Math.random is seeded per graphic, and every CSS or Web
 * Animations animation is paused and seeked to the frame's time. The same graphic and words
 * therefore draw the same pixels every time. Timers (setTimeout, setInterval) keep real time:
 * don't animate with them.
 */
(() => {
  'use strict';
  const setup = window.__directionSetup || {};
  const realNow = performance.now.bind(performance);

  // MARK: The clock

  let nowMs = 0;
  // A fixed wall clock, so a graphic that shows a date shows the same one on every render.
  const EPOCH = Date.UTC(2026, 0, 1);
  const RealDate = Date;
  function VirtualDate(...args) {
    if (!new.target) return new RealDate(EPOCH + nowMs).toString();
    return args.length ? new RealDate(...args) : new RealDate(EPOCH + nowMs);
  }
  VirtualDate.prototype = RealDate.prototype;
  VirtualDate.now = () => EPOCH + nowMs;
  VirtualDate.parse = RealDate.parse;
  VirtualDate.UTC = RealDate.UTC;
  Object.defineProperty(VirtualDate, 'name', { value: 'Date' });
  window.Date = VirtualDate;
  Object.defineProperty(performance, 'now', { value: () => nowMs, configurable: true, writable: true });

  // requestAnimationFrame runs once per frame Direction asks for, with that frame's time.
  let callbacks = new Map(), nextCallback = 1;
  window.requestAnimationFrame = (callback) => { const id = nextCallback++; callbacks.set(id, callback); return id; };
  window.cancelAnimationFrame = (id) => { callbacks.delete(id); };

  // A small, fast seeded generator (mulberry32). Math.random uses the graphic's own seed.
  const seeded = (seed) => {
    let a = (seed >>> 0) || 1;
    return () => {
      a = (a + 0x6d2b79f5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  };
  Math.random = seeded(setup.seed || 1);

  // MARK: What went wrong

  const errors = [], consoleErrors = [], internet = [];
  const offline = (url) => /^(https?|wss?|ftp):/i.test(String(url || '')) || String(url || '').startsWith('//');
  const noteInternet = (url) => { const u = String(url); if (!internet.includes(u)) internet.push(u); };
  const describe = (e) => {
    if (e && typeof e === 'object') {
      const source = String(e.sourceURL || '').replace(/^direction:\/\/graphic\//, '');
      return { message: String(e.message || e), source, line: e.line || 0, column: e.column || 0 };
    }
    return { message: String(e), source: '', line: 0, column: 0 };
  };
  window.addEventListener('error', (event) => {
    const target = event.target;
    if (target && target !== window && target.nodeType === 1) {
      // A file that didn't load: an image, a script, a stylesheet.
      const url = target.currentSrc || target.src || target.href || '';
      if (offline(url)) noteInternet(url); else consoleErrors.push(`Couldn't load ${String(url).replace(/^direction:\/\/graphic\//, '') || target.tagName.toLowerCase()}`);
      return;
    }
    errors.push({ message: event.message, source: String(event.filename || '').replace(/^direction:\/\/graphic\//, ''), line: event.lineno || 0, column: event.colno || 0 });
  }, true);
  window.addEventListener('unhandledrejection', (event) => { errors.push(describe(event.reason)); });
  document.addEventListener('securitypolicyviolation', (event) => { if (event.blockedURI && event.blockedURI !== 'inline' && event.blockedURI !== 'eval') noteInternet(event.blockedURI); });
  const consoleError = console.error.bind(console);
  console.error = (...args) => { consoleErrors.push(args.map((a) => (a && a.stack) ? `${a.message}` : String(a)).join(' ')); consoleError(...args); };

  // Network requests are blocked twice over (a content rule list and the page's security policy).
  // These wrappers only make the URL easy to report.
  const realFetch = window.fetch && window.fetch.bind(window);
  if (realFetch) window.fetch = (input, init) => { const url = typeof input === 'string' ? input : (input && input.url); if (offline(url)) noteInternet(url); return realFetch(input, init); };
  const RealXHR = window.XMLHttpRequest;
  if (RealXHR) { const open = RealXHR.prototype.open; RealXHR.prototype.open = function (method, url, ...rest) { if (offline(url)) noteInternet(url); return open.call(this, method, url, ...rest); }; }
  for (const name of ['WebSocket', 'EventSource']) {
    const Real = window[name];
    if (!Real) continue;
    window[name] = function (url, ...rest) { noteInternet(url); return new Real(url, ...rest); };
    window[name].prototype = Real.prototype;
  }
  if (navigator.sendBeacon) navigator.sendBeacon = (url) => { noteInternet(url); return false; };

  // MARK: Fonts

  // Archivo is bundled (weights 100–900, widths 62–125%). System fonts and fonts in the folder work too.
  const fonts = document.createElement('style');
  fonts.textContent = "@font-face { font-family: 'Archivo'; src: url('direction:fonts/Archivo-Variable.ttf') format('truetype'); font-weight: 100 900; font-stretch: 62% 125%; }";
  (document.head || document.documentElement).appendChild(fonts);

  // MARK: The contract

  let graphic = null, declared = {}, words = Object.freeze({});
  let ready, isReady = new Promise((resolve) => { ready = resolve; });
  const overrides = Object.assign({}, setup.words || {});

  const resolveWords = () => {
    const out = {};
    for (const key of Object.keys(declared)) out[key] = Object.prototype.hasOwnProperty.call(overrides, key) ? String(overrides[key]) : declared[key].text;
    words = Object.freeze(out);
  };

  const ease = {
    linear: (x) => x,
    in: (x) => x * x * x,
    out: (x) => 1 - Math.pow(1 - x, 3),
    inOut: (x) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2),
    // A gentle spring: about 9% overshoot, settled exactly at 1.
    spring: (x) => (x <= 0 ? 0 : x >= 1 ? 1 : 1 - Math.exp(-6 * x) * Math.cos(x * Math.PI * 2.5)),
  };

  window.direction = Object.freeze({
    graphic(config) {
      if (graphic) throw new Error('direction.graphic() was called twice. A page is one graphic.');
      if (!config || typeof config.render !== 'function') throw new Error('direction.graphic() needs a render(t, words) function.');
      const duration = Number(config.duration);
      if (!(duration > 0)) throw new Error('direction.graphic() needs a duration in seconds.');
      declared = {};
      for (const [key, field] of Object.entries(config.words || {})) {
        const f = (field && typeof field === 'object') ? field : { text: field };
        declared[key] = { label: String(f.label ?? key), text: String(f.text ?? ''), max: f.max == null ? null : Number(f.max) };
      }
      graphic = { duration, render: config.render };
      resolveWords();
      ready();
    },
    ease: Object.freeze(ease),
    clamp: (x, lo = 0, hi = 1) => Math.min(hi, Math.max(lo, x)),
    lerp: (a, b, t) => a + (b - a) * t,
    random: (seed) => seeded(seed),
    get words() { return words; },
    get width() { return setup.width || innerWidth; },
    get height() { return setup.height || innerHeight; },
  });

  // MARK: Frames (called by Direction, never by the page)

  // Animations are seeked relative to when they first appeared: 0 for anything that runs from the
  // start, the frame's time for a transition a render started.
  const births = new WeakMap();
  const seekAnimations = (t) => {
    if (!document.getAnimations) return;
    for (const animation of document.getAnimations()) {
      if (!births.has(animation)) births.set(animation, t);
      try { animation.pause(); animation.currentTime = Math.max(0, (t - births.get(animation)) * 1000); } catch (_) {}
    }
  };

  const frame = async (t) => {
    const started = realNow();
    nowMs = t * 1000;
    const due = [...callbacks.values()];
    callbacks = new Map();
    for (const callback of due) {
      try { callback(nowMs); } catch (e) { errors.push(describe(e)); }
    }
    try { await graphic.render(t, words); } catch (e) { errors.push(describe(e)); }
    seekAnimations(t);
    if (document.fonts) await document.fonts.ready;
    void document.documentElement.offsetHeight;
    return realNow() - started;
  };

  // MARK: Checks (graphics.md › Tools: overflow, title safe, size, contrast)

  const probe = document.createElement('canvas').getContext('2d', { willReadFrequently: true });
  const rgba = (css) => {
    if (!css || css === 'transparent') return [0, 0, 0, 0];
    probe.clearRect(0, 0, 1, 1);
    probe.fillStyle = '#000'; probe.fillStyle = css;
    probe.fillRect(0, 0, 1, 1);
    const d = probe.getImageData(0, 0, 1, 1).data;
    return [d[0], d[1], d[2], d[3] / 255];
  };
  const opacityOf = (el) => { let o = 1; for (let e = el; e && e.nodeType === 1; e = e.parentElement) o *= Number(getComputedStyle(e).opacity); return o; };
  const scaleOf = (el) => {
    if (el instanceof SVGElement && el.getScreenCTM) { const m = el.getScreenCTM(); return m ? Math.hypot(m.a, m.b) : 1; }
    const r = el.getBoundingClientRect();
    return el.offsetHeight > 0 ? r.height / el.offsetHeight : 1;
  };
  // The colors right behind a piece of text, nearest first, until one is opaque. null when a gradient
  // or image sits behind it, which the check can't measure.
  const backing = (el) => {
    const layers = [];
    for (let e = el; e && e.nodeType === 1; e = e.parentElement) {
      const s = getComputedStyle(e);
      if (s.backgroundImage && s.backgroundImage !== 'none') return null;
      const c = rgba(s.backgroundColor);
      if (c[3] > 0) { layers.push([c[0], c[1], c[2], c[3] * Number(s.opacity)]); if (c[3] >= 1 && Number(s.opacity) >= 1) break; }
    }
    return layers;
  };
  const wordFor = (el, text) => {
    const marked = el.closest && el.closest('[data-word]');
    if (marked) return marked.getAttribute('data-word');
    const lower = text.toLowerCase();
    for (const [key, value] of Object.entries(words)) if (value.trim() === text) return key;
    for (const [key, value] of Object.entries(words)) if (value.toLowerCase().includes(lower)) return key;
    return null;
  };
  // Words overflow when they don't fit their own box (the nearest block around them): too wide to
  // wrap, or more lines than its height holds. A little vertical slack allows tight leading.
  const ownBoxOverflows = (el) => {
    for (let e = el; e && e !== document.body && e !== document.documentElement; e = e.parentElement) {
      if (!(e instanceof HTMLElement)) continue;
      const s = getComputedStyle(e);
      if (s.display === 'inline' || s.display === 'contents') continue;
      return e.scrollWidth > e.clientWidth + 1 || e.scrollHeight > e.clientHeight + Math.max(2, parseFloat(s.fontSize) * 0.3);
    }
    return false;
  };
  // What clips the text: ancestors with overflow other than visible. A mask a word slides out of,
  // or a credits window, hides what's outside it; only the part that shows is checked.
  const clipOf = (el) => {
    let c = { left: -Infinity, top: -Infinity, right: Infinity, bottom: Infinity };
    for (let e = el.parentElement; e && e !== document.documentElement; e = e.parentElement) {
      const s = getComputedStyle(e);
      if (s.overflowX === 'visible' && s.overflowY === 'visible' && s.clipPath === 'none') continue;
      const r = e.getBoundingClientRect();
      c = { left: Math.max(c.left, r.left), top: Math.max(c.top, r.top), right: Math.min(c.right, r.right), bottom: Math.min(c.bottom, r.bottom) };
    }
    return c;
  };
  const intersect = (a, b) => ({ left: Math.max(a.left, b.left), top: Math.max(a.top, b.top), right: Math.min(a.right, b.right), bottom: Math.min(a.bottom, b.bottom) });

  const inspect = () => {
    const W = innerWidth, H = innerHeight, texts = [];
    const root = document.body || document.documentElement;
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const text = node.nodeValue.replace(/\s+/g, ' ').trim();
      const el = node.parentElement;
      if (!text || !el || el.closest('script,style,noscript,template,title,defs')) continue;
      const style = getComputedStyle(el);
      if (style.visibility !== 'visible' || style.display === 'none') continue;
      const opacity = opacityOf(el);
      if (opacity < 0.05) continue;
      const range = document.createRange();
      range.selectNodeContents(node);
      const rects = [...range.getClientRects()].filter((r) => r.width > 0.5 && r.height > 0.5);
      if (!rects.length) continue;
      const box = { left: Math.min(...rects.map((r) => r.left)), top: Math.min(...rects.map((r) => r.top)), right: Math.max(...rects.map((r) => r.right)), bottom: Math.max(...rects.map((r) => r.bottom)) };
      const shown = intersect(box, clipOf(el));
      if (shown.right - shown.left < 0.5 || shown.bottom - shown.top < 0.5) continue;
      const onPicture = intersect(shown, { left: 0, top: 0, right: W, bottom: H });
      if (onPicture.right - onPicture.left < 0.5 || onPicture.bottom - onPicture.top < 0.5) continue;
      const offPicture = shown.left < -0.5 || shown.top < -0.5 || shown.right > W + 0.5 || shown.bottom > H + 0.5;
      const color = rgba(style.color);
      texts.push({
        text, word: wordFor(el, text),
        x: onPicture.left, y: onPicture.top, width: onPicture.right - onPicture.left, height: onPicture.bottom - onPicture.top,
        fontSize: parseFloat(style.fontSize) * scaleOf(el),
        color: [color[0], color[1], color[2], color[3] * opacity],
        backing: backing(el),
        overflow: offPicture ? 'picture' : ownBoxOverflows(el) ? 'box' : null,
      });
    }
    return { width: W, height: H, texts };
  };

  const report = () => ({ errors: errors.slice(), consoleErrors: consoleErrors.slice(), internet: internet.slice() });

  window.__direction = Object.freeze({
    ready: () => isReady.then(() => ({ duration: graphic.duration, words: declared })),
    setWords: (values) => { for (const k of Object.keys(overrides)) delete overrides[k]; Object.assign(overrides, values || {}); resolveWords(); },
    frame, inspect, report,
  });
})();
