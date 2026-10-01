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
//   gamma       float      default 1.0    (exposure, pow)
//   bright      float      default 1.0    (linear gain)
//   contrast    float      default 1.0    (1.0 = none; >1 pushes toward 0/1)
//   saturation  float      default 1.0    (1.0 = none; 0 = gray)
//   hue         float      default 0.0    (hue rotation, radians)
//   echo        float      default 0.0    (additive self-blend: ret + ret*echo)

precision highp float;

varying vec2 uv;

uniform sampler2D fb;
uniform float gamma;
uniform float bright;
uniform float contrast;
uniform float saturation;
uniform float hue;
uniform float echo;

void main() {
    vec3 col = texture2D(fb, uv).rgb;

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
    float c = cos(hue);
    float sn = sin(hue);
    float y = dot(col, vec3(0.299, 0.587, 0.114));
    float i = dot(col, vec3(0.596, -0.274, -0.322));
    float q = dot(col, vec3(0.211, -0.523, 0.312));
    float i2 = i * c - q * sn;
    float q2 = i * sn + q * c;
    col = vec3(
        y + 0.956 * i2 + 0.621 * q2,
        y - 0.272 * i2 - 0.647 * q2,
        y - 1.106 * i2 + 1.703 * q2);

    // echo: additive self-blend (MilkDrop's video-echo term, bounded)
    col += col * echo;

    gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
