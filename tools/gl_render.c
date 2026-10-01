/* Offscreen GLES2 render harness for the milkdrop mode's fragments.
 *
 * tools/check_render.py drives this: it is not meant to be run by hand, though
 * it can be. One fragment in, one PPM out, on a real driver.
 *
 * The host contract it reproduces is the engine's, from engine/src/runtime.cpp:
 *   fragment source = "precision mediump float;\n" + <body, verbatim>
 *   no #version line, so the body is compiled as GLSL ES 1.00
 *   vertex uv = position.xy / u_resolution, origin top-left (uv.y top-down)
 *   u_resolution/u_time/u_energy/u_control are set on every draw
 * plus the mode's own per-draw uniforms, which arrive as name=value words.
 *
 * Output is a P6 PPM of the rendered frame. Both it and the optional
 * GL_RENDER_DUMP_INPUT copy of the input texture are written top-down, so a
 * check can compare them directly without re-deriving the input pattern.
 *
 * usage: gl_render <fragment.frag> <out.ppm> [name=value ...]
 *
 * env:
 *   GL_RENDER_W, GL_RENDER_H   render size, default 320x180 (16:9, so aspect
 *                              handling is exercised rather than bypassed)
 *   GL_RENDER_INPUT            raw RGBA8 file for the first sampler
 *   GL_RENDER_INPUT2           raw RGBA8 file for the second sampler
 *   GL_RENDER_DUMP_INPUT       path to write the input texture as a PPM
 *   GL_RENDER_TIME             u_time, default 1.0
 *
 * exit: 0 rendered; 2 no usable EGL/GLES2; 3 the fragment did not compile or link
 */

#define _GNU_SOURCE
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_UNIFORMS 64

static int W = 320;
static int H = 180;

static void die(const char *what, int code) {
    fprintf(stderr, "gl_render: FATAL: %s\n", what);
    exit(code);
}

static char *slurp(const char *path, size_t *len) {
    FILE *f = fopen(path, "rb");
    if (!f) die("cannot open fragment", 2);
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc((size_t)n + 1);
    if (!buf || fread(buf, 1, (size_t)n, f) != (size_t)n) die("cannot read fragment", 2);
    buf[n] = 0;
    fclose(f);
    if (len) *len = (size_t)n;
    return buf;
}

static GLuint compile(GLenum type, const char *src, const char *label) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &src, NULL);
    glCompileShader(shader);
    GLint ok = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        GLchar log[8192];
        GLsizei len = 0;
        glGetShaderInfoLog(shader, sizeof log, &len, log);
        fprintf(stderr, "gl_render: %s failed to compile:\n%.*s\n", label, (int)len, log);
        exit(3);
    }
    return shader;
}

/* Deterministic input texture: a ring and eight spokes for angular structure,
 * over a diagonal ramp with an off-centre blob for asymmetry. The asymmetry is
 * deliberate — a symmetric pattern makes mirror- and direction-sensitive checks
 * pass vacuously. */
static void make_input(unsigned char *px) {
    for (int y = 0; y < H; y++) {
        for (int x = 0; x < W; x++) {
            double fx = (x + 0.5) / W, fy = (y + 0.5) / H;
            double dx = fx - 0.5, dy = fy - 0.5;
            double d = sqrt(dx * dx + dy * dy);
            double ang = atan2(dy, dx);
            double ring = 1.0 - fabs(d - 0.26) * 34.0;
            if (ring < 0.0) ring = 0.0;
            ring *= ring;
            double spoke = cos(ang * 4.0);
            if (spoke < 0.0) spoke = 0.0;
            spoke = pow(spoke, 6.0) * (1.0 - d * 1.3 > 0.0 ? 1.0 - d * 1.3 : 0.0);
            double ramp = 0.25 + 0.45 * fx + 0.12 * fy;
            double blob = 0.55 * exp(-(((fx - 0.28) * (fx - 0.28)) + ((fy - 0.32) * (fy - 0.32))) / 0.006);
            double r = ramp;
            double g = ramp - blob + 0.5 * ring;
            double b = 0.6 * ramp + 0.45 * spoke + blob;
            size_t i = ((size_t)y * W + x) * 4;
            px[i + 0] = (unsigned char)(fmin(fmax(r, 0.0), 1.0) * 255.0 + 0.5);
            px[i + 1] = (unsigned char)(fmin(fmax(g, 0.0), 1.0) * 255.0 + 0.5);
            px[i + 2] = (unsigned char)(fmin(fmax(b, 0.0), 1.0) * 255.0 + 0.5);
            px[i + 3] = 255;
        }
    }
}

static void write_ppm(const char *path, const unsigned char *px, int flip) {
    FILE *f = fopen(path, "wb");
    if (!f) die("cannot open output", 2);
    fprintf(f, "P6\n%d %d\n255\n", W, H);
    for (int y = 0; y < H; y++) {
        const unsigned char *row = px + (size_t)(flip ? H - 1 - y : y) * W * 4;
        for (int x = 0; x < W; x++) fwrite(row + x * 4, 1, 3, f);
    }
    fclose(f);
}

