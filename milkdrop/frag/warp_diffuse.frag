// modes/milkdrop/frag/warp_diffuse.frag
// Gray-Scott reaction-diffusion, one step per frame, running inside the feedback
// loop: the previous frame *is* the state. The feedback target carries both
// reagents — A in red, B in green and blue — so one texture holds the pair and
// the five-point Laplacian costs five fetches rather than ten.
//
// warp-bound: one clamped Gray-Scott step. A and B are each clamped to [0,1]
// every frame, so the loop cannot accumulate: the reaction replaces the field
// with a bounded function of the previous state rather than adding gain to it.
// This is the one warp archetype that does not decay, and the exception is
// declared here rather than faked with a `decay` term that would fight the
// pattern. The design law it steps outside is "the warp pass only decays, never
// adds light" (SCENE-LIBRARY); a reaction-diffusion field has no decay to express.
//
// Seeding: the mode draws waves and shapes into the feedback target *after* the
// warp, so a preset seeds the reagents by drawing with r = A and g = B. The field
// then evolves for as long as the scene runs, and the drawn waves keep feeding it.
//
// uv.y is top-down in eyesy shader space; the stencil is a plain texel offset on
// the pixel grid, so no y-up conversion is involved and the field is never warped
// — a Laplacian taken on a warped grid is not a Laplacian.
//
// Uniforms (draw_shader arg 5 = named, arg 6 = target samplers):
//   prev        sampler2D - previous frame, i.e. the current state (arg 6)
//   rd_feed     float     default 0.035 (f — feed rate of A; the name follows the model)
//   rd_kill     float     default 0.060 (k — kill rate of B)
//   rd_dt       float     default 1.0   (step size per frame)
//   rd_scale    float     default 1.0   (stencil spacing, in pixels)
//   texel       vec2      default (1/640,1/360) (1/pixel in uv space)
// Da and Db are the model's constants, not per-frame axes.

precision highp float;

varying vec2 uv;

uniform sampler2D prev;
uniform float rd_feed;
uniform float rd_kill;
uniform float rd_dt;
uniform float rd_scale;
uniform vec2 texel;

const float RD_DA = 0.16;   // diffusion rate of A
const float RD_DB = 0.08;   // diffusion rate of B; half of Da is the stable pair

void main() {
    vec2 t = texel * max(rd_scale, 0.25);

    vec3 c = texture2D(prev, uv).rgb;
    vec3 xm = texture2D(prev, uv - vec2(t.x, 0.0)).rgb;
    vec3 xp = texture2D(prev, uv + vec2(t.x, 0.0)).rgb;
    vec3 ym = texture2D(prev, uv - vec2(0.0, t.y)).rgb;
    vec3 yp = texture2D(prev, uv + vec2(0.0, t.y)).rgb;

    float A = c.r;
    float B = c.g;

    // five-point Laplacian per reagent
    float lapA = (xm.r + xp.r + ym.r + yp.r) - 4.0 * A;
    float lapB = (xm.g + xp.g + ym.g + yp.g) - 4.0 * B;

    // Gray-Scott: A is fed and consumed by the B-catalysed reaction, B is killed
    float reaction = A * B * B;
    float dA = RD_DA * lapA - reaction + rd_feed * (1.0 - A);
    float dB = RD_DB * lapB + reaction - (rd_kill + rd_feed) * B;

    float An = clamp(A + rd_dt * dA, 0.0, 1.0);
    float Bn = clamp(B + rd_dt * dB, 0.0, 1.0);

    // B is written twice so the field reads as colour without a composite trick
    gl_FragColor = vec4(An, Bn, Bn, 1.0);
}