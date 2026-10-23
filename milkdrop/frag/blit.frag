// modes/milkdrop/frag/blit.frag
// The last pass of every frame: stretches the composite target over the screen.
// It is a plain textured copy, drawn as a shader pass instead of with the
// engine's draw_target. On engines before eyesy-platform d2f0d67 the
// draw_target upscale to 1280x720 cost about 4.2 ms more than this shader on the
// CM3+ (openFrameworks' default shader on the Pi; device headless p50, October
// 2026: docs/PERFORMANCE.md). From d2f0d67 the two are within 0.15 ms (this pass
// skips alpha blending). The picture is identical either way, because both
// stretch the target with its linear filter.
//
// uv.y is top-down in eyesy shader space, which is the target's own row order,
// so the copy needs no flip.
//
// Uniforms (draw_shader arg 6 = target samplers):
//   fb           sampler2D - the composite target

precision highp float;

varying vec2 uv;

uniform sampler2D fb;

void main() {
    gl_FragColor = vec4(texture2D(fb, uv).rgb, 1.0);
}
