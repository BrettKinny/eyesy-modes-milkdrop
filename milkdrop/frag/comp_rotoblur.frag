// modes/milkdrop/frag/comp_rotoblur.frag
// Roto-blur composite: the frame is smeared along an arc about the screen
// centre (and optionally along the radius), by a fixed-count weighted gather of
// the feedback target. Display-only: reads the feedback target and never writes
// back into it, so it cannot self-amplify (SCENE-LIBRARY design law).
//
// Construct ported from gl-transitions transitions/tangentMotionBlur.glsl
// (MIT, Author: chenkai) — multi-tap gather along a motion direction with the
// triangular weight 4*(f - f^2), plus a per-pixel jitter so a fixed tap count
// does not band. three.js examples/jsm/shaders/AfterimageShader.js (MIT) was the
// other ranked source; its damped-old-frame blend is deliberately NOT ported,
// because this engine already decays the previous frame in the warp pass, so a
// second cross-frame hold would duplicate the feedback rather than add a blur.
// Self-authored implementation; the gather direction here is rotational, which
// is what makes it a roto-blur rather than a linear one.
//
// Count: 8 taps, the ceiling set for this archetype, so this is the most
// expensive composite in the library — 8 gathers per pixel at content
// resolution. It is display-only, so it costs the same whether or not the
// scene is fast-moving.
//
// uv.y is top-down in eyesy shader space; the arc is traced in y-up Cartesian
// screen-height units, so the rotation is about the screen centre and the
// radial term is aspect-correct. That needs u_resolution, which the host binds
// on every draw (engine/src/runtime.cpp:713-719) rather than the mode passing.
//
// Uniforms (draw_shader arg 5 = named, arg 6 = target samplers):
//   fb          sampler2D - feedback target (arg 6)
//   blur_rot    float     default 0.18  (total angular sweep of the gather, radians)
//   blur_rad    float     default 0.02  (total radial sweep, fraction of the radius)
//   blur_mix    float     default 0.75  (blurred share; 0 = crisp frame, 1 = all blur)
//   gamma       float     default 1.0   (exposure, pow)
//   bright      float     default 1.0   (linear gain)
//   contrast    float     default 1.0   (1.0 = none; >1 pushes toward 0/1)
//   saturation  float     default 1.0   (1.0 = none; 0 = gray)
//   hue         float     default 0.0   (hue rotation, radians)
//   echo        float     default 0.0   (additive self-blend: ret + ret*echo)
// Host-bound, not in arg 5: u_resolution.

precision highp float;

varying vec2 uv;

uniform sampler2D fb;
uniform float blur_rot;
uniform float blur_rad;
uniform float blur_mix;
uniform float gamma;
uniform float bright;
uniform float contrast;
uniform float saturation;
uniform float hue;
uniform float echo;
uniform vec2 u_resolution;

const int TAPS = 8;

// fract(sin(dot(..))) hash: the idiom the source uses for its per-pixel offset
float hash_f(vec2 c) {
    return fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    float aspect = u_resolution.x / u_resolution.y;
    vec3 base = texture2D(fb, uv).rgb;

    // y-up Cartesian, origin at screen centre, x aspect-corrected
    vec2 p = vec2((uv.x - 0.5) * aspect, 0.5 - uv.y);

    // Per-pixel offset, so 8 discrete taps read as a smear rather than 8 ghosts.
    float jitter = hash_f(uv);

    vec3 acc = vec3(0.0);
    float total = 0.0;
    for (int i = 0; i < TAPS; i++) {
        float f = (float(i) + jitter) / float(TAPS);
        float w = 4.0 * (f - f * f);            // triangular, peaks mid-sweep
        float da = blur_rot * (f - 0.5);        // symmetric about the pixel
        float dr = blur_rad * (f - 0.5);
        float ca = cos(da);
        float sa = sin(da);
        vec2 q = p * (1.0 + dr);
        q = vec2(q.x * ca - q.y * sa, q.x * sa + q.y * ca);
        // back to y-down uv space
        vec2 suv = vec2(0.5 + q.x / aspect, 0.5 - q.y);
        acc += texture2D(fb, suv).rgb * w;
        total += w;
    }

    vec3 col = mix(base, acc / total, blur_mix);

    // exposure
    col = pow(max(col, 0.0), vec3(1.0 / max(gamma, 1e-4)));

    // linear gain
    col *= bright;

    // contrast around 0.5
    col = (col - 0.5) * max(contrast, 1e-4) + 0.5;

    // saturation: blend toward luminance (include.fx lum weights)
    float lum = dot(col, vec3(0.32, 0.49, 0.29));
    col = mix(vec3(lum), col, saturation);

    // hue rotation about the luminance axis (YIQ-style rotation)
    float ch = cos(hue);
    float sh = sin(hue);
    float y = dot(col, vec3(0.299, 0.587, 0.114));
    float pi_ = dot(col, vec3(0.596, -0.274, -0.322));
    float q_ = dot(col, vec3(0.211, -0.523, 0.312));
    float i2 = pi_ * ch - q_ * sh;
    float q2 = pi_ * sh + q_ * ch;
    col = vec3(
        y + 0.956 * i2 + 0.621 * q2,
        y - 0.272 * i2 - 0.647 * q2,
        y - 1.106 * i2 + 1.703 * q2);

    // echo: additive self-blend (MilkDrop's video-echo term, bounded)
    col += col * echo;

    gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}