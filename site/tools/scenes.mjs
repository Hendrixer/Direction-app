// Draws the stand-in picture for the page: plainly not footage, cheap to ship, and easy to swap for real frames.
// Run: node site/tools/scenes.mjs  (writes site/img/*.svg)
import { writeFileSync } from 'node:fs';
const out = new URL('../public/img/', import.meta.url);
const W = 1920, H = 1080;

function rng(seed) { return () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let t = Math.imul(seed ^ seed >>> 15, 1 | seed); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
const r1 = n => Math.round(n * 10) / 10;

// A ridge line by midpoint displacement over a base curve.
function ridge({ seed, n = 128, base, amp, rough = 0.55 }) {
  const rand = rng(seed); const ys = new Array(n + 1).fill(0);
  ys[0] = (rand() - .5) * amp; ys[n] = (rand() - .5) * amp;
  for (let step = n, a = amp; step > 1; step >>= 1, a *= rough)
    for (let i = 0; i + step <= n; i += step) { const m = i + step / 2; ys[m] = (ys[i] + ys[i + step]) / 2 + (rand() - .5) * a; }
  return ys.map((y, i) => { const x = i / n * W; return [x, base(x) + y]; });
}
const path = pts => `M0 ${H}L` + pts.map(([x, y]) => `${r1(x)} ${r1(y)}`).join('L') + `L${W} ${H}Z`;
const at = (pts, x) => { const i = Math.min(pts.length - 2, Math.floor(x / W * (pts.length - 1))); const [x0, y0] = pts[i], [x1, y1] = pts[i + 1]; return y0 + (y1 - y0) * (x - x0) / (x1 - x0); };
const svg = (body, defs = '') => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid slice"><defs>${defs}</defs>${body}</svg>`;

/* ---------- The ridge at dusk: sky, far ranges, near ridge with Maya and the telescope ---------- */
const far = [
  { seed: 11, n: 64,  base: x => 596 - 40 * Math.sin(x / 520), amp: 120, rough: .6, top: '#8c4a62', foot: '#c56a6a' },
  { seed: 23, n: 64,  base: x => 640 + 24 * Math.sin(x / 300 + 1), amp: 150, rough: .58, top: '#5b2f55', foot: '#9c5066' },
  { seed: 37, n: 128, base: x => 700 - 30 * Math.cos(x / 410), amp: 170, rough: .56, top: '#341d40', foot: '#6a3a58' },
  { seed: 51, n: 128, base: x => 790 + 40 * Math.sin(x / 600 + 2), amp: 90, rough: .52, top: '#1b1127', foot: '#3a2340' },
];
const ridges = far.map(f => ({ ...f, pts: ridge(f) }));
const near = ridge({ seed: 77, n: 128, amp: 26, rough: .5, base: x => { const c = 1180, d = (x - c) / 900; return 772 + 150 * d * d + (x < c ? 30 * Math.max(0, -d) : 0); } });
const crestX = 1180, crestY = Math.min(...near.filter(([x]) => Math.abs(x - crestX) < 40).map(([, y]) => y));
const sunX = 1330, sunY = at(ridges[0].pts, sunX) - 6;

const rand = rng(5);
let stars = '';
for (let i = 0; i < 90; i++) { const x = rand() * W, y = rand() * 430, r = .5 + rand() * rand() * 1.6, o = .25 + rand() * .65; stars += `<circle cx="${r1(x)}" cy="${r1(y)}" r="${r1(r)}" fill="#fff" opacity="${r1(o)}"/>`; }

const sky = svg(
  `<rect width="${W}" height="${H}" fill="url(#sky)"/>` + stars +
  `<circle cx="${sunX}" cy="${r1(sunY)}" r="520" fill="url(#bloom)"/>` +
  `<circle cx="${sunX}" cy="${r1(sunY)}" r="26" fill="#fff4dc"/>` +
  `<circle cx="${sunX}" cy="${r1(sunY)}" r="70" fill="url(#halo)"/>`,
  `<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#05081a"/><stop offset=".28" stop-color="#11173a"/><stop offset=".42" stop-color="#2c2556"/>
    <stop offset=".5" stop-color="#5b305f"/><stop offset=".55" stop-color="#a04c56"/><stop offset=".59" stop-color="#e08a58"/>
    <stop offset=".63" stop-color="#f7c47c"/><stop offset="1" stop-color="#f7c47c"/></linearGradient>
  <radialGradient id="bloom"><stop offset="0" stop-color="#ffd9a0" stop-opacity=".62"/><stop offset=".18" stop-color="#ffb070" stop-opacity=".32"/><stop offset=".5" stop-color="#e0705a" stop-opacity=".1"/><stop offset="1" stop-color="#e0705a" stop-opacity="0"/></radialGradient>
  <radialGradient id="halo"><stop offset=".3" stop-color="#fff0d0" stop-opacity=".9"/><stop offset="1" stop-color="#ffd090" stop-opacity="0"/></radialGradient>`);

const farSvg = svg(
  ridges.map((r, i) => `<path d="${path(r.pts)}" fill="url(#r${i})"/>`).join(''),
  ridges.map((r, i) => { const top = Math.min(...r.pts.map(p => p[1])); return `<linearGradient id="r${i}" gradientUnits="userSpaceOnUse" x1="0" y1="${r1(top)}" x2="0" y2="${r1(top + 220)}"><stop offset="0" stop-color="${r.top}"/><stop offset="1" stop-color="${r.foot}"/></linearGradient>`; }).join(''));

// Maya: standing, turned a little toward the telescope. Feet at (0,0), about 92 tall.
const maya = `M-5 0L-4 -30L-9 -31L-11 -56Q-11 -66 -4 -68L4 -68Q11 -66 11 -56L9 -31L4 -30L5 0L1.5 0L0 -26L-1.5 0Z M0 -70a8 8 0 1 0 0 -16a8 8 0 1 0 0 16Z M-6 -78Q0 -90 7 -79L6 -74Q0 -80 -6 -74Z`;
// The telescope: a tripod and a tube pointing up into the dark.
const scope = `M30 0L42 -44L44 -44L33 0Z M58 0L46 -44L44 -44L55 0Z M43 0L44 -44L45 -44L44.6 0Z M34 -47L76 -96L82 -91L40 -42Z M74 -101L86 -91L84 -88L72 -98Z`;
const fig = (fill, dx = 0, dy = 0) => `<g transform="translate(${crestX + dx} ${r1(crestY + 2 + dy)})" fill="${fill}"><path d="${maya}"/><path d="${scope}"/></g>`;
const nearSvg = svg(
  `<path d="${path(near)}" fill="url(#near)"/>` +
  `<path d="${path(near)}" fill="none" stroke="#f3a768" stroke-opacity=".55" stroke-width="1.6" transform="translate(0 -.8)" clip-path="url(#rimclip)"/>` +
  fig('#ffbe7a', 1.8, -.4) + fig('#07060b'),
  `<linearGradient id="near" x1="0" y1="0" x2="0" y2="1"><stop offset=".68" stop-color="#0c0912"/><stop offset="1" stop-color="#040306"/></linearGradient>
   <clipPath id="rimclip"><rect x="${crestX - 520}" y="0" width="900" height="${H}"/></clipPath>`);

// One file with every layer, for thumbnails and the notes picture.
const inner = str => ({ defs: str.match(/<defs>([\s\S]*?)<\/defs>/)[1], body: str.replace(/^[\s\S]*?<\/defs>/, '').replace(/<\/svg>$/, '') });
const parts = [sky, farSvg, nearSvg].map(inner);
writeFileSync(new URL('ridge.svg', out), svg(parts.map(p => p.body).join(''), parts.map(p => p.defs).join('')));
writeFileSync(new URL('ridge-sky.svg', out), sky);
writeFileSync(new URL('ridge-far.svg', out), farSvg);
writeFileSync(new URL('ridge-near.svg', out), nearSvg);

/* ---------- Night street: the cold open ---------- */
{
  const rand = rng(91); let b = '', win = '';
  let x = -20;
  while (x < W) {
    const w = 90 + rand() * 170, h = 260 + rand() * 420, top = 760 - h, shade = ['#0a0e1c', '#0d1224', '#080b17', '#0f1428'][Math.floor(rand() * 4)];
    b += `<rect x="${r1(x)}" y="${r1(top)}" width="${r1(w)}" height="${r1(H - top)}" fill="${shade}"/>`;
    for (let wy = top + 24; wy < 730; wy += 26) for (let wx = x + 12; wx < x + w - 18; wx += 22)
      if (rand() < .16) { const warm = rand() < .7; win += `<rect x="${r1(wx)}" y="${r1(wy)}" width="9" height="13" fill="${warm ? '#f2b56b' : '#9fd0ff'}" opacity="${r1(.35 + rand() * .6)}"/>`; }
    x += w + 4 + rand() * 18;
  }
  let lamps = '';
  for (const lx of [260, 820, 1380, 1880]) lamps += `<rect x="${lx - 2}" y="560" width="4" height="240" fill="#05070d"/><circle cx="${lx}" cy="560" r="160" fill="url(#lamp)"/><circle cx="${lx}" cy="560" r="5" fill="#fff1d6"/><ellipse cx="${lx}" cy="905" rx="40" ry="160" fill="url(#refl)" opacity=".7"/>`;
  const street = svg(
    `<rect width="${W}" height="${H}" fill="url(#nsky)"/>` + b + win +
    `<rect y="760" width="${W}" height="${H - 760}" fill="url(#road)"/>` + lamps +
    `<rect y="0" width="${W}" height="${H}" fill="url(#fog)"/>`,
    `<linearGradient id="nsky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#03050d"/><stop offset=".6" stop-color="#0d1530"/><stop offset=".72" stop-color="#1d2a55"/></linearGradient>
     <linearGradient id="road" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0c1226"/><stop offset="1" stop-color="#03050b"/></linearGradient>
     <radialGradient id="lamp"><stop offset="0" stop-color="#ffd59a" stop-opacity=".55"/><stop offset=".35" stop-color="#f2a65a" stop-opacity=".14"/><stop offset="1" stop-color="#f2a65a" stop-opacity="0"/></radialGradient>
     <radialGradient id="refl"><stop offset="0" stop-color="#f2b56b" stop-opacity=".5"/><stop offset="1" stop-color="#f2b56b" stop-opacity="0"/></radialGradient>
     <linearGradient id="fog" x1="0" y1="0" x2="0" y2="1"><stop offset=".55" stop-color="#3a4a80" stop-opacity="0"/><stop offset=".72" stop-color="#3a4a80" stop-opacity=".22"/><stop offset=".85" stop-color="#3a4a80" stop-opacity="0"/></linearGradient>`);
  writeFileSync(new URL('street.svg', out), street);
}

/* ---------- Her face: a close profile, lit from the right by a street lamp ---------- */
{
  const face = `M1010 1080C1000 980 960 930 930 900C900 870 880 830 884 780C860 770 850 750 862 735C850 722 852 705 866 700C858 690 856 676 868 664C850 650 838 636 846 618C858 600 870 594 872 570C876 470 940 380 1050 360C1170 340 1290 400 1330 520C1360 610 1340 700 1300 760C1280 800 1290 860 1330 920C1360 960 1400 1010 1420 1080Z`;
  const svgFace = svg(
    `<rect width="${W}" height="${H}" fill="url(#bg)"/><circle cx="260" cy="380" r="700" fill="url(#glow)"/>` +
    `<circle cx="300" cy="300" r="10" fill="#fff1d6" opacity=".85"/><circle cx="520" cy="620" r="6" fill="#9fd0ff" opacity=".35"/><circle cx="140" cy="760" r="8" fill="#f2b56b" opacity=".3"/>` +
    `<g fill="#ffc483" transform="translate(-6 1)"><path d="${face}"/></g>` +
    `<g fill="url(#skin)"><path d="${face}"/><circle cx="1312" cy="420" r="84"/><path d="M1230 380C1300 330 1370 360 1390 430L1340 520Z"/></g>`,
    `<linearGradient id="bg" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#141c3a"/><stop offset="1" stop-color="#04050a"/></linearGradient>
     <radialGradient id="glow"><stop offset="0" stop-color="#f2b56b" stop-opacity=".35"/><stop offset=".5" stop-color="#6a4a80" stop-opacity=".1"/><stop offset="1" stop-color="#6a4a80" stop-opacity="0"/></radialGradient>
     <linearGradient id="skin" gradientUnits="userSpaceOnUse" x1="860" y1="0" x2="1420" y2="0"><stop offset="0" stop-color="#1c1514"/><stop offset=".25" stop-color="#0a0809"/><stop offset="1" stop-color="#050407"/></linearGradient>`);
  writeFileSync(new URL('face.svg', out), svgFace);
}

/* ---------- The garage at night: Maya at the bench, a window of blue, a warm lamp ---------- */
{
  const room = svg(
    `<rect width="${W}" height="${H}" fill="#0a0910"/>` +
    // window: cold light from outside, mullions
    `<rect x="250" y="170" width="430" height="560" fill="url(#win)"/>` +
    `<path d="M250 170h430v560H250z M462 170v560 M250 450h430" fill="none" stroke="#08070c" stroke-width="16"/>` +
    // light spill on the floor
    `<path d="M250 730L680 730L1020 1080L120 1080Z" fill="url(#spill)"/>` +
    // lamp pool on the bench
    `<circle cx="1420" cy="660" r="430" fill="url(#lamp)"/>` +
    // bench and telescope tube resting on it
    `<rect x="1020" y="760" width="760" height="22" fill="#151017"/><rect x="1060" y="782" width="18" height="300" fill="#0d0a10"/><rect x="1720" y="782" width="18" height="300" fill="#0d0a10"/>` +
    `<path d="M1180 742L1560 700L1566 730L1186 772Z" fill="#1d1820"/><path d="M1180 742L1560 700L1561 706L1181 748Z" fill="#e2a868" opacity=".55"/>` +
    // the lamp
    `<path d="M1490 760L1500 600L1430 560L1438 548L1512 592L1504 760Z" fill="#100c12"/><path d="M1400 520L1480 560L1450 600L1370 560Z" fill="#100c12"/><circle cx="1428" cy="580" r="10" fill="#fff0d0"/>` +
    // Maya, seated, turned to the window: rim of blue on the window side, warm on the lamp side
    `<g transform="translate(860 1080)"><path d="M-150 0C-160 -120 -130 -230 -60 -262C-70 -300 -64 -350 -20 -372C30 -394 84 -366 92 -318C98 -286 86 -262 66 -250C130 -226 170 -150 176 0Z" fill="#7aa6e0" opacity=".5" transform="translate(-5 0)"/>` +
    `<path d="M-150 0C-160 -120 -130 -230 -60 -262C-70 -300 -64 -350 -20 -372C30 -394 84 -366 92 -318C98 -286 86 -262 66 -250C130 -226 170 -150 176 0Z" fill="#f0b071" opacity=".45" transform="translate(5 0)"/>` +
    `<path d="M-150 0C-160 -120 -130 -230 -60 -262C-70 -300 -64 -350 -20 -372C30 -394 84 -366 92 -318C98 -286 86 -262 66 -250C130 -226 170 -150 176 0Z" fill="#060509"/></g>` +
    `<rect width="${W}" height="${H}" fill="url(#vig)"/>`,
    `<linearGradient id="win" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2a3f78"/><stop offset=".7" stop-color="#5a78b8"/><stop offset="1" stop-color="#8aa6d8"/></linearGradient>
     <linearGradient id="spill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5a78b8" stop-opacity=".28"/><stop offset="1" stop-color="#5a78b8" stop-opacity="0"/></linearGradient>
     <radialGradient id="lamp"><stop offset="0" stop-color="#ffcf8a" stop-opacity=".5"/><stop offset=".4" stop-color="#e09050" stop-opacity=".14"/><stop offset="1" stop-color="#e09050" stop-opacity="0"/></radialGradient>
     <radialGradient id="vig" cx=".5" cy=".5" r=".75"><stop offset=".6" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".6"/></radialGradient>`);
  writeFileSync(new URL('garage.svg', out), room);
}
console.log('crest', crestX, Math.round(crestY), 'sun', sunX, Math.round(sunY));
