// The chrome D, lit by a light that circles it — a WebGL2 port of Sources/DirectionApp/Gate/ChromeMark.swift.
// The bevel is rebuilt from the letter's silhouette; red to violet each see the light from a slightly
// different angle, so lit edges split into spectra the way chrome and glass disperse light.
// On a desktop the light follows the pointer while it's over the section; otherwise it orbits:
// slow out of rest, quick through the middle, a long eased stall, then a rest.
// No WebGL2, or Reduce Motion, keeps the still image.
(() => {
  const host = document.getElementById('mark');
  if (!host) return;
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const PASS = 5.6, REST = 2.4, RESTING = 1.25 * Math.PI;

  // cubic-bezier(.72, 0, .14, 1), solved by bisection
  const curve = x => {
    const B = (a, b, t) => 3 * a * t * (1 - t) ** 2 + 3 * b * t * t * (1 - t) + t ** 3;
    let lo = 0, hi = 1, t = x;
    for (let i = 0; i < 24; i++) { t = (lo + hi) / 2; if (B(.72, .14, t) < x) lo = t; else hi = t; }
    return B(0, 1, t);
  };
  const orbit = s => { const t = s % (PASS + REST); return RESTING + (t >= PASS ? 0 : curve(t / PASS)) * 2 * Math.PI; };

  const VERT = `#version 300 es
  in vec2 p; out vec2 uv;
  void main() { uv = vec2(p.x * .5 + .5, .5 - p.y * .5); gl_Position = vec4(p, 0., 1.); }`;

  const FRAG = `#version 300 es
  precision highp float;
  uniform sampler2D art; uniform sampler2D height;
  uniform vec2 light; uniform float lod; uniform vec2 artSize; uniform vec2 hSize;
  in vec2 uv; out vec4 o;
  const float elevation = .32, bevel = 30., detail = 1.4, intensity = 2.2, spread = .5, orbitR = .78, falloff = 1.6, saturation = .2, lobe = 7.;
  float luma(vec3 c) { return dot(c, vec3(.3, .59, .11)); }
  void main() {
    vec4 c = textureLod(art, uv, lod);
    if (c.a < .002) { o = vec4(0.); return; }
    vec2 hs = 1. / hSize;
    float hc = texture(height, uv).r;
    float hx = texture(height, uv + vec2(hs.x, 0.)).r - texture(height, uv - vec2(hs.x, 0.)).r;
    float hy = texture(height, uv + vec2(0., hs.y)).r - texture(height, uv - vec2(0., hs.y)).r;
    vec2 as = exp2(lod) / artSize;
    float lx = luma(textureLod(art, uv + vec2(as.x, 0.), lod).rgb) - luma(textureLod(art, uv - vec2(as.x, 0.), lod).rgb);
    float ly = luma(textureLod(art, uv + vec2(0., as.y), lod).rgb) - luma(textureLod(art, uv - vec2(0., as.y), lod).rgb);
    vec3 n = normalize(vec3(-hx * bevel - lx * detail, -hy * bevel - ly * detail, 1.));
    float rim = 1. - hc;
    vec2 toLight = vec2(.5) + light * orbitR - uv;
    float reach = 1. / (1. + falloff * dot(toLight, toLight) * 4.);
    c.rgb = mix(vec3(luma(c.rgb)), c.rgb, mix(saturation, 1., clamp(reach * 1.5, 0., 1.)));
    float base = atan(toLight.y, toLight.x);
    vec2 slope = vec2(-hx, -hy) / max(length(vec2(hx, hy)), 1e-5);
    float band = sin(3.14159 * clamp(rim, 0., 1.));
    vec3 spectrum[7] = vec3[7](vec3(1., 0., .05), vec3(1., .45, 0.), vec3(.85, .85, 0.), vec3(.1, 1., .2), vec3(0., .75, 1.), vec3(.15, .25, 1.), vec3(.6, 0., 1.));
    vec3 fringe = vec3(0.);
    for (int i = 0; i < 7; i++) {
      float a = base + (float(i) - 3.) / 3. * spread;
      fringe += spectrum[i] * pow(clamp(dot(slope, vec2(cos(a), sin(a))), 0., 1.), lobe);
    }
    fringe /= vec3(2.7, 3.3, 2.45);
    float core = pow(clamp(dot(slope, vec2(cos(base), sin(base))), 0., 1.), lobe * 2.5);
    vec3 edge = (vec3(core) * .85 + fringe * .75) * band;
    vec3 l = normalize(vec3(toLight, elevation));
    float glint = pow(max(dot(n, normalize(l + vec3(0., 0., 1.))), 0.), 60.) * (1. - rim);
    float facing = dot(slope, normalize(toLight));
    float ambient = .64 + .5 * reach;
    vec3 shaded = c.rgb * ambient * mix(1., .5 + .65 * clamp(facing, 0., 1.), band);
    vec3 lit = shaded + (edge * intensity + glint * .5) * reach * c.a;
    o = vec4(min(lit, vec3(c.a)), c.a);
  }`;

  // The bevel as a height field: the alpha blurred wide (three box blurs ≈ a Gaussian), re-ranged so the
  // rim sits just inside the silhouette.
  function heightField(img, side = 512, radius = 11) {
    const cv = document.createElement('canvas'); cv.width = cv.height = side;
    const cx = cv.getContext('2d', { willReadFrequently: true }); cx.drawImage(img, 0, 0, side, side);
    const px = cx.getImageData(0, 0, side, side).data;
    let f = new Float32Array(side * side);
    for (let i = 0; i < f.length; i++) f[i] = px[i * 4 + 3] / 255;
    const tmp = new Float32Array(side), w = 2 * radius + 1;
    const pass = horizontal => {
      for (let r = 0; r < side; r++) {
        const at = c => horizontal ? r * side + c : c * side + r;
        let sum = 0;
        for (let k = -radius; k <= radius; k++) sum += f[at(Math.min(Math.max(k, 0), side - 1))];
        for (let c = 0; c < side; c++) {
          tmp[c] = sum / w;
          sum += f[at(Math.min(c + radius + 1, side - 1))] - f[at(Math.max(c - radius, 0))];
        }
        for (let c = 0; c < side; c++) f[at(c)] = tmp[c];
      }
    };
    for (let i = 0; i < 3; i++) { pass(true); pass(false); }
    for (let i = 0; i < f.length; i++) { const t = Math.min(Math.max((f[i] - .72) / .275, 0), 1); f[i] = 1 - (1 - t) * (1 - t); }
    return f;
  }

  async function start() {
    const still = host.querySelector('img');
    const img = new Image(); img.src = still.currentSrc || still.src;
    try { await img.decode(); } catch { return; }
    const canvas = document.createElement('canvas');
    const gl = canvas.getContext('webgl2', { premultipliedAlpha: true, alpha: true, antialias: false });
    if (!gl) return;

    const sh = (type, src) => { const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s); if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s)); return s; };
    const prog = gl.createProgram();
    try { gl.attachShader(prog, sh(gl.VERTEX_SHADER, VERT)); gl.attachShader(prog, sh(gl.FRAGMENT_SHADER, FRAG)); } catch (e) { console.warn(e); return; }
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) return;
    gl.useProgram(prog);

    const buf = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    const loc = gl.getAttribLocation(prog, 'p'); gl.enableVertexAttribArray(loc); gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);

    const art = gl.createTexture(); gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, art);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, img);
    gl.generateMipmap(gl.TEXTURE_2D);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    for (const p of [gl.TEXTURE_WRAP_S, gl.TEXTURE_WRAP_T]) gl.texParameteri(gl.TEXTURE_2D, p, gl.CLAMP_TO_EDGE);

    const side = 512;
    const height = gl.createTexture(); gl.activeTexture(gl.TEXTURE1); gl.bindTexture(gl.TEXTURE_2D, height);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.R16F, side, side, 0, gl.RED, gl.FLOAT, heightField(img, side));
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    for (const p of [gl.TEXTURE_WRAP_S, gl.TEXTURE_WRAP_T]) gl.texParameteri(gl.TEXTURE_2D, p, gl.CLAMP_TO_EDGE);

    const u = n => gl.getUniformLocation(prog, n);
    gl.uniform1i(u('art'), 0); gl.uniform1i(u('height'), 1);
    gl.uniform2f(u('artSize'), img.naturalWidth, img.naturalHeight);
    gl.uniform2f(u('hSize'), side, side);
    const uLight = u('light'), uLod = u('lod');

    const size = () => {
      const px = Math.max(32, Math.min(1024, Math.round(host.clientWidth * Math.min(devicePixelRatio || 1, 2))));
      if (canvas.width !== px) { canvas.width = canvas.height = px; gl.viewport(0, 0, px, px); gl.uniform1f(uLod, Math.max(0, Math.log2(img.naturalWidth / px))); }
    };
    size(); new ResizeObserver(() => { size(); if (!running) draw(angle); }).observe(host);
    host.appendChild(canvas);

    const draw = a => { gl.uniform2f(uLight, Math.cos(a), Math.sin(a)); gl.drawArrays(gl.TRIANGLES, 0, 3); };

    let angle = RESTING, pointer = null, running = false, visible = true, last = performance.now();
    draw(angle);
    requestAnimationFrame(() => host.classList.add('lit'));
    if (reduce) return;

    // The light follows the pointer like a torch held near the letter; let go and it rejoins its orbit.
    const section = host.closest('section') || host.parentElement;
    section.addEventListener('pointermove', e => {
      if (e.pointerType !== 'mouse') return;
      const r = host.getBoundingClientRect();
      pointer = Math.atan2(e.clientY - (r.top + r.height / 2), e.clientX - (r.left + r.width / 2));
    });
    section.addEventListener('pointerleave', () => { pointer = null; });

    const t0 = performance.now();
    const frame = now => {
      if (!visible) { running = false; return; }
      const dt = Math.min(.1, (now - last) / 1000); last = now;
      const target = pointer ?? orbit((now - t0) / 1000);
      let d = (target - angle) % (2 * Math.PI);
      if (d > Math.PI) d -= 2 * Math.PI; if (d < -Math.PI) d += 2 * Math.PI;
      angle += d * (1 - Math.exp(-dt * (pointer == null ? 9 : 5)));
      draw(angle);
      requestAnimationFrame(frame);
    };
    new IntersectionObserver(([e]) => {
      visible = e.isIntersecting;
      if (visible && !running) { running = true; last = performance.now(); requestAnimationFrame(frame); }
    }).observe(host);
  }

  // Load the light only as the end of the page comes near.
  const io = new IntersectionObserver(([e]) => { if (e.isIntersecting) { io.disconnect(); start(); } }, { rootMargin: '600px 0px' });
  io.observe(host);
})();
