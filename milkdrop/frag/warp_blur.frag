// modes/milkdrop/frag/warp_blur.frag
// Painterly multi-blur flow. The warp samples the previous frame twice over:
// sharp, and through the engine's blur1 copy of it, gathered at three small
// offsets so the soft side blurs in both axes. The two are mixed and then the
// standard warp chain and decay apply as usual, so the blur lives *inside* the
// feedback loop — each frame feeds a slightly softened version of the last one
// forward, which is what gives the flow its painterly drag.
//
// Why the extra taps: blur1.frag is a separable pass whose default weight row
// offsets only in x, so a single fetch of it is horizontally smeared. Three
// vertical offsets of that result complete the 2D blur without a second pass,
// which matters because the target budget is full — four targets times two
// content sizes is already the engine's eight (see the README engine notes).
//
// The blurred copy is produced by the mode before this fragment runs, into the
// same `blur` target the glow composite uses; the two never need it at the same
// moment (the warp stage finishes with it before the composite stage starts).
//
// Feedback-only: this pass decays and never adds light (SCENE-LIBRARY design law).
// uv.y is top-down in eyesy shader space; MilkDrop math is y-up Cartesian, so
// convert once and work in uv-space (0..1) from there.
//
// Uniforms (draw_shader arg 5 = named, arg 6 = target samplers):
//   prev           sampler2D  - previous feedback frame (arg 6)
//   prev_blur      sampler2D  - blurred copy of it (arg 6)
//   zoom           float      default 1.004  (per-frame scale around (cx,cy))
//   zoomexp        float      default 1.0    (curvature of that zoom; 1.0 = normal)
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
//   blur_warp      float      default 0.55   (share of the blurred gather)
//   blur_spread    float      default 0.012  (vertical tap spacing, uv space)

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
uniform float blur_warp;
uniform float blur_spread;

uniform sampler2D prev;
uniform sampler2D prev_blur;

void main() {
    // y-up Cartesian, origin at screen center, x axis aspect-corrected
    vec2 p = vec2((uv.x - 0.5) * aspect, 0.5 - uv.y);

    // --- default warp math ---
    vec2 q = p - vec2((cx - 0.5) * aspect, cy - 0.5);
    float r = length(q);

    // zoom: radial scale around the focus (MilkDrop spec: zoom 1.0 = no zoom);
    // zoomexp bends that zoom's curvature (spec: 1 = normal), so 1.0/1.0 is the
    // identity and the scale applied here is zoom * r^zoomexp / r.
    q *= zoom * pow(max(r, 1e-6), zoomexp) / (r + 1e-6);

    // spherical pinch: the classic MilkDrop 'warp' term pushes uv outward
    // from the focus with a 1/(r+eps) falloff
    q += warp * q / (r + 0.02);

    // rotation (y-up: standard 2D rotation matrix)
    float rc = cos(rot);
    float rs = sin(rot);
    q = mat2(rc, rs, -rs, rc) * q;

    // squash/stretch + roam translate
    q = q * vec2(sx, sy) + vec2(dx * aspect, dy);

    // back to uv space (y flipped again)
    vec2 wuv = q + vec2((cx - 0.5) * aspect, cy - 0.5);
    wuv = vec2(wuv.x / aspect + 0.5, 0.5 - wuv.y);

    // --- the gathers: one sharp, three through the blurred copy ---
    vec3 sharp = texture2D(prev, wuv).rgb;

    // blur1 is horizontal-only, so these offsets run in y and complete it
    vec3 soft = vec3(0.0);
    for (int i = 0; i < 3; i++) {
        float o = (float(i) - 1.0) * blur_spread;
        soft += texture2D(prev_blur, wuv + vec2(0.0, o)).rgb;
    }
    soft /= 3.0;

    vec3 col = mix(sharp, soft, clamp(blur_warp, 0.0, 1.0)) * decay;
    gl_FragColor = vec4(col, 1.0);
}