// modes/milkdrop/frag/warp_kaleido.frag
// Exact kaleidoscope fold. The sampling angle is folded into one half-wedge by
// radial reflection — a = mod(a, 2*pi/N) then a = |a - pi/N| — so every output
// pixel pulls from the same half-wedge and the frame reconstructs as N
// mirror-symmetric wedges. Radius is untouched, so the radial warp terms keep
// their magnitude and only the direction mirrors.
//
// A wedge warp that *displaces* each wedge about its own centre shears the
// picture into shards but never mirrors across a wedge boundary, so it cannot
// produce this reflection. The fold here is a projection (applying it twice is
// the identity on the already-folded range), so compositing it into the
// feedback converges in one frame rather than compounding.
//
// Construct from three.js examples/jsm/shaders/KaleidoShader.js (MIT, Copyright
// (c) 2010-2026 three.js authors; that file credits pixelshaders.com / Toby
// Schachman as its own upstream). Self-authored implementation of the fold, not
// a copy — it is wired into the MilkDrop warp chain rather than standing alone,
// takes the wedge count from the engine's own `sectors`, and decays the way
// every warp fragment must.
//
// Feedback-only: this pass decays and never adds light (SCENE-LIBRARY design
// law). uv.y is top-down in eyesy shader space; MilkDrop math is y-up Cartesian,
// so convert once and work in uv-space (0..1) from there.
//
// Uniforms (draw_shader arg 5 = named, arg 6 = target samplers):
//   prev           sampler2D  - previous feedback frame (arg 6)
//   zoom           float      default 1.004  (per-frame scale around (cx,cy))
//   zoomexp        float      default 1.0    (exponent applied to the radial scale)
//   rot            float      default 0.0    (rotation, radians)
//   warp           float      default 0.011  (spherical pinch strength)
//   cx             float      default 0.5    (warp focus x, uv-space)
//   cy             float      default 0.5    (warp focus y, uv-space)
//   dx             float      default 0.0    (horizontal translate)
//   dy             float      default 0.0    (vertical translate)
//   sx             float      default 1.0    (x squash/stretch)
//   sy             float      default 1.0    (y squash/stretch)
//   decay          float      default 0.98   (multiplicative fade per frame)
//   aspect         float      default 16/9   (width/height, for x-axis aspect)
//   texel          vec2       default (1/640,1/360) (1/pixel in uv space)
//   sectors        float      default 8.0    (wedge count N)
//   kaleido_angle  float      default 0.0    (fold rotation, radians)

precision highp float;

varying vec2 uv;

uniform float zoom;
uniform float zoomexp;
uniform float rot;
uniform float warp;
uniform float cx;
uniform float cy;
uniform float dx;
uniform float dy;
uniform float sx;
uniform float sy;
uniform float decay;
uniform float aspect;
uniform vec2 texel;
uniform float sectors;
uniform float kaleido_angle;

uniform sampler2D prev;

const float PI = 3.14159265359;

void main() {
    // y-up Cartesian, origin at screen center, x axis aspect-corrected
    vec2 p = vec2((uv.x - 0.5) * aspect, 0.5 - uv.y);

    // --- kaleidoscope fold: angle into one half-wedge, radius preserved ---
    float r = length(p);
    float a = atan(p.y, p.x) + kaleido_angle;
    float wedge = 2.0 * PI / max(sectors, 2.0);
    a = mod(a, wedge);            // into [0, wedge)
    a = abs(a - wedge * 0.5);     // mirror into [0, wedge/2) -> N-fold symmetry
    p = r * vec2(cos(a), sin(a));

    // --- default warp math on top ---
    vec2 q = p - vec2((cx - 0.5) * aspect, cy - 0.5);
    float rq = length(q);

// zoom: radial scale around the focus (MilkDrop spec: zoom 1.0 = no zoom);
// zoomexp bends that zoom's curvature (spec: 1 = normal), so 1.0/1.0 is the
// identity and the scale applied here is zoom * r^zoomexp / r.
    q *= zoom * pow(max(rq, 1e-6), zoomexp) / (rq + 1e-6);

    // spherical pinch: the classic MilkDrop 'warp' term pushes uv outward
    // from the focus with a 1/(r+eps) falloff
    q += warp * q / (rq + 0.02);

    // rotation (y-up: standard 2D rotation matrix)
    float rc = cos(rot);
    float rs = sin(rot);
    q = mat2(rc, rs, -rs, rc) * q;

    // squash/stretch + roam translate
    q = q * vec2(sx, sy) + vec2(dx * aspect, dy);

    // back to uv space (y flipped again)
    vec2 wuv = q + vec2((cx - 0.5) * aspect, cy - 0.5);
    wuv = vec2(wuv.x / aspect + 0.5, 0.5 - wuv.y);

    // canonical decay: sample prev at the warped uv and fade it
    vec3 col = texture2D(prev, wuv).rgb * decay;
    gl_FragColor = vec4(col, 1.0);
}