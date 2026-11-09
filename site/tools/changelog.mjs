// The changelog, from one source: site/changelog/<version>.md.
//
//   node site/tools/changelog.mjs              writes public/changelog/index.html and public/changelog/feed.xml
//   node site/tools/changelog.mjs notes 0.3.5  prints that version's notes as Markdown (GitHub release body)
//   node site/tools/changelog.mjs sparkle 0.3.5  prints them as Sparkle's "What's new" Markdown
//
// A version's file has frontmatter (version, date, build, title, and an optional hero: the name of a
// picture in site/changelog/heroes/<hero>.html), then Markdown. Everything before the first "## " is the
// write-up; each "## Name" after it (Improvements, Fixes) is a list that opens on click.
import { readFileSync, readdirSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';

const root = new URL('../', import.meta.url);
const SITE = 'https://givedirection.ai';
const REPO = 'https://github.com/Hendrixer/Direction-app';

/* ---------- Reading the notes ---------- */
function read(file) {
  const text = readFileSync(new URL(`changelog/${file}`, root), 'utf8');
  const m = text.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!m) throw new Error(`${file}: no frontmatter`);
  const meta = Object.fromEntries(m[1].split('\n').filter(Boolean).map(l => { const i = l.indexOf(':'); return [l.slice(0, i).trim(), l.slice(i + 1).trim()]; }));
  for (const k of ['version', 'date', 'title']) if (!meta[k]) throw new Error(`${file}: no ${k}`);
  const body = m[2].trim();
  const parts = body.split(/^## /m);
  const intro = parts.shift().trim();
  const sections = parts.map(p => { const nl = p.indexOf('\n'); return { name: p.slice(0, nl).trim(), md: p.slice(nl + 1).trim() }; });
  return { ...meta, body, intro, sections };
}
const semver = v => v.split('.').map(Number);
const newestFirst = (a, b) => { const x = semver(a.version), y = semver(b.version); for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return y[i] - x[i]; return 0; };
const releases = () => readdirSync(new URL('changelog/', root)).filter(f => /^\d+\.\d+\.\d+\.md$/.test(f)).map(read).sort(newestFirst);

/* ---------- A little Markdown: paragraphs, ### headings, lists (one level of nesting), bold, em, code, links ---------- */
const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const inline = s => esc(s)
  .replace(/`([^`]+)`/g, '<code>$1</code>')
  .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
  .replace(/(^|[^*])\*([^*\s][^*]*)\*/g, '$1<em>$2</em>')
  .replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, '<a href="$2">$1</a>');
function html(md) {
  const out = []; const lines = md.split('\n'); let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (!line.trim()) { i++; continue; }
    if (line.startsWith('### ')) { out.push(`<h3>${inline(line.slice(4))}</h3>`); i++; continue; }
    if (/^- /.test(line)) {
      const items = [];
      while (i < lines.length && (/^- /.test(lines[i]) || /^\s{2,}\S/.test(lines[i]))) {
        if (/^- /.test(lines[i])) items.push({ text: lines[i].slice(2), sub: [] });
        else { const t = lines[i].trim(); const last = items[items.length - 1]; if (t.startsWith('- ')) last.sub.push(t.slice(2)); else last.text += ' ' + t; }
        i++;
      }
      out.push('<ul>' + items.map(it => `<li>${inline(it.text)}${it.sub.length ? '<ul>' + it.sub.map(s => `<li>${inline(s)}</li>`).join('') + '</ul>' : ''}</li>`).join('') + '</ul>');
      continue;
    }
    const para = [];
    while (i < lines.length && lines[i].trim() && !/^(- |### )/.test(lines[i])) para.push(lines[i++].trim());
    out.push(`<p>${inline(para.join(' '))}</p>`);
  }
  return out.join('\n');
}
const plain = md => md.replace(/\*\*([^*]+)\*\*/g, '$1').replace(/`([^`]+)`/g, '$1').replace(/\[([^\]]+)\]\([^)]+\)/g, '$1');

