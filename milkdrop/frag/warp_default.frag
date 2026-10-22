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
//   zoom     float      default 1.004  (per-frame scale around the focus)
//   zoomexp  float      default 1.0    (exponent applied to the radial scale)
//   warp     float      default 0.011  (spherical pinch strength)
//   decay    float      default 0.98   (multiplicative fade per frame)
//   aspect   float      default 16/9   (width/height, for x-axis aspect)
//   pre      vec2       default (-0.8889, 0.5)  (offset taking uv to the focus-centred
//                                       y-up frame: (-0.5*aspect - fx, 0.5 - fy))
//   rotmap   vec4       default (1/aspect, 0, 0, -1)  (the rotation, squash and the
//                                       return to uv as one 2x2, row-major)
//   post     vec2       default (0.5, 0.5)  (the roam translate and the focus, in uv)
// The focus (cx, cy), rotation, sx/sy and dx/dy of the other warp fragments are
// folded into pre/rotmap/post by main.lua once a frame (warp_default_uniforms),
// so the pixel pays one length, one divide and a 2x2 instead of the whole chain.

precision highp float;

varying vec2 uv;

uniform float zoom;
uniform float zoomexp;
uniform float warp;
uniform float decay;
uniform float aspect;
uniform vec2 pre;
uniform vec4 rotmap;
uniform vec2 post;

uniform sampler2D prev;

void main() {
    // y-up Cartesian about the focus, x axis aspect-corrected
    vec2 q = vec2(uv.x * aspect + pre.x, pre.y - uv.y);
    float r = length(q);

    // zoom: radial scale around the focus (MilkDrop spec: zoom 1.0 = no zoom);
    // zoomexp bends that zoom's curvature (spec: 1 = normal), so 1.0/1.0 is the
    // identity and the scale applied here is zoom * r^zoomexp / r. Then the
    // spherical pinch: the classic MilkDrop 'warp' term pushes uv outward from
    // the focus with a 1/(r+eps) falloff, q += warp * q / (r + 0.02), computed
    // analytically per pixel. Both are scalings of q, so they share one multiply.
    float s = zoom;
    if (zoomexp != 1.0) {
        s *= pow(max(r, 1e-6), zoomexp) / (r + 1e-6);
    }
    q *= s * (1.0 + warp / (r + 0.02));

    // rotation, squash/stretch, roam translate and the way back to uv space
    vec2 wuv = vec2(dot(rotmap.xy, q), dot(rotmap.zw, q)) + post;

    // canonical decay: sample prev at the warped uv and fade it
    vec3 col = texture2D(prev, wuv).rgb * decay;
    gl_FragColor = vec4(col, 1.0);
}
