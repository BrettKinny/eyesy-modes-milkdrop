// modes/milkdrop/frag/warp_default.frag
// Canonical MilkDrop warp pass (MilkDrop2 warp_ps.fx default, ported):
// sample the previous feedback frame at the analytically-warped uv, apply
// decay, and write the feedback target. Feedback-only: this pass never adds
// light (SCENE-LIBRARY design law) — waves/shapes are drawn into the same
// target afterwards, and the next frame's warp decays everything together.
//
// uv.y is top-down in eyesy shader space; MilkDrop math is y-up Cartesian,
// so convert once and work in uv-space (0..1) from there.
//
// Uniforms (draw_shader arg 5 = named, arg 6 = target samplers):
//   prev     sampler2D  - previous feedback frame (arg 6)
//   zoom     float      default 1.004  (per-frame scale around (cx,cy))
//   zoomexp  float      default 1.0    (exponent applied to the radial scale)
//   rot      float      default 0.0    (rotation, radians)
//   warp     float      default 0.011  (spherical pinch strength)
//   cx       float      default 0.5    (warp focus x, uv-space)
//   cy       float      default 0.5    (warp focus y, uv-space)
//   dx       float      default 0.0    (horizontal translate)
//   dy       float      default 0.0    (vertical translate)
//   sx       float      default 1.0    (x squash/stretch)
//   sy       float      default 1.0    (y squash/stretch)
//   decay    float      default 0.98   (multiplicative fade per frame)
//   aspect   float      default 16/9   (width/height, for x-axis aspect)
//   texel    vec2       default (1/640,1/360) (1/pixel in uv space)

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

uniform sampler2D prev;

void main() {
    // y-up Cartesian, origin at screen center, x axis aspect-corrected
    vec2 p = vec2((uv.x - 0.5) * aspect, 0.5 - uv.y);

    // focus the warp on (cx, cy) instead of the center
    vec2 q = p - vec2((cx - 0.5) * aspect, cy - 0.5);
    float r = length(q);

// zoom: radial scale around the focus (MilkDrop spec: zoom 1.0 = no zoom);
// zoomexp bends that zoom's curvature (spec: 1 = normal), so 1.0/1.0 is the
// identity and the scale applied here is zoom * r^zoomexp / r.
    q *= zoom * pow(max(r, 1e-6), zoomexp) / (r + 1e-6);

    // spherical pinch: the classic MilkDrop 'warp' term pushes uv outward
    // from the focus with a 1/(r+eps) falloff (per-vertex mesh removed;
    // computed analytically per pixel)
    q += warp * q / (r + 0.02);

    // rotation (y-up: standard 2D rotation matrix)
    float c = cos(rot);
    float sn = sin(rot);
    q = mat2(c, sn, -sn, c) * q;

    // squash/stretch + roam translate
    q = q * vec2(sx, sy) + vec2(dx * aspect, dy);

    // back to uv space (y flipped again)
    vec2 wuv = q + vec2((cx - 0.5) * aspect, cy - 0.5);
    wuv = vec2(wuv.x / aspect + 0.5, 0.5 - wuv.y);

    // canonical decay: sample prev at the warped uv and fade it
    vec3 col = texture2D(prev, wuv).rgb * decay;
    gl_FragColor = vec4(col, 1.0);
}