/* ---------- The page ---------- */
const longDate = d => new Date(d + 'T12:00:00Z').toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric', timeZone: 'UTC' });
function entry(r, i) {
  const hero = r.hero && existsSync(new URL(`changelog/heroes/${r.hero}.html`, root))
    ? `<figure class="cl-hero rv" aria-hidden="true"><div class="cl-stage">${readFileSync(new URL(`changelog/heroes/${r.hero}.html`, root), 'utf8').trim()}</div></figure>` : '';
  const more = r.sections.map(s => {
    const n = (s.md.match(/^- /gm) || []).length;
    return `<details class="cl-more"><summary><span>${esc(s.name)}</span><span class="n">${n}</span></summary><div class="cl-more-body">${html(s.md)}</div></details>`;
  }).join('\n');
  return `
    <li class="cl-entry${i === 0 ? ' latest' : ''}" id="${r.version}">
      <div class="cl-when">
        <i class="gem${i === 0 ? '' : ' grey'}"></i>
        <a class="cl-ver" href="#${r.version}">${r.version}</a>
        <time datetime="${r.date}">${longDate(r.date)}</time>
      </div>
      <article class="cl-body">
        <h2 class="display">${esc(r.title)}</h2>
        ${hero}
        <div class="cl-prose">${html(r.intro)}</div>
        ${more ? `<div class="cl-mores">${more}</div>` : ''}
        <a class="cl-gh" href="${REPO}/releases/tag/v${r.version}">Direction ${r.version} on GitHub <span aria-hidden="true">↗</span></a>
      </article>
    </li>`;
}

function page(list) {
  const latest = list[0];
  const desc = `What's new in Direction, the Mac app for directing films. Latest: ${latest.version}, ${latest.title.toLowerCase()}.`;
  const template = readFileSync(new URL('changelog/template.html', root), 'utf8');
  return template
    .replaceAll('{{description}}', esc(desc))
    .replace('{{entries}}', list.map(entry).join('\n'))
    .replace('{{latest}}', latest.version);
}

function feed(list) {
  const updated = list[0].date + 'T12:00:00Z';
  const items = list.map(r => `  <entry>
    <id>${SITE}/changelog/#${r.version}</id>
    <title>${esc(`${r.version}: ${r.title}`)}</title>
    <link href="${SITE}/changelog/#${r.version}"/>
    <updated>${r.date}T12:00:00Z</updated>
    <content type="html">${esc(html(r.body.replace(/^## (.+)$/gm, '### $1')))}</content>
  </entry>`).join('\n');
  return `<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Direction changelog</title>
  <subtitle>What's new in Direction, the Mac app for directing films.</subtitle>
  <id>${SITE}/changelog/</id>
  <link href="${SITE}/changelog/"/>
  <link rel="self" href="${SITE}/changelog/feed.xml"/>
  <updated>${updated}</updated>
  <author><name>Direction</name></author>
${items}
</feed>
`;
}

/* ---------- Commands ---------- */
const [cmd, version] = process.argv.slice(2);
const list = releases();
const find = v => { const r = list.find(r => r.version === v); if (!r) { console.error(`No site/changelog/${v}.md`); process.exit(1); } return r; };

if (cmd === 'notes') {
  const r = find(version);
  process.stdout.write(`${r.body}\n\n---\n\n**Download:** [Direction ${r.version} for Mac](https://updates.givedirection.ai/Direction-${r.version}.dmg) (Apple silicon, macOS 26 or later). Copies you already have update themselves.\n\n[Read it on the changelog](${SITE}/changelog/#${r.version})\n`);
} else if (cmd === 'sparkle') {
  const r = find(version);
  process.stdout.write(`# What's new in Direction ${r.version}\n\n**${r.title}.** ${plain(r.intro).replace(/\n+/g, '\n\n')}\n\n${r.sections.map(s => s.md).join('\n')}\n`);
} else if (cmd === 'title') {
  const r = find(version);
  process.stdout.write(`${r.version}: ${r.title}`);
} else {
  const out = new URL('public/changelog/', root);
  mkdirSync(out, { recursive: true });
  writeFileSync(new URL('index.html', out), page(list));
  writeFileSync(new URL('feed.xml', out), feed(list));
  console.log(`Wrote the changelog: ${list.map(r => r.version).join(', ')}`);
}
