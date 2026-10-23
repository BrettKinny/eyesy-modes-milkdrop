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
// Count: 6 taps. It was 8 until the October 2026 budget pass; each tap is a
// dependent gather per pixel at content resolution (about 0.55 ms on the EYESY),
// and roto-streaks needed two of them back to fit 33.3 ms. It is display-only,
// so it costs the same whether or not the scene is fast-moving.
//
// uv.y is top-down in eyesy shader space; the arc is traced in y-up Cartesian
// screen-height units, so the rotation is about the screen centre and the
// radial term is aspect-correct. The aspect arrives as a uniform, and the
// tap loop works in uv units directly, with the aspect folded into two
// per-pixel products, so a tap pays no division.
//
// Uniforms (draw_shader arg 5 = named, arg 6 = target samplers):
//   fb          sampler2D - feedback target (arg 6)
//   blur_rot    float     default 0.18  (total angular sweep of the gather, radians)
//   blur_rad    float     default 0.02  (total radial sweep, fraction of the radius)
//   blur_mix    float     default 0.75  (blurred share; 0 = crisp frame, 1 = all blur)
//   blur_step   vec2      default (0.99955, 0.0300)  (cos, sin of blur_rot / TAPS: the angle
//                         between neighbouring taps, built once a frame in main.lua)
//   blur_start  vec2      default (0.99595, -0.0899)  (cos, sin of -blur_rot / 2: the angle of the
//                         first tap before its per-pixel offset)
//   blur_dth    float     default 0.03  (blur_rot / TAPS: the per-pixel offset's angular range)
//   aspect      float     default 1.7778  (target width / height)
//   inv_gamma    float     default 1.0   (1 / gamma: the exposure power)
//   tone_r/g/b   vec3      default (1,0,0) (0,1,0) (0,0,1)  rows of the tone matrix
//   tone_o       vec3      default (0,0,0)  (offset). Bright, contrast, saturation,
//                hue and echo are one affine map, built once a frame in
//                main.lua (tone_uniforms), so the pixel pays three dots

precision highp float;

varying vec2 uv;

uniform sampler2D fb;
uniform float blur_rot;
uniform float blur_rad;
uniform float blur_mix;
uniform vec2 blur_step;
uniform vec2 blur_start;
uniform float blur_dth;
uniform float inv_gamma;
uniform vec3 tone_r;
uniform vec3 tone_g;
uniform vec3 tone_b;
uniform vec3 tone_o;
uniform float aspect;

const int TAPS = 6;

// Interleaved gradient noise (Jimenez, 2014): the per-pixel offset in [0, 1) from
// two multiplies and two fracts. The source's fract(sin(dot(..))) hash spends a
// full sin on every pixel, and this one gives the same dither.
float hash_f(vec2 c) {
    return fract(52.9829189 * fract(dot(c, vec2(0.06711056, 0.00583715))));
}

void main() {
    vec3 base = texture2D(fb, uv).rgb;

    // centred uv (y up), and the two aspect-scaled copies the rotation needs:
    // a point at (X, Y) in uv units is (X*aspect, Y) in screen-height units
    float X = uv.x - 0.5;
    float Y = 0.5 - uv.y;
    float Xa = X * aspect;
    float Ya = Y / aspect;

    // Per-pixel offset, so 6 discrete taps read as a smear rather than 6 ghosts.
    float jitter = hash_f(gl_FragCoord.xy);

    // The taps' angles are evenly spaced (blur_rot / TAPS apart), so the first
    // tap's rotation is built once and the other five rotate by the shared step.
    // That first tap sits at -blur_rot/2 plus a per-pixel offset of at most
    // blur_rot / TAPS (pi / 6 at the widest sweep): the -blur_rot/2 part comes from
    // Lua, and the small offset's cos and sin are series that are exact to 1e-6
    // there, in place of two library trig calls per pixel.
    float x = jitter * blur_dth;
    float x2 = x * x;
    float cx = 1.0 - x2 * 0.5 * (1.0 - x2 * (1.0 / 12.0) * (1.0 - x2 * (1.0 / 30.0)));
    float sx = x * (1.0 - x2 * (1.0 / 6.0) * (1.0 - x2 * 0.05 * (1.0 - x2 * (1.0 / 42.0))));
    float ca = blur_start.x * cx - blur_start.y * sx;
    float sa = blur_start.y * cx + blur_start.x * sx;
    vec3 acc = vec3(0.0);
    float total = 0.0;
    for (int i = 0; i < TAPS; i++) {
        float f = (float(i) + jitter) / float(TAPS);
        float w = 4.0 * (f - f * f);            // triangular, peaks mid-sweep
        float scale = 1.0 + blur_rad * (f - 0.5);
        float cs = ca * scale;
        float ss = sa * scale;
        // rotate and scale about the centre, back in y-down uv space
        vec2 suv = vec2(0.5 + cs * X - ss * Ya, 0.5 - ss * Xa - cs * Y);
        acc += texture2D(fb, suv).rgb * w;
        total += w;
        vec2 nx = vec2(ca * blur_step.x - sa * blur_step.y, sa * blur_step.x + ca * blur_step.y);
        ca = nx.x;
        sa = nx.y;
    }

    vec3 col = mix(base, acc / total, blur_mix);

    // exposure: the feedback target is unsigned, so no max() before the pow
    col = pow(col, vec3(inv_gamma));

    // bright, contrast, saturation, hue and echo, folded into one matrix
    col = vec3(dot(tone_r, col), dot(tone_g, col), dot(tone_b, col)) + tone_o;

    gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}