static void report_stats(const char *tag, const unsigned char *px) {
    double sum = 0, sumsq = 0, lo = 1e9, hi = -1e9;
    for (int i = 0; i < W * H; i++) {
        double l = (px[i * 4] + px[i * 4 + 1] + px[i * 4 + 2]) / 3.0;
        sum += l;
        sumsq += l * l;
        if (l < lo) lo = l;
        if (l > hi) hi = l;
    }
    double mean = sum / (W * H);
    printf("%s\tmin=%.2f\tmax=%.2f\tmean=%.3f\tstddev=%.3f\n", tag, lo, hi, mean,
           sqrt(sumsq / (W * H) - mean * mean));
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: gl_render <fragment.frag> <out.ppm> [name=value ...]\n");
        return 2;
    }
    const char *frag_path = argv[1];
    const char *out_path = argv[2];

    if (getenv("GL_RENDER_W")) W = atoi(getenv("GL_RENDER_W"));
    if (getenv("GL_RENDER_H")) H = atoi(getenv("GL_RENDER_H"));
    if (W < 8 || H < 8 || W > 4096 || H > 4096) die("bad render size", 2);
    double u_time = getenv("GL_RENDER_TIME") ? atof(getenv("GL_RENDER_TIME")) : 1.0;

    EGLDisplay dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (dpy == EGL_NO_DISPLAY) die("no EGL display", 2);
    EGLint major = 0, minor = 0;
    if (!eglInitialize(dpy, &major, &minor)) die("eglInitialize failed", 2);

    EGLint cfg_attr[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
                          EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
                          EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8,
                          EGL_ALPHA_SIZE, 8, EGL_NONE };
    EGLConfig cfg;
    EGLint n = 0;
    if (!eglChooseConfig(dpy, cfg_attr, &cfg, 1, &n) || n < 1) die("no EGL config", 2);

    EGLint ctx_attr[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    EGLContext ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ctx_attr);
    if (ctx == EGL_NO_CONTEXT) die("no EGL context", 2);

    EGLint pb[] = { EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE };
    EGLSurface surf = eglCreatePbufferSurface(dpy, cfg, pb);
    if (surf == EGL_NO_SURFACE || !eglMakeCurrent(dpy, surf, surf, ctx)) {
        if (!eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx))
            die("neither a pbuffer nor a surfaceless context works here", 2);
    }

    const GLubyte *version = glGetString(GL_VERSION);
    const GLubyte *renderer = glGetString(GL_RENDERER);
    printf("GL_VERSION\t%s\n", version ? (const char *)version : "?");
    printf("GL_RENDERER\t%s\n", renderer ? (const char *)renderer : "?");

    /* the host's own preambles, verbatim in shape */
    const char *vsrc =
        "precision highp float;\n"
        "attribute vec4 position;\n"
        "varying vec2 uv;\n"
        "uniform vec2 u_resolution;\n"
        "void main(){ uv = position.xy / u_resolution;\n"
        "  gl_Position = vec4(position.x / u_resolution.x * 2.0 - 1.0,\n"
        "                     1.0 - position.y / u_resolution.y * 2.0, 0.0, 1.0); }";

    char *body = slurp(frag_path, NULL);
    size_t flen = strlen(body) + 64;
    char *fsrc = malloc(flen);
    snprintf(fsrc, flen, "precision mediump float;\n%s", body);

    GLuint prog = glCreateProgram();
    glAttachShader(prog, compile(GL_VERTEX_SHADER, vsrc, "vertex shader"));
    glAttachShader(prog, compile(GL_FRAGMENT_SHADER, fsrc, frag_path));
    glBindAttribLocation(prog, 0, "position");
    glLinkProgram(prog);
    GLint linked = 0;
    glGetProgramiv(prog, GL_LINK_STATUS, &linked);
    if (!linked) {
        GLchar log[8192];
        GLsizei len = 0;
        glGetProgramInfoLog(prog, sizeof log, &len, log);
        fprintf(stderr, "gl_render: link failed:\n%.*s\n", (int)len, log);
        return 3;
    }
    glUseProgram(prog);

    /* input texture (and a second, for fragments that take two) */
    unsigned char *in = malloc((size_t)W * H * 4);
    make_input(in);
    const char *in_path = getenv("GL_RENDER_INPUT");
    if (in_path && *in_path) {
        FILE *f = fopen(in_path, "rb");
        if (!f) die("cannot open GL_RENDER_INPUT", 2);
        if (fread(in, 1, (size_t)W * H * 4, f) != (size_t)W * H * 4)
            die("GL_RENDER_INPUT must hold exactly W*H*4 bytes", 2);
        fclose(f);
    }
    /* both PPMs are written top-down, so they compare directly */
    if (getenv("GL_RENDER_DUMP_INPUT")) write_ppm(getenv("GL_RENDER_DUMP_INPUT"), in, 0);

    GLuint tex, tex2 = 0;
    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_2D, tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, W, H, 0, GL_RGBA, GL_UNSIGNED_BYTE, in);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    const char *in2_path = getenv("GL_RENDER_INPUT2");
    if (in2_path && *in2_path) {
        unsigned char *in2 = malloc((size_t)W * H * 4);
        FILE *f = fopen(in2_path, "rb");
        if (!f) die("cannot open GL_RENDER_INPUT2", 2);
        if (fread(in2, 1, (size_t)W * H * 4, f) != (size_t)W * H * 4)
            die("GL_RENDER_INPUT2 must hold exactly W*H*4 bytes", 2);
        fclose(f);
        glGenTextures(1, &tex2);
        glBindTexture(GL_TEXTURE_2D, tex2);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, W, H, 0, GL_RGBA, GL_UNSIGNED_BYTE, in2);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }

    GLuint out;
    glGenTextures(1, &out);
    glBindTexture(GL_TEXTURE_2D, out);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, W, H, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    GLuint fbo;
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, out, 0);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
        die("framebuffer incomplete", 2);

    /* Uniforms. The host's own are set first; then every uniform the fragment
     * declares, samplers taking successive units and floats coming from argv.
     * vec2/vec3/vec4 are left alone beyond the two the host always provides,
     * because nothing in this library declares another one. */
    GLint res = glGetUniformLocation(prog, "u_resolution");
    if (res >= 0) glUniform2f(res, (float)W, (float)H);
    GLint tloc = glGetUniformLocation(prog, "texel");
    if (tloc >= 0) glUniform2f(tloc, 1.0f / W, 1.0f / H);
    GLint timeloc = glGetUniformLocation(prog, "u_time");
    if (timeloc >= 0) glUniform1f(timeloc, (float)u_time);

    int unit = 0, set = 0, missing = 0;
    char line[512];
    char *declared[MAX_UNIFORMS];
    int declared_count = 0;
    FILE *fp = fopen(frag_path, "r");
    if (!fp) die("cannot reopen fragment", 2);
    while (fgets(line, sizeof line, fp)) {
        char type[64], name[128];
        if (sscanf(line, " uniform %63s %127s", type, name) != 2) continue;
        size_t nl = strlen(name);
        if (nl && name[nl - 1] == ';') name[nl - 1] = 0;
        if (declared_count < MAX_UNIFORMS) declared[declared_count++] = strdup(name);
        GLint loc = glGetUniformLocation(prog, name);
        if (loc < 0) continue; /* optimised out: it is genuinely unused */
        if (strcmp(type, "sampler2D") == 0) {
            glActiveTexture(GL_TEXTURE0 + unit);
            glBindTexture(GL_TEXTURE_2D, unit == 0 || !tex2 ? tex : tex2);
            glUniform1i(loc, unit);
            unit++;
            set++;
            continue;
        }
        /* Scalars and vectors both arrive as argv words; a vector is a
         * comma-separated list, the way the mode passes blur_w = {7.8, 6.4, ...}
         * and the host fans it out to a glUniformNf call. */
        const char *raw = NULL;
        for (int a = 3; a < argc; a++) {
            char *eq = strchr(argv[a], '=');
            if (eq && (size_t)(eq - argv[a]) == strlen(name) && strncmp(argv[a], name, strlen(name)) == 0) {
                raw = eq + 1;
                break;
            }
        }
        if (!raw) {
            /* the host fills these three itself */
            if (strcmp(name, "u_time") == 0) glUniform1f(loc, (float)u_time);
            else if (strcmp(name, "u_resolution") != 0 && strcmp(name, "texel") != 0) missing++;
            set++;
            continue;
        }
        float v[4];
        int count = 0;
        char buf[256];
        snprintf(buf, sizeof buf, "%s", raw);
        for (char *tok = strtok(buf, ","); tok && count < 4; tok = strtok(NULL, ",")) v[count++] = strtof(tok, NULL);
        switch (count) {
            case 1: glUniform1f(loc, v[0]); set++; break;
            case 2: glUniform2f(loc, v[0], v[1]); set++; break;
            case 3: glUniform3f(loc, v[0], v[1], v[2]); set++; break;
            case 4: glUniform4f(loc, v[0], v[1], v[2], v[3]); set++; break;
            default: missing++; break;
        }
    }
    fclose(fp);
    printf("UNIFORMS_SET\t%d\n", set);
    printf("SAMPLERS_SET\t%d\n", unit);
    printf("UNIFORMS_MISSING\t%d\n", missing);
    for (int i = 0; i < declared_count; i++) free(declared[i]);

    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glViewport(0, 0, W, H);
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    GLfloat verts[] = { 0, 0, 0, 1, (float)W, 0, 0, 1, 0, (float)H, 0, 1,
                        (float)W, 0, 0, 1, (float)W, (float)H, 0, 1, 0, (float)H, 0, 1 };
    glVertexAttribPointer(0, 4, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), verts);
    glEnableVertexAttribArray(0);
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glFinish();

    GLenum err = glGetError();
    printf("GL_ERROR\t%d\n", (int)err);

    unsigned char *px = malloc((size_t)W * H * 4);
    glReadPixels(0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, px);
    write_ppm(out_path, px, 1);   /* glReadPixels is bottom-up */
    report_stats("STATS", px);
    report_stats("INPUT_STATS", in);
    return 0;
}