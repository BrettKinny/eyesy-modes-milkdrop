// modes/milkdrop/frag/blur1.frag
// Single-pass 8-tap horizontal Gaussian gather, ported 1:1 from the
// MilkDrop2 engine blur1_ps.fx (d1..d4 offsets in texel units, w1..w4
// weights, srctexsize.zw = inverse texel). The preset's GetBlur1 macro
// reads this blurred copy (sampler_blur1) with its own scale/bias — here
// the pass itself is the blur, so scale/bias default to identity and the
// output is the weighted gather normalized by w_div.
//
// The preset's per-frame code computes w1..w4/d1..d4 from a user-chosen
// 8-tap weight row (blur1_ps.fx comment block); the defaults below are the
// engine's built-in row { 4,3.8,3.5,2.9,1.9,1.2,0.7,0.3 } unfolded:
//   w1=7.8  w2=6.4  w3=3.1  w4=1.0
//   d1=0.487  d2=3.344  d3=6.387  d4=10.0
//   w_div = 0.5/(w1+w2+w3+w4) = 1/18.6
//
// uv.y is top-down in eyesy shader space; the blur is purely horizontal in
// uv space so the y-flip is irrelevant (offsets only touch the x channel).
//
// Uniforms (draw_shader arg 5 = named, arg 6 = target samplers):
//   src          sampler2D  - source target to blur (arg 6)
//   texel        vec2       default (1/640,1/360) (1/pixel in uv space;
//                                     .x is the horizontal texel used here)
//   blur_w       vec4       default (7.8, 6.4, 3.1, 1.0)  (w1..w4 weights)
//   blur_d       vec4       default (0.487, 3.344, 6.387, 10.0) (d1..d4, texels)
//   blur_scale   float      default 1.0    (post-gain, fscale)
//   blur_bias    float      default 0.0    (post-offset, fbias)

precision highp float;

varying vec2 uv;

uniform sampler2D src;
uniform vec2 texel;
uniform vec4 blur_w;
uniform vec4 blur_d;
uniform float blur_scale;
uniform float blur_bias;

void main() {
    // tap offsets: d_k is in texels, texel is 1/pixel in uv space
    // (same semantic as the engine shader's srctexsize.zw) — use directly
    float itx = max(texel.x, 1e-6);

    // 8 taps: +d_k / -d_k in x, weighted by w_k (blur1_ps.fx body)
    vec3 blur =
        (texture2D(src, uv + vec2( blur_d.x * itx, 0.0)).rgb
       + texture2D(src, uv + vec2(-blur_d.x * itx, 0.0)).rgb) * blur_w.x +
        (texture2D(src, uv + vec2( blur_d.y * itx, 0.0)).rgb
       + texture2D(src, uv + vec2(-blur_d.y * itx, 0.0)).rgb) * blur_w.y +
        (texture2D(src, uv + vec2( blur_d.z * itx, 0.0)).rgb
       + texture2D(src, uv + vec2(-blur_d.z * itx, 0.0)).rgb) * blur_w.z +
        (texture2D(src, uv + vec2( blur_d.w * itx, 0.0)).rgb
       + texture2D(src, uv + vec2(-blur_d.w * itx, 0.0)).rgb) * blur_w.w;

    // normalize (w_div = 0.5 / sum(w)) then scale/bias (fscale/fbias)
    float w_sum = blur_w.x + blur_w.y + blur_w.z + blur_w.w;
    blur *= 0.5 / max(w_sum, 1e-6);
    blur = blur * blur_scale + blur_bias;

    gl_FragColor = vec4(blur, 1.0);
}
