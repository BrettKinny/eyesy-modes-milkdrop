// modes/milkdrop/frag/comp_softmax.frag
// Soft-max composite: a screen blend (a + b - a*b) of the feedback target with
// a rotated, magnified gather of itself. Where comp_default just tones the
// frame, this pass folds the frame over itself, so lit structure doubles into a soft halo
// with no blur pass and no added gain inside the feedback loop.
//
// Screen is the blend algebra defined by jamieowen/glsl-blend screen.glsl
// (MIT, Copyright (c) 2015 Jamie Owen) and, at spec level, by W3C Compositing
// and Blending Level 1: screen = 1 - (1-Cb)(1-Cs). This is a self-authored
// port of the construct — no upstream file is copied — and the opacity
// overload from the same source is what carries soft_mix.
//
// Display-only: samples the feedback target through its sampler and never
// writes back into it, so the pass cannot self-amplify (SCENE-LIBRARY design
// law: the warp pass is the only writer of the feedback target).
//
// uv.y is top-down in eyesy shader space; the gather rotates about the screen
// centre in y-up Cartesian, so convert once and work in uv (0..1) from there.
// No aspect correction here: the comp pass is not given `aspect` (that uniform
// is warp-only).
//
// Uniforms (draw_shader arg 5 = named, arg 6 = target samplers):
//   fb          sampler2D  - feedback target (arg 6)
//   soft_rot    float      default 6.0    (gather rotation about the centre, degrees)
//   soft_scale  float      default 1.03   (gather scale about the centre)
//   soft_mix    float      default 0.55   (screen weight; 0 = passthrough, 1 = full)
//   inv_gamma    float     default 1.0   (1 / gamma: the exposure power)
//   tone_r/g/b   vec3      default (1,0,0) (0,1,0) (0,0,1)  rows of the tone matrix
//   tone_o       vec3      default (0,0,0)  (offset). Bright, contrast, saturation,
//                hue and echo are one affine map, built once a frame in
//                main.lua (tone_uniforms), so the pixel pays three dots

precision highp float;

varying vec2 uv;

uniform sampler2D fb;
uniform float soft_rot;
uniform float soft_scale;
uniform float soft_mix;
uniform float inv_gamma;
uniform vec3 tone_r;
uniform vec3 tone_g;
uniform vec3 tone_b;
uniform vec3 tone_o;

const float PI = 3.14159265359;

void main() {
    // y-up Cartesian, origin at screen centre: the gather rotates about it
    vec2 p = vec2(uv.x - 0.5, 0.5 - uv.y);
    float ang = soft_rot * PI / 180.0;
    float c = cos(ang);
    float sn = sin(ang);
    vec2 g = vec2(p.x * c - p.y * sn, p.x * sn + p.y * c) * soft_scale;
    vec2 guv = vec2(0.5 + g.x, 0.5 - g.y);   // back to y-down uv space

    vec3 base = texture2D(fb, uv).rgb;
    vec3 ghost = texture2D(fb, guv).rgb;

    // screen = 1 - (1-base)*(1-ghost), with the source's opacity overload:
    // screen*mix + base*(1-mix). soft_mix = 0 leaves the frame untouched.
    vec3 scr = 1.0 - (1.0 - base) * (1.0 - ghost);
    vec3 col = scr * soft_mix + base * (1.0 - soft_mix);

    // exposure: the feedback target is unsigned, so no max() before the pow
    col = pow(col, vec3(inv_gamma));

    // bright, contrast, saturation, hue and echo, folded into one matrix
    col = vec3(dot(tone_r, col), dot(tone_g, col), dot(tone_b, col)) + tone_o;

    gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}