// modes/milkdrop/frag/comp_default.frag
// Display composite over the feedback target (MilkDrop2 comp_ps default
// passthrough + the engine's per-frame gamma/bright/contrast/saturation/hue
// variables). Display-only: samples the (unwarped) feedback target through
// its sampler, applies tone/color, writes the screen. No feedback loop
// here — the warp pass is the only writer to the feedback target, so this
// pass cannot self-amplify (SCENE-LIBRARY design law).
//
// uv.y is top-down in eyesy shader space; no coordinate math is needed in
// this pass (all sampling is identity uv), so the y-flip is irrelevant.
//
// Uniforms (draw_shader arg 5 = named, arg 6 = target samplers):
//   fb          sampler2D  - feedback target (arg 6)
//   inv_gamma    float     default 1.0   (1 / gamma: the exposure power)
//   tone_r/g/b   vec3      default (1,0,0) (0,1,0) (0,0,1)  rows of the tone matrix
//   tone_o       vec3      default (0,0,0)  (offset). Bright, contrast, saturation,
//                hue and echo are one affine map, built once a frame in
//                main.lua (tone_uniforms), so the pixel pays three dots

precision highp float;

varying vec2 uv;

uniform sampler2D fb;
uniform float inv_gamma;
uniform vec3 tone_r;
uniform vec3 tone_g;
uniform vec3 tone_b;
uniform vec3 tone_o;

void main() {
    vec3 col = texture2D(fb, uv).rgb;

    // exposure: the feedback target is unsigned, so no max() before the pow
    col = pow(col, vec3(inv_gamma));

    // bright, contrast, saturation, hue and echo, folded into one matrix
    col = vec3(dot(tone_r, col), dot(tone_g, col), dot(tone_b, col)) + tone_o;

    gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
