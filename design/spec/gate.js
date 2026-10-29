// Gate frame helper. Include as the first child of <body>:  <script src="../gate.js"></script>
// 1. Injects the icon sprite. Use icons as <svg class="ico"><use href="#i-name"/></svg>.
//    In the app, map each id to the SF Symbol listed in specs/icons.md.
// 2. With ?layout in the URL, writes a JSON list of every [data-c] element's box
//    (x, y, w, h in points, relative to the frame) into <pre id="layout">. render.sh saves it.
(function () {
  const s = 'stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" fill="none"';
  const icons = {
    play: '<path d="M5 3.2v9.6c0 .5.5.8.9.5l7.4-4.8c.4-.3.4-.8 0-1L5.9 2.7c-.4-.3-.9 0-.9.5Z" fill="currentColor"/>',
    pause: '<rect x="4" y="3" width="2.6" height="10" rx="1" fill="currentColor"/><rect x="9.4" y="3" width="2.6" height="10" rx="1" fill="currentColor"/>',
    back: `<path d="M8 4 4 8l4 4M12 4 8 8l4 4" ${s}/>`,
    fwd: `<path d="m8 4 4 4-4 4M4 4l4 4-4 4" ${s}/>`,
    plus: `<path d="M8 3v10M3 8h10" ${s}/>`,
    check: `<path d="m3.5 8.4 2.9 2.9 6.1-6.6" ${s}/>`,
    x: `<path d="m4 4 8 8M12 4l-8 8" ${s}/>`,
    lock: '<rect x="3.5" y="7" width="9" height="6.5" rx="1.6" fill="currentColor"/><path d="M5.5 7V5.2a2.5 2.5 0 0 1 5 0V7" stroke="currentColor" stroke-width="1.5" fill="none"/>',
    unlock: `<rect x="3.5" y="7" width="9" height="6.5" rx="1.6" ${s}/><path d="M5.5 7V5.2a2.5 2.5 0 0 1 4.8-1" ${s}/>`,
    region: `<path d="M2.5 5V3.5a1 1 0 0 1 1-1H5M11 2.5h1.5a1 1 0 0 1 1 1V5M13.5 11v1.5a1 1 0 0 1-1 1H11M5 13.5H3.5a1 1 0 0 1-1-1V11" ${s}/>`,
    range: `<path d="M3 3v10M13 3v10M5.5 8h5M7 6.5 5.5 8 7 9.5M9 6.5l1.5 1.5L9 9.5" ${s}/>`,
    turn: `<path d="M3 8h9M8.5 4.5 12 8l-3.5 3.5" ${s}/>`,
    exit: `<path d="M6 3H3.5a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1H6M10 5l3 3-3 3M13 8H6.5" ${s}/>`,
    circle: '<path d="M30 5.5C25 1.8 12 1.6 6.2 6.6 1 11.2 2.6 21 9.5 24.6c7.6 4 19.6 2.6 24-3.6 3.6-5.1 1.4-11.8-5.1-14.6" fill="none" stroke-width="1.8" stroke-linecap="round"/>',
    script: `<path d="M4 2.5h6l2.5 2.5v8.5H4z" ${s}/><path d="M6 7h4.5M6 9.5h4.5M6 12h2.5" ${s}/>`,
    strike: `<path d="M3 8h10M10.5 4.5c-.5-.8-1.4-1.2-2.6-1.2-1.6 0-2.6.8-2.6 2 0 .9.6 1.4 1.4 1.7M5.5 11c.4 1 1.4 1.7 2.8 1.7 1.7 0 2.7-.9 2.7-2.1 0-.3 0-.6-.2-.8" ${s}/>`,
    hold: `<path d="M5 2.5H3.5v11H5M11 2.5h1.5v11H11" ${s}/>`,
    move: `<path d="M8 2.5v11M5.5 5 8 2.5 10.5 5M5.5 11 8 13.5l2.5-2.5" ${s}/>`,
    quote: '<path d="M3 9.5c0-2.6 1.3-4.4 3.4-5l.4.9C5.5 6 4.9 7 4.9 8H6.5v4H3zM9 9.5c0-2.6 1.3-4.4 3.4-5l.4.9c-1.3.6-1.9 1.6-1.9 2.6h1.6v4H9z" fill="currentColor"/>',
    share: `<path d="M8 2.5v8M5 5.5l3-3 3 3M3.5 9v3.5a1 1 0 0 0 1 1h7a1 1 0 0 0 1-1V9" ${s}/>`,
    link: `<path d="M7 9a2.5 2.5 0 0 0 3.5 0l2-2A2.5 2.5 0 0 0 9 3.5l-.7.7M9 7a2.5 2.5 0 0 0-3.5 0l-2 2A2.5 2.5 0 0 0 7 12.5l.7-.7" ${s}/>`,
    gear: `<circle cx="8" cy="8" r="2.2" ${s}/><path d="M8 1.8v1.8M8 12.4v1.8M1.8 8h1.8M12.4 8h1.8M3.6 3.6l1.3 1.3M11.1 11.1l1.3 1.3M3.6 12.4l1.3-1.3M11.1 4.9l1.3-1.3" ${s}/>`,
    search: `<circle cx="7" cy="7" r="4.2" ${s}/><path d="m10.2 10.2 3.3 3.3" ${s}/>`,
    down: `<path d="m4 6 4 4 4-4" ${s}/>`,
    right: `<path d="m6 4 4 4-4 4" ${s}/>`,
    left: `<path d="m10 4-4 4 4 4" ${s}/>`,
    more: '<circle cx="3.5" cy="8" r="1.2" fill="currentColor"/><circle cx="8" cy="8" r="1.2" fill="currentColor"/><circle cx="12.5" cy="8" r="1.2" fill="currentColor"/>',
    film: `<rect x="2.5" y="3" width="11" height="10" rx="1.5" ${s}/><path d="M5 3v10M11 3v10M2.5 6h2.5M2.5 10h2.5M11 6h2.5M11 10h2.5" ${s}/>`,
    folder: `<path d="M2.5 4.5a1 1 0 0 1 1-1h3l1.5 1.5h4.5a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1h-9a1 1 0 0 1-1-1z" ${s}/>`,
    import: `<path d="M8 2.5v7.5M5 7l3 3 3-3M3.5 10v2.5a1 1 0 0 0 1 1h7a1 1 0 0 0 1-1V10" ${s}/>`,
    clock: `<circle cx="8" cy="8" r="5.5" ${s}/><path d="M8 5v3.2l2 1.3" ${s}/>`,
    ask: `<circle cx="8" cy="8" r="5.5" ${s}/><path d="M6.4 6.3a1.7 1.7 0 0 1 3.2.6c0 1.2-1.6 1.4-1.6 2.4" ${s}/><circle cx="8" cy="11.2" r=".8" fill="currentColor"/>`,
    warn: `<path d="M8 2.8 14 13H2z" ${s}/><path d="M8 6.5v3" ${s}/><circle cx="8" cy="11.2" r=".8" fill="currentColor"/>`,
    revert: `<path d="M4 6h6a3 3 0 0 1 0 6H7M6 3.5 3.5 6 6 8.5" ${s}/>`,
    reply: `<path d="M6.5 4 3 7.5 6.5 11M3 7.5h6.5a3.5 3.5 0 0 1 3.5 3.5V12" ${s}/>`,
    eye: `<path d="M1.8 8S4 3.8 8 3.8 14.2 8 14.2 8 12 12.2 8 12.2 1.8 8 1.8 8z" ${s}/><circle cx="8" cy="8" r="1.8" ${s}/>`,
    person: `<circle cx="8" cy="5.5" r="2.5" ${s}/><path d="M3 13.5c.6-2.4 2.6-3.8 5-3.8s4.4 1.4 5 3.8" ${s}/>`,
    people: `<circle cx="6" cy="5.8" r="2.2" ${s}/><path d="M1.8 13c.5-2 2.1-3.3 4.2-3.3s3.7 1.3 4.2 3.3M10.5 3.8a2.2 2.2 0 0 1 0 4.2M12 9.9c1.1.5 1.9 1.6 2.2 3.1" ${s}/>`,
    bell: `<path d="M4 11V7.5a4 4 0 0 1 8 0V11l1 1.5H3zM6.5 14h3" ${s}/>`,
    keyboard: `<rect x="1.8" y="4" width="12.4" height="8" rx="1.5" ${s}/><path d="M4.5 6.5h.01M7 6.5h.01M9.5 6.5h.01M12 6.5h.01M5 9.5h6" ${s}/>`,
    disk: `<rect x="2.5" y="3" width="11" height="10" rx="1.5" ${s}/><path d="M2.5 9.5h11M11 11.3h.01" ${s}/>`,
    wave: `<path d="M2 8h1M4.5 5.5v5M7 3v10M9.5 5v6M12 6.5v3M14 8h.01" ${s}/>`,
    speaker: `<path d="M3 6.2h2.3L8.5 3.5v9L5.3 9.8H3z" ${s}/><path d="M10.8 5.8a3 3 0 0 1 0 4.4M12.6 4.2a5.4 5.4 0 0 1 0 7.6" ${s}/>`,
    cc: `<rect x="2" y="3.5" width="12" height="9" rx="1.8" ${s}/><path d="M7 6.6a1.8 1.8 0 1 0 0 2.8M11.2 6.6a1.8 1.8 0 1 0 0 2.8" ${s}/>`,
    color: `<circle cx="8" cy="8" r="5.5" ${s}/><path d="M8 2.5v11" ${s}/><path d="M8 2.5a5.5 5.5 0 0 0 0 11z" fill="currentColor"/>`,
    titles: `<path d="M3.5 4.5V3h9v1.5M8 3v10M6 13h4" ${s}/>`,
    export: `<path d="M8 10V2.5M5 5.5l3-3 3 3M3.5 9v3.5a1 1 0 0 0 1 1h7a1 1 0 0 0 1-1V9" ${s}/>`,
    full: `<path d="M2.5 6V3.5a1 1 0 0 1 1-1H6M10 2.5h2.5a1 1 0 0 1 1 1V6M13.5 10v2.5a1 1 0 0 1-1 1H10M6 13.5H3.5a1 1 0 0 1-1-1V10" ${s}/>`,
    grip: '<circle cx="6" cy="4" r="1" fill="currentColor"/><circle cx="10" cy="4" r="1" fill="currentColor"/><circle cx="6" cy="8" r="1" fill="currentColor"/><circle cx="10" cy="8" r="1" fill="currentColor"/><circle cx="6" cy="12" r="1" fill="currentColor"/><circle cx="10" cy="12" r="1" fill="currentColor"/>',
    note: `<path d="M3 3.5h10v7H8l-3 2.5v-2.5H3z" ${s}/>`,
    mark: '<path d="M8 2.2a4 4 0 0 0-4 4c0 3 4 7.6 4 7.6s4-4.6 4-7.6a4 4 0 0 0-4-4z" fill="currentColor"/>',
    gem: '<rect x="4.2" y="4.2" width="7.6" height="7.6" rx="1.2" transform="rotate(45 8 8)" fill="currentColor"/>',
    brief: `<path d="M4 2.5h8v11H4z" ${s}/><path d="M6 5.5h4M6 8h4M6 10.5h2" ${s}/>`,
    takes: `<rect x="2" y="3.5" width="5.2" height="4" rx="1" ${s}/><rect x="8.8" y="3.5" width="5.2" height="4" rx="1" ${s}/><rect x="2" y="9" width="5.2" height="4" rx="1" ${s}/><rect x="8.8" y="9" width="5.2" height="4" rx="1" ${s}/>`,
    split: `<rect x="2" y="3.5" width="12" height="9" rx="1.5" ${s}/><path d="M8 3.5v9" ${s}/>`,
    history: `<path d="M2.8 8a5.2 5.2 0 1 0 1.6-3.8M2.5 2.8v2.6h2.6" ${s}/><path d="M8 5.5v2.8l1.8 1.1" ${s}/>`,
    offline: `<path d="M2.5 6.5a8 8 0 0 1 11 0M4.6 8.8a5 5 0 0 1 6.8 0M6.8 11a2 2 0 0 1 2.4 0M2.5 2.5l11 11" ${s}/>`,
    trash: `<path d="M3 4.5h10M6.5 4.5V3h3v1.5M4.5 4.5l.6 9h5.8l.6-9" ${s}/>`,
    sidebar: `<rect x="2" y="3" width="12" height="10" rx="1.5" ${s}/><path d="M6 3v10" ${s}/>`,
    sliders: `<path d="M3 4.5h10M3 8h10M3 11.5h10" ${s}/><circle cx="6" cy="4.5" r="1.4" fill="var(--ground)" ${s}/><circle cx="10.5" cy="8" r="1.4" fill="var(--ground)" ${s}/><circle cx="5" cy="11.5" r="1.4" fill="var(--ground)" ${s}/>`,
    cmd: `<path d="M6 6V4.5A1.5 1.5 0 1 0 4.5 6H6zm0 0h4M6 6v4m4-4V4.5A1.5 1.5 0 1 1 11.5 6H10zm0 0v4m0 0v1.5a1.5 1.5 0 1 0 1.5-1.5H10zm0 0H6m0 0v1.5A1.5 1.5 0 1 1 4.5 10H6z" ${s}/>`,
    star: `<path d="m8 2.5 1.7 3.5 3.8.5-2.8 2.6.7 3.8L8 11.1l-3.4 1.8.7-3.8-2.8-2.6 3.8-.5z" ${s}/>`
  };
  let defs = '';
  for (const [k, v] of Object.entries(icons)) defs += `<symbol id="i-${k}" viewBox="${k === 'circle' ? '0 0 38 30' : '0 0 16 16'}">${v}</symbol>`;
  document.body.insertAdjacentHTML('afterbegin', `<svg width="0" height="0" style="position:absolute" aria-hidden="true"><defs>${defs}</defs></svg>`);

  if (location.search.includes('layout')) {
    addEventListener('load', () => {
      const out = [...document.querySelectorAll('[data-c]')].map(el => {
        const r = el.getBoundingClientRect(), cs = getComputedStyle(el);
        return { c: el.dataset.c, x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height),
          bg: cs.backgroundColor, color: cs.color, radius: cs.borderRadius, font: `${cs.fontWeight} ${cs.fontSize} ${cs.fontFamily.split(',')[0]}` };
      });
      const pre = document.createElement('pre'); pre.id = 'layout'; pre.textContent = JSON.stringify(out); document.body.appendChild(pre);
    });
  }
})();
