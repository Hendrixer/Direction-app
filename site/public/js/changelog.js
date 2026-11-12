// Changelog: scale each version's picture to its column, and fade entries in.
(() => {
  const fit = new ResizeObserver(es => es.forEach(e => e.target.firstElementChild.style.setProperty('--k', e.contentRect.width / 720)));
  document.querySelectorAll('.cl-hero').forEach(h => fit.observe(h));

  if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  const rv = new IntersectionObserver(es => es.forEach(e => { if (e.isIntersecting) { e.target.classList.add('in'); rv.unobserve(e.target); } }), { rootMargin: '0px 0px -8% 0px' });
  document.querySelectorAll('.rv').forEach(el => rv.observe(el));
})();
