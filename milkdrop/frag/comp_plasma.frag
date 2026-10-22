// modes/milkdrop/frag/comp_plasma.frag
// Interference-field composite: four overlapping sine layers — horizontal,
// diagonal, and two radial around orbiting centres — summed into one smooth
// 0..1 field, which then lifts the scene and veils it in light. Display-only:
// reads the feedback target through its sampler and never writes back into it,
// so it cannot self-amplify (SCENE-LIBRARY design law).
//
// Construct ported from maravexa/hyprsaver shaders/plasma.frag (MIT, Copyright
// (c) 2026 Mara Vexa), which is the classic plasma family 0.5+0.5*sin(sum of
// incommensurable harmonic terms). Self-authored implementation, not a copy:
// hyprsaver's palette() is host-injected there and is NOT ported — the field
// drives a two-stop ramp defined here — and the field modulates the scene
// rather than replacing it, because a composite pass has to composite the
// warped feedback rather than erase it. No samplers beyond fb, so the cost is
// 4 sin + 2 length + 1 detail sin per pixel.
//
// uv.y is top-down in eyesy shader space; the field is read in y-up Cartesian
// screen-height units, the space the source itself uses
// (uv = (fragCoord - 0.5*resolution)/resolution.y), so both radial layers stay
// circles instead of ellipses at 16:9. That needs u_resolution, which the host
// binds on every draw (engine/src/runtime.cpp:713-719) rather than the mode
// passing it.
//
// Uniforms (draw_shader arg 5 = named, arg 6 = target samplers):
//   fb            sampler2D - feedback target (arg 6)
//   plasma_scale  float     default 1.0  (spatial frequency multiplier)
//   plasma_speed  float     default 1.0  (time rate; negative runs it backwards)
//   plasma_lift   float     default 0.6  (how hard the field drives the scene)
//   plasma_glow   float     default 0.25 (quantity of veil light added)
//   inv_gamma    float     default 1.0   (1 / gamma: the exposure power)
//   tone_r/g/b   vec3      default (1,0,0) (0,1,0) (0,0,1)  rows of the tone matrix
//   tone_o       vec3      default (0,0,0)  (offset). Bright, contrast, saturation,
//                hue and echo are one affine map, built once a frame in
//                main.lua (tone_uniforms), so the pixel pays three dots
// Host-bound, not in arg 5: u_resolution, u_time.

precision highp float;

varying vec2 uv;

uniform sampler2D fb;
uniform float plasma_scale;
uniform float plasma_speed;
uniform float plasma_lift;
uniform float plasma_glow;
uniform float inv_gamma;
uniform vec3 tone_r;
uniform vec3 tone_g;
uniform vec3 tone_b;
uniform vec3 tone_o;
uniform vec2 u_resolution;
uniform float u_time;

const float TAU = 6.28318530718;

// sin mapped onto 0..1 — the source's `wave()` construct
float wave(float x) {
    return sin(x) * 0.5 + 0.5;
}

void main() {
    // y-up Cartesian, centred, in screen-height units (aspect-corrected)
    vec2 p = vec2((uv.x - 0.5) * (u_resolution.x / u_resolution.y), 0.5 - uv.y);
    float t = u_time * plasma_speed;
    float k = plasma_scale;

    // Four layers at incommensurable frequencies, so the pattern never visibly
    // repeats; the two radial centres orbit rather than sit still.
    float v1 = wave(p.x * 6.2 * k + t * 0.7);
    float v2 = wave((p.x * 3.4 + p.y * 4.6) * k - t * 1.1);
    vec2 c3 = vec2(sin(t * 0.41) * 0.30, cos(t * 0.37) * 0.20);
    float v3 = wave(length(p - c3) * 9.4 * k - t * 1.9);
    vec2 c4 = vec2(cos(t * 0.29) * 0.25, sin(t * 0.53) * 0.15);
    float v4 = wave(length(p - c4) * 6.6 * k + t * 1.3);

    // The average is already smooth and inside 0..1; a second harmonic riding
    // the coarse field adds the fine detail.
    float coarse = (v1 + v2 + v3 + v4) * 0.25;
    float field = clamp(coarse + wave(coarse * TAU * 2.0 + t * 0.3) * 0.15, 0.0, 1.0);

    // brighter near the crests (the source's brightness modulation)
    float crest = 0.7 + 0.3 * sin(field * TAU * 3.0 + t * 0.5);

    // two-stop ramp standing in for the source's host-injected palette()
    vec3 tint = mix(vec3(0.35, 0.55, 1.00), vec3(1.00, 0.72, 0.35), field);

    vec3 base = texture2D(fb, uv).rgb;
    vec3 col = base * (1.0 + plasma_lift * field) + tint * (plasma_glow * field * crest);

    // exposure: the feedback target is unsigned, so no max() before the pow
    col = pow(col, vec3(inv_gamma));

    // bright, contrast, saturation, hue and echo, folded into one matrix
    col = vec3(dot(tone_r, col), dot(tone_g, col), dot(tone_b, col)) + tone_o;

    gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}