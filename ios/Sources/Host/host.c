/*
 * Native host for the VM translated from WebAssembly by wasm2c.
 * Implements the 61 imports of runMidlet.wasm (see docs/ios-port-feasibility.md).
 *
 * Everything the VM does runs on one thread (the "VM thread"); the UI thread
 * only pushes key events and reads the last presented frame.
 */
#include <dirent.h>
#include <execinfo.h>
#include <compression.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#include "host.h"
#include "midp.h"

struct w2c_env { int unused; };
struct w2c_wasi__snapshot__preview1 { int unused; };
typedef struct w2c_env ENV;
typedef struct w2c_wasi__snapshot__preview1 WASI;

extern const int fk_sig_count;
extern const short fk_sig_table[];

static w2c_midp M;
static ENV g_env;
static WASI g_wasi;

static char g_root[1024];
static int g_trace;
static const char *const *g_args, *const *g_environ;
static volatile int g_running;
static pthread_t g_thread;
static int g_exit_status;
static jmp_buf *g_jb;
static volatile int g_kill;
static void vm_exit(int status);
static void pump_audio(void);

/* save states: the VM is unwound (Asyncify, as the browser page did for yields)
 * at an idle point, its memory written out, and then rewound to go on */
#define ASYNC_BUF 262144
static volatile int g_save_req, g_unwinding, g_save_state;   /* g_save_state: 0 idle, 1 working, 2 ok, -1 failed */
static char g_save_path[1024];
static const char *g_restore_path;
static u32 g_data;                                           /* Asyncify buffer in the VM's memory */
static pthread_mutex_t g_savelock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_savecond = PTHREAD_COND_INITIALIZER;

#define MEM() ((uint8_t *) M.w2c_memory.data)
#define PTR(p) (MEM() + (p))
static inline void put32(u32 at, u32 v) { memcpy(PTR(at), &v, 4); }
static inline void put64(u32 at, uint64_t v) { memcpy(PTR(at), &v, 8); }
static inline u32 get32(u32 at) { u32 v; memcpy(&v, PTR(at), 4); return v; }

/* ---------------------------------------------------------------- paths */

void host_set_root(const char *dir) { snprintf(g_root, sizeof g_root, "%s", dir); }

static int hostpath(u32 wp, char *out, size_t n) {
    const char *p = (const char *) PTR(wp);
    if (p[0] == '/') snprintf(out, n, "%s%s", g_root, p);
    else snprintf(out, n, "%s", p);
    return 0;
}

/* host errno -> Linux errno (what the wasm libc expects, negated) */
static int lerr(int e) {
    switch (e) {
    case 0: return 0;
    case ENOTEMPTY: return 39;
    case ENAMETOOLONG: return 36;
    case ELOOP: return 40;
    case ENOTSUP: return 95;
    case EOVERFLOW: return 75;
    default: return e < 35 ? e : 5;
    }
}
static u32 neg(int e) { return (u32) -lerr(e); }
static u32 ret(long r) { return r < 0 ? neg(errno) : (u32) r; }

static int wasm_open_flags(u32 f) {
    int o = 0;
    switch (f & 3) { case 0: o = O_RDONLY; break; case 1: o = O_WRONLY; break; default: o = O_RDWR; }
    if (f & 0100) o |= O_CREAT;
    if (f & 0200) o |= O_EXCL;
    if (f & 01000) o |= O_TRUNC;
    if (f & 02000) o |= O_APPEND;
    if (f & 04000) o |= O_NONBLOCK;
    if (f & 0200000) o |= O_DIRECTORY;
    return o;
}

/* ---------------------------------------------------------------- events */

/* Emscripten's SDL 1.2 headers: 32-bit type (SDL2 values), 28-byte events;
 * key: type@0 state@8 scancode@12 sym@16 mod@20 unicode@24; resize: w@4 h@8 */
#define EV_SIZE 28
#define EV_MAX 512
static pthread_mutex_t g_evlock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_evcond = PTHREAD_COND_INITIALIZER;
static uint8_t g_ev[EV_MAX][EV_SIZE];
static int g_ev_head, g_ev_count;

static void ev_push(const uint8_t *e) {
    pthread_mutex_lock(&g_evlock);
    if (g_ev_count < EV_MAX) {
        memcpy(g_ev[(g_ev_head + g_ev_count) % EV_MAX], e, EV_SIZE);
        g_ev_count++;
    }
    pthread_cond_signal(&g_evcond);
    pthread_mutex_unlock(&g_evlock);
}

#define SDL_QUIT 0x100
#define SDL_KEYDOWN 0x300
#define SDL_KEYUP 0x301
#define SDL_VIDEORESIZE 0x7001

void host_key(int sym, int down) {
    if (g_trace) fprintf(stderr, "host: key %d %s\n", sym, down ? "down" : "up");
    uint8_t e[EV_SIZE] = {0};
    uint32_t type = down ? SDL_KEYDOWN : SDL_KEYUP, s = (uint32_t) sym;
    memcpy(e, &type, 4);
    e[8] = down ? 1 : 0;
    memcpy(e + 12, &s, 4);
    memcpy(e + 16, &s, 4);
    ev_push(e);
}

void host_resize(int w, int h) {
    uint8_t e[EV_SIZE] = {0};
    uint32_t type = SDL_VIDEORESIZE;
    memcpy(e, &type, 4);
    memcpy(e + 4, &w, 4);
    memcpy(e + 8, &h, 4);
    ev_push(e);
}

void host_quit(void) {
    uint8_t e[EV_SIZE] = {0};
    uint32_t type = SDL_QUIT;
    memcpy(e, &type, 4);
    ev_push(e);
}

u32 w2c_env_SDL_PushEvent(ENV *e, u32 ev) { (void) e; ev_push(PTR(ev)); return 0; }

u32 w2c_env_SDL_PollEvent(ENV *e, u32 ev) {
    (void) e;
    if (g_kill) vm_exit(0);
    pump_audio();
    int got = 0;
    pthread_mutex_lock(&g_evlock);
    if (g_ev_count > 0) {
        if (ev) memcpy(PTR(ev), g_ev[g_ev_head], EV_SIZE);
        if (g_trace) fprintf(stderr, "host: poll event type 0x%x\n", *(uint32_t *) g_ev[g_ev_head]);
        g_ev_head = (g_ev_head + 1) % EV_MAX;
        g_ev_count--;
        got = 1;
    }
    pthread_mutex_unlock(&g_evlock);
    return got;
}

/* ----------------------------------------------------------------- time */

static double now_ms(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1000.0 + t.tv_nsec / 1e6;
}
static double g_t0;
static double g_skew, g_wskew;   /* real minus virtual ms: a restored state continues its own clock */
static double vnow(void) { return now_ms() - g_skew; }
static double wall_ms(void) { struct timeval t; gettimeofday(&t, NULL); return t.tv_sec * 1000.0 + t.tv_usec / 1000.0; }

f64 w2c_env_emscripten_get_now(ENV *e) { (void) e; return vnow(); }
u32 w2c_env_SDL_GetTicks(ENV *e) { (void) e; return (u32) vnow(); }
/* The runtime menu is modal: its loop polls events and calls SDL_Delay(16) over and over, while the
 * game's own loop always goes through the idle imports (wait/yield). Several Delays in a row with none of those
 * in between mean the menu (or the fatal notice) is on screen. */
static volatile int g_delay_run;
static volatile double g_last_delay;
void w2c_env_SDL_Delay(ENV *e, u32 ms) {
    (void) e;
    g_delay_run++;
    g_last_delay = now_ms();
    usleep(ms * 1000u);
}

int host_overlay_open(void) { return g_delay_run >= 3 && now_ms() - g_last_delay < 200; }
void w2c_env_emscripten_sleep(ENV *e, u32 ms) { (void) e; usleep(ms * 1000u); }

u32 w2c_env_gettimeofday(ENV *e, u32 tv, u32 tz) {
    (void) e; (void) tz;
    double w = wall_ms() - g_wskew;
    if (tv) { put32(tv, (u32) (w / 1000.0)); put32(tv + 4, (u32) ((w - (double) (u32) (w / 1000.0) * 1000.0) * 1000.0)); }
    return 0;
}

/* the page's yield / wait (they were asyncify imports): block until an input
 * event arrives or ms have passed */
/* Common start of the two Asyncify imports: 1 = this call is a rewind resuming
 * here (nothing more to do), 2 = a save started unwinding (return at once). */
static int async_prologue(void) {
    if (g_kill) vm_exit(0);
    g_delay_run = 0;
    if (w2c_midp_asyncify_get_state(&M) == 2) {
        w2c_midp_asyncify_stop_rewind(&M);
        return 1;
    }
    if (g_trace && g_save_req) fprintf(stderr, "host: save requested, at async import, in_invoke=%d\n", g_jb != NULL);
    if (g_save_req && !g_jb) {   /* not inside invoke_v: a host frame cannot be unwound */
        g_save_req = 0;
        g_unwinding = 1;
        put32(g_data, g_data + 8);
        put32(g_data + 4, g_data + 8 + ASYNC_BUF);
        w2c_midp_asyncify_start_unwind(&M, g_data);
        return 2;
    }
    return 0;
}

void w2c_env_0x5F_asyncjs_0x5Ffk_web_yield_js(ENV *e) {
    (void) e;
    if (async_prologue()) return;
    pump_audio();
    sched_yield();
}

/* ---------------------------------------------------------------- audio
 * SDL audio as Emscripten did it: the game's callback runs on the VM's own
 * thread (the wasm instance is single threaded), at its idle points. It fills
 * a ring buffer; the app's audio engine drains it from its render thread. */
#include <stdatomic.h>
#define RING_FRAMES 32768   /* stereo frames, power of two */
static struct { int open, paused; u32 freq, channels, samples, cb, ud, stream, bytes; } g_aud;
static int16_t g_ring[RING_FRAMES * 2];
static uint64_t g_aud_pumped, g_aud_loud, g_aud_underrun, g_aud_reported;   /* J2ME_AUDIO_TRACE */
static _Atomic uint32_t g_rhead, g_rtail;   /* frames written / read */

static void pump_audio(void) {
    if (!g_aud.open || g_aud.paused || !g_aud.cb) return;
    uint32_t target = g_aud.freq / 8;                       /* ~125 ms ahead */
    for (int n = 0; n < 8; n++) {
        uint32_t head = atomic_load_explicit(&g_rhead, memory_order_relaxed);
        uint32_t tail = atomic_load_explicit(&g_rtail, memory_order_acquire);
        uint32_t fill = head - tail;
        uint32_t frames = g_aud.samples;
        if (fill >= target || RING_FRAMES - fill < frames) return;
        wasm_rt_funcref_t *f = &M.w2c_0x5F_indirect_function_table.data[g_aud.cb];
        ((void (*)(void *, u32, u32, u32)) f->func)(f->module_instance, g_aud.ud, g_aud.stream, g_aud.bytes);
        const int16_t *src = (const int16_t *) PTR(g_aud.stream);
        for (uint32_t i = 0; i < frames; i++) {
            int16_t l = src[i * g_aud.channels], r = g_aud.channels > 1 ? src[i * g_aud.channels + 1] : l;
            uint32_t at = ((head + i) & (RING_FRAMES - 1)) * 2;
            g_ring[at] = l; g_ring[at + 1] = r;
            if (l > 64 || l < -64) g_aud_loud++;
        }
        g_aud_pumped += frames;
        if (g_aud_pumped - g_aud_reported >= g_aud.freq * 2) {
            g_aud_reported = g_aud_pumped;
            if (getenv("J2ME_AUDIO_TRACE")) fprintf(stderr, "host: audio pumped %llu frames, %llu loud, %llu underruns\n",
                                                    (unsigned long long) g_aud_pumped, (unsigned long long) g_aud_loud, (unsigned long long) g_aud_underrun);
        }
        atomic_store_explicit(&g_rhead, head + frames, memory_order_release);
    }
}

/* audio thread: interleaved stereo S16 at the game's rate; silence when empty */
int host_audio_read(int16_t *dst, int frames) {
    uint32_t tail = atomic_load_explicit(&g_rtail, memory_order_relaxed);
    uint32_t head = atomic_load_explicit(&g_rhead, memory_order_acquire);
    uint32_t avail = head - tail;
    uint32_t n = (uint32_t) frames < avail ? (uint32_t) frames : avail;
    for (uint32_t i = 0; i < n; i++) {
        uint32_t at = ((tail + i) & (RING_FRAMES - 1)) * 2;
        dst[i * 2] = g_ring[at]; dst[i * 2 + 1] = g_ring[at + 1];
    }
    if (n < (uint32_t) frames) g_aud_underrun++;
    for (uint32_t i = n; i < (uint32_t) frames; i++) { dst[i * 2] = 0; dst[i * 2 + 1] = 0; }
    atomic_store_explicit(&g_rtail, tail + n, memory_order_release);
    return (int) n;
}

/* 1 while the game has an audio device open and running; *rate is its sample rate */
int host_audio_active(int *rate) {
    if (rate) *rate = (int) g_aud.freq;
    return g_aud.open && !g_aud.paused;
}

static void audio_reset(void) {
    memset(&g_aud, 0, sizeof g_aud);
    atomic_store(&g_rhead, 0);
    atomic_store(&g_rtail, 0);
}

void w2c_env_0x5F_asyncjs_0x5Ffk_web_wait_js(ENV *e, u32 ms) {
    (void) e;
    if (async_prologue()) return;
    double end = now_ms() + ms;
    for (;;) {
        pump_audio();
        double left = end - now_ms();
        if (left <= 0) break;
        double slice = (g_aud.open && !g_aud.paused && left > 4) ? 4 : left;
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        long ns = (long) (slice * 1e6);
        ts.tv_sec += ns / 1000000000L;
        ts.tv_nsec += ns % 1000000000L;
        if (ts.tv_nsec >= 1000000000L) { ts.tv_sec++; ts.tv_nsec -= 1000000000L; }
        pthread_mutex_lock(&g_evlock);
        if (g_ev_count == 0) pthread_cond_timedwait(&g_evcond, &g_evlock, &ts);
        int pending = g_ev_count;
        pthread_mutex_unlock(&g_evlock);
        if (pending) break;
    }
}

/* ---------------------------------------------------------------- video */

static pthread_mutex_t g_frlock = PTHREAD_MUTEX_INITIALIZER;
static uint32_t *g_frame;
static int g_fw, g_fh;
static size_t g_fcap;
static uint64_t g_fgen;

void w2c_env_fk_web_present(ENV *e, u32 rgba, u32 w, u32 h) {
    (void) e;
    size_t bytes = (size_t) w * h * 4;
    pthread_mutex_lock(&g_frlock);
    if (bytes > g_fcap) { free(g_frame); g_frame = malloc(bytes); g_fcap = g_frame ? bytes : 0; }
    if (g_frame) {
        memcpy(g_frame, PTR(rgba), bytes);
        g_fw = (int) w; g_fh = (int) h; g_fgen++;
    }
    pthread_mutex_unlock(&g_frlock);
}

const uint32_t *host_frame_acquire(int *w, int *h, uint64_t *gen) {
    pthread_mutex_lock(&g_frlock);
    if (!g_frame) { pthread_mutex_unlock(&g_frlock); return NULL; }
    *w = g_fw; *h = g_fh; *gen = g_fgen;
    return g_frame;
}
void host_frame_release(void) { pthread_mutex_unlock(&g_frlock); }

/* a block in the VM's memory for strings and structs the host hands back */
static u32 wmalloc(size_t n) { return w2c_midp_malloc(&M, (u32) n); }

static u32 g_videoinfo, g_errstr;

u32 w2c_env_SDL_GetVideoInfo(ENV *e) {
    (void) e;
    if (!g_videoinfo) {
        g_videoinfo = wmalloc(64);
        memset(PTR(g_videoinfo), 0, 64);
        put32(g_videoinfo + 12, 1170);   /* current_w, current_h: the desktop */
        put32(g_videoinfo + 16, 2532);
    }
    return g_videoinfo;
}

u32 w2c_env_SDL_GetError(ENV *e) {
    (void) e;
    if (!g_errstr) { g_errstr = wmalloc(8); memset(PTR(g_errstr), 0, 8); }
    return g_errstr;
}

u32 w2c_env_SDL_Init(ENV *e, u32 f) { (void) e; (void) f; return 0; }
void w2c_env_SDL_Quit(ENV *e) { (void) e; }
u32 w2c_env_SDL_NumJoysticks(ENV *e) { (void) e; return 0; }
u32 w2c_env_SDL_JoystickOpen(ENV *e, u32 i) { (void) e; (void) i; return 0; }
u32 w2c_env_SDL_JoystickEventState(ENV *e, u32 s) { (void) e; (void) s; return 0; }
void w2c_env_SDL_WM_SetCaption(ENV *e, u32 a, u32 b) { (void) e; (void) a; (void) b; }

/* SDL_AudioSpec (Emscripten's 32-bit layout): freq@0 format@4(u16) channels@6
 * silence@7 samples@8(u16) size@12 callback@16 userdata@20 */
static int g_audio_inited;
u32 w2c_env_SDL_WasInit(ENV *e, u32 f) { (void) e; return (f & 0x10) && g_audio_inited ? 0x10 : 0; }
u32 w2c_env_SDL_InitSubSystem(ENV *e, u32 f) { (void) e; if (f & 0x10) g_audio_inited = 1; return 0; }
void w2c_env_SDL_QuitSubSystem(ENV *e, u32 f) { (void) e; if (f & 0x10) g_audio_inited = 0; }

u32 w2c_env_SDL_OpenAudio(ENV *e, u32 want, u32 got) {
    (void) e;
    uint16_t format, samples;
    uint8_t channels;
    int32_t freq;
    memcpy(&freq, PTR(want), 4);
    memcpy(&format, PTR(want + 4), 2);
    channels = *PTR(want + 6);
    memcpy(&samples, PTR(want + 8), 2);
    if (format != 0x8010 || freq <= 0 || channels < 1 || channels > 2 || samples < 128) return (u32) -1;
    g_aud.freq = (u32) freq; g_aud.channels = channels; g_aud.samples = samples;
    g_aud.bytes = (u32) samples * channels * 2;
    memcpy(&g_aud.cb, PTR(want + 16), 4);
    memcpy(&g_aud.ud, PTR(want + 20), 4);
    g_aud.stream = wmalloc(g_aud.bytes);
    memset(PTR(g_aud.stream), 0, g_aud.bytes);
    memcpy(PTR(got), PTR(want), 24);
    *PTR(got + 7) = 0;
    put32(got + 12, g_aud.bytes);
    g_aud.open = 1; g_aud.paused = 1;
    atomic_store(&g_rhead, 0);
    atomic_store(&g_rtail, 0);
    return 0;
}
void w2c_env_SDL_CloseAudio(ENV *e) { (void) e; g_aud.open = 0; g_aud.paused = 1; }
void w2c_env_SDL_PauseAudio(ENV *e, u32 p) { (void) e; g_aud.paused = p ? 1 : 0; }
void w2c_env_SDL_LockAudio(ENV *e) { (void) e; }     /* same thread as the callback */
void w2c_env_SDL_UnlockAudio(ENV *e) { (void) e; }

/* ------------------------------------------------------------------ JIT */
u32 w2c_env_fk_jit_setting(ENV *e, u32 s) { (void) e; (void) s; return 0; }
void w2c_env_fk_jit_report_at_exit(ENV *e, u32 s) { (void) e; (void) s; }
u32 w2c_env_fk_jit_load(ENV *e, u32 a, u32 b, u32 c, u32 d) {
    (void) e; (void) a; (void) b; (void) c; (void) d;
    return 0;
}

/* --------------------------------------------------------- script eval */

static u32 g_args_str;

u32 w2c_env_emscripten_run_script_string(ENV *e, u32 script) {
    (void) e; (void) script;
    /* the only use: runMidlet_md.c asks for Module.arguments, joined by \x01 */
    if (!g_args_str) {
        size_t n = 1;
        for (const char *const *a = g_args; a && *a; a++) n += strlen(*a) + 1;
        g_args_str = wmalloc(n);
        char *d = (char *) PTR(g_args_str);
        *d = 0;
        for (const char *const *a = g_args; a && *a; a++) {
            if (a != g_args) *d++ = '\x01';
            size_t l = strlen(*a);
            memcpy(d, *a, l);
            d += l;
        }
        *d = 0;
    }
    return g_args_str;
}

u32 w2c_env_emscripten_run_script_int(ENV *e, u32 script) {
    (void) e;
    /* Interpreter_c.cpp: "Module.fkSig(<table index>)" */
    const char *s = (const char *) PTR(script);
    unsigned idx;
    if (sscanf(s, "Module.fkSig(%u)", &idx) == 1)
        return idx < (unsigned) fk_sig_count ? (u32) (int) fk_sig_table[idx] : (u32) -1;
    return 0;
}

void w2c_env_emscripten_run_script(ENV *e, u32 script) { (void) e; (void) script; }

/* -------------------------------------------------- exit, abort, assert */

static void vm_exit(int status) {
    g_exit_status = status;
    g_running = 0;
    pthread_exit(NULL);
}

void w2c_env_exit(ENV *e, u32 code) { (void) e; vm_exit((int) code); }
void w2c_wasi__snapshot__preview1_proc_exit(WASI *e, u32 code) { (void) e; vm_exit((int) code); }
void w2c_env_abort(ENV *e) { (void) e; fprintf(stderr, "vm: abort()\n"); abort(); }

void w2c_env_0x5F_assert_fail(ENV *e, u32 cond, u32 file, u32 line, u32 func) {
    (void) e; (void) func;
    fprintf(stderr, "vm: assertion failed: %s (%s:%u)\n", (char *) PTR(cond), (char *) PTR(file), line);
    abort();
}

/* ------------------------------------------- setjmp / longjmp (Emscripten) */

static u32 g_tempret0;
u32 w2c_env_getTempRet0(ENV *e) { (void) e; return g_tempret0; }
void w2c_env_setTempRet0(ENV *e, u32 v) { (void) e; g_tempret0 = v; }


void w2c_env_invoke_v(ENV *e, u32 idx) {
    (void) e;
    volatile u32 sp = w2c_midp_stackSave(&M);
    volatile uint32_t depth = wasm_rt_call_stack_depth;
    jmp_buf jb;
    jmp_buf *volatile prev = g_jb;
    g_jb = &jb;
    if (setjmp(jb) == 0) {
        wasm_rt_funcref_t *f = &M.w2c_0x5F_indirect_function_table.data[idx];
        ((void (*)(void *)) f->func)(f->module_instance);
    } else {
        wasm_rt_call_stack_depth = depth;
        w2c_midp_stackRestore(&M, sp);
        w2c_midp_setThrew(&M, 1, 0);
    }
    g_jb = prev;
}

void w2c_env_0x5Femscripten_throw_longjmp(ENV *e) {
    (void) e;
    if (g_jb) longjmp(*g_jb, 1);
    fprintf(stderr, "vm: longjmp without setjmp\n");
    abort();
}

/* --------------------------------------------------------------- memory */

u32 w2c_env_emscripten_memcpy_big(ENV *e, u32 dst, u32 src, u32 n) {
    (void) e;
    memmove(PTR(dst), PTR(src), n);
    return dst;
}

u32 w2c_env_emscripten_resize_heap(ENV *e, u32 want) {
    (void) e;
    uint64_t cur = M.w2c_memory.size;
    if (g_trace) fprintf(stderr, "host: resize_heap(%u) cur=%llu max=%llu\n", want, (unsigned long long) cur, (unsigned long long) M.w2c_memory.max_pages);
    if (want <= cur) return 1;
    uint64_t pages = (want - cur + 65535) / 65536;
    return wasm_rt_grow_memory(&M.w2c_memory, pages) == (uint64_t) -1 ? 0 : 1;
}

/* ---------------------------------------------------------- environment */

u32 w2c_wasi__snapshot__preview1_environ_sizes_get(WASI *e, u32 pcount, u32 pbuf) {
    (void) e;
    u32 n = 0, size = 0;
    for (const char *const *s = g_environ; s && *s; s++) { n++; size += (u32) strlen(*s) + 1; }
    put32(pcount, n);
    put32(pbuf, size);
    return 0;
}

u32 w2c_wasi__snapshot__preview1_environ_get(WASI *e, u32 penv, u32 pbuf) {
    (void) e;
    for (const char *const *s = g_environ; s && *s; s++) {
        size_t l = strlen(*s) + 1;
        memcpy(PTR(pbuf), *s, l);
        put32(penv, pbuf);
        penv += 4; pbuf += (u32) l;
    }
    put32(penv, 0);
    return 0;
}

/* ----------------------------------------------------------- file system */

static u32 wasi_err(int e) {
    switch (e) {
    case 0: return 0;
    case EBADF: return 8;
    case EINVAL: return 28;
    case ENOENT: return 44;
    case EISDIR: return 31;
    case EACCES: return 2;
    case ENOSPC: return 51;
    case EPIPE: return 64;
    default: return 29;
    }
}

/* The VM's file descriptors are indices into this table, not host fds, so a
 * saved state does not depend on which host fds the new process has free. */
#define MAXFD 256
static int g_rfd[MAXFD];
static struct { char path[1024]; int flags; } g_finfo[MAXFD];

static int rfd(u32 v) {
    if (v < 3) return (int) v;
    if (v >= MAXFD || g_rfd[v] < 0) return -1;
    return g_rfd[v];
}

#define MAX_DIRS 64
static struct { int fd; DIR *d; } g_dirs[MAX_DIRS];

static void drop_dir(int fd) {
    for (int i = 0; i < MAX_DIRS; i++)
        if (g_dirs[i].d && g_dirs[i].fd == fd) { closedir(g_dirs[i].d); g_dirs[i].d = NULL; }
}

u32 w2c_wasi__snapshot__preview1_fd_close(WASI *e, u32 fd) {
    (void) e;
    if (g_trace) fprintf(stderr, "host: close(%u)\n", fd);
    drop_dir((int) fd);
    int r = rfd(fd);
    if (r < 0) return 8;
    if (fd >= 3) g_rfd[fd] = -1;
    return close(r) < 0 ? wasi_err(errno) : 0;
}

u32 w2c_wasi__snapshot__preview1_fd_write(WASI *e, u32 fd, u32 iov, u32 cnt, u32 pn) {
    (void) e;
    u32 total = 0;
    for (u32 i = 0; i < cnt; i++) {
        u32 base = get32(iov + i * 8), len = get32(iov + i * 8 + 4);
        if (!len) continue;
        ssize_t n = write(rfd(fd), PTR(base), len);
        if (n < 0) return wasi_err(errno);
        total += (u32) n;
        if ((u32) n < len) break;
    }
    put32(pn, total);
    return 0;
}

u32 w2c_wasi__snapshot__preview1_fd_read(WASI *e, u32 fd, u32 iov, u32 cnt, u32 pn) {
    (void) e;
    u32 total = 0;
    for (u32 i = 0; i < cnt; i++) {
        u32 base = get32(iov + i * 8), len = get32(iov + i * 8 + 4);
        if (!len) continue;
        ssize_t n = read(rfd(fd), PTR(base), len);
        if (g_trace) fprintf(stderr, "host: read(%u, %u) = %zd\n", fd, len, n);
        if (n < 0) return wasi_err(errno);
        total += (u32) n;
        if ((u32) n < len) break;
    }
    put32(pn, total);
    return 0;
}

u32 w2c_wasi__snapshot__preview1_fd_seek(WASI *e, u32 fd, u32 lo, u32 hi, u32 whence, u32 pnew) {
    (void) e;
    int64_t off = (int64_t) (((uint64_t) hi << 32) | lo);
    if (g_trace && fd == 0) { void *bt[40]; int n = backtrace(bt, 40); backtrace_symbols_fd(bt, n, 2); }
    off_t r = lseek(rfd(fd), off, whence == 0 ? SEEK_SET : whence == 1 ? SEEK_CUR : SEEK_END);
    if (r < 0) { if (g_trace) fprintf(stderr, "host: seek(%u, %lld, %u) failed: %s\n", fd, (long long) off, whence, strerror(errno)); return wasi_err(errno); }
    if (g_trace) fprintf(stderr, "host: seek(%u, %lld, %u) = %lld\n", fd, (long long) off, whence, (long long) r);
    if (off == 0 && whence == 0) drop_dir((int) fd);
    put64(pnew, (uint64_t) r);
    return 0;
}

u32 w2c_env_0x5F_syscall_open(ENV *e, u32 path, u32 flags, u32 varargs) {
    (void) e;
    char p[2048];
    hostpath(path, p, sizeof p);
    int mode = varargs ? (int) get32(varargs) : 0;
    int hflags = wasm_open_flags(flags);
    int fd = open(p, hflags, mode);
    if (g_trace) fprintf(stderr, "host: open(%s, 0%o) = %d%s%s\n", p, flags, fd, fd < 0 ? " " : "", fd < 0 ? strerror(errno) : "");
    if (fd < 0) return neg(errno);
    for (int v = 3; v < MAXFD; v++) {
        if (g_rfd[v] < 0) {
            g_rfd[v] = fd;
            snprintf(g_finfo[v].path, sizeof g_finfo[v].path, "%s", p);
            g_finfo[v].flags = hflags;
            return (u32) v;
        }
    }
    close(fd);
    return (u32) -24;
}

u32 w2c_env_0x5F_syscall_fcntl64(ENV *e, u32 fd, u32 cmd, u32 varargs) {
    (void) e; (void) varargs;
    if (g_trace) fprintf(stderr, "host: fcntl(%u, %u)\n", fd, cmd);
    switch (cmd) {
    case 1: case 2: case 6: case 7: return 0;
    case 3: return ret(fcntl(rfd(fd), F_GETFL) & O_ACCMODE);
    case 4: return 0;
    default: return (u32) -28;
    }
}

u32 w2c_env_0x5F_syscall_ioctl(ENV *e, u32 fd, u32 op, u32 arg) {
    (void) e; (void) arg;
    if (g_trace) fprintf(stderr, "host: ioctl(%u, 0x%x)\n", fd, op);
    return (u32) -25;   /* ENOTTY: not a terminal */
}

static void put_stat(u32 buf, const struct stat *st) {
    memset(PTR(buf), 0, 88);   /* the VM's struct stat is 88 bytes: writing past it corrupts the caller's stack */
    put32(buf + 0, (u32) st->st_dev);
    put32(buf + 8, (u32) st->st_ino);
    u32 mode = st->st_mode & 07777;
    if (S_ISDIR(st->st_mode)) mode |= 0040000;
    else if (S_ISREG(st->st_mode)) mode |= 0100000;
    else if (S_ISLNK(st->st_mode)) mode |= 0120000;
    else if (S_ISCHR(st->st_mode)) mode |= 0020000;
    put32(buf + 12, mode);
    put32(buf + 16, (u32) st->st_nlink);
    put32(buf + 20, (u32) st->st_uid);
    put32(buf + 24, (u32) st->st_gid);
    put64(buf + 40, (uint64_t) st->st_size);
    put32(buf + 48, 4096);
    put32(buf + 52, (u32) st->st_blocks);
    put32(buf + 56, (u32) st->st_atimespec.tv_sec);
    put32(buf + 64, (u32) st->st_mtimespec.tv_sec);
    put32(buf + 72, (u32) st->st_ctimespec.tv_sec);
    put64(buf + 80, (uint64_t) st->st_ino);
}

u32 w2c_env_0x5F_syscall_fstat64(ENV *e, u32 fd, u32 buf) {
    (void) e;
    struct stat st;
    if (fstat(rfd(fd), &st) < 0) { if (g_trace) fprintf(stderr, "host: fstat(%u) failed: %s\n", fd, strerror(errno)); return neg(errno); }
    if (g_trace) fprintf(stderr, "host: fstat(%u) size=%lld\n", fd, (long long) st.st_size);
    put_stat(buf, &st);
    return 0;
}

static u32 do_stat(u32 path, u32 buf, int follow) {
    char p[2048];
    struct stat st;
    hostpath(path, p, sizeof p);
    if ((follow ? stat(p, &st) : lstat(p, &st)) < 0) {
        if (g_trace) fprintf(stderr, "host: stat(%s) failed: %s\n", p, strerror(errno));
        return neg(errno);
    }
    if (g_trace) fprintf(stderr, "host: stat(%s) size=%lld mode=%o\n", p, (long long) st.st_size, st.st_mode);
    put_stat(buf, &st);
    return 0;
}
u32 w2c_env_0x5F_syscall_stat64(ENV *e, u32 path, u32 buf) { (void) e; return do_stat(path, buf, 1); }
u32 w2c_env_0x5F_syscall_lstat64(ENV *e, u32 path, u32 buf) { (void) e; return do_stat(path, buf, 0); }
u32 w2c_env_0x5F_syscall_fstatat64(ENV *e, u32 dirfd, u32 path, u32 buf, u32 flags) {
    (void) e; (void) dirfd;
    return do_stat(path, buf, !(flags & 0x100));
}

u32 w2c_env_0x5F_syscall_faccessat(ENV *e, u32 dirfd, u32 path, u32 amode, u32 flags) {
    (void) e; (void) dirfd; (void) flags;
    char p[2048];
    hostpath(path, p, sizeof p);
    return access(p, (int) amode) < 0 ? neg(errno) : 0;
}

u32 w2c_env_0x5F_syscall_ftruncate64(ENV *e, u32 fd, u32 lo, u32 hi) {
    (void) e;
    return ftruncate(rfd(fd), (off_t) (((uint64_t) hi << 32) | lo)) < 0 ? neg(errno) : 0;
}

u32 w2c_env_0x5F_syscall_mkdir(ENV *e, u32 path, u32 mode) {
    (void) e;
    char p[2048];
    hostpath(path, p, sizeof p);
    return mkdir(p, mode) < 0 ? neg(errno) : 0;
}

u32 w2c_env_0x5F_syscall_rename(ENV *e, u32 from, u32 to) {
    (void) e;
    char a[2048], b[2048];
    hostpath(from, a, sizeof a);
    hostpath(to, b, sizeof b);
    return rename(a, b) < 0 ? neg(errno) : 0;
}

u32 w2c_env_0x5F_syscall_unlink(ENV *e, u32 path) {
    (void) e;
    char p[2048];
    hostpath(path, p, sizeof p);
    return unlink(p) < 0 ? neg(errno) : 0;
}

/* linux_dirent64: ino u64, off i64, reclen u16, type u8, name; 280 bytes each */
u32 w2c_env_0x5F_syscall_getdents64(ENV *e, u32 fd, u32 dirp, u32 count) {
    (void) e;
    DIR *d = NULL;
    for (int i = 0; i < MAX_DIRS; i++) if (g_dirs[i].d && g_dirs[i].fd == (int) fd) d = g_dirs[i].d;
    if (!d && rfd(fd) < 0) return (u32) -9;
    if (!d) {
        int dupfd = dup(rfd(fd));
        if (dupfd < 0) return neg(errno);
        d = fdopendir(dupfd);
        if (!d) { close(dupfd); return neg(errno); }
        int slot = -1;
        for (int i = 0; i < MAX_DIRS; i++) if (!g_dirs[i].d) { slot = i; break; }
        if (slot < 0) { closedir(d); return (u32) -24; }
        g_dirs[slot].fd = (int) fd; g_dirs[slot].d = d;
    }
    u32 pos = 0;
    struct dirent *de;
    while (pos + 280 <= count && (de = readdir(d)) != NULL) {
        memset(PTR(dirp + pos), 0, 280);
        put64(dirp + pos, (uint64_t) de->d_ino);
        put64(dirp + pos + 8, (uint64_t) (pos + 280));
        memcpy(PTR(dirp + pos + 16), &(uint16_t){280}, 2);
        *PTR(dirp + pos + 18) = de->d_type == DT_DIR ? 4 : de->d_type == DT_LNK ? 10 : 8;
        strncpy((char *) PTR(dirp + pos + 19), de->d_name, 255);
        pos += 280;
    }
    return pos;
}

/* ----------------------------------------------------------- save states */

typedef struct {
    char magic[8];
    uint32_t version, data_ptr;
    uint64_t mem_size, pages, comp_size;
    uint32_t sp, send, sbase, g3, g4;
    uint32_t args_str, videoinfo, errstr, tempret0;
    double vnow, wall;
    uint32_t nfiles, pad;
    uint32_t aud_open, aud_paused, aud_freq, aud_channels, aud_samples, aud_cb, aud_ud, aud_stream, aud_init;
} SnapHdr;

typedef struct { uint32_t vfd; int32_t flags; int64_t off; char path[1024]; } SnapFile;

static int write_snapshot(const char *path) {
    uint64_t n = M.w2c_memory.size;
    size_t cap = (size_t) n + n / 64 + 65536;
    uint8_t *out = malloc(cap);
    if (!out) return -1;
    size_t comp = compression_encode_buffer(out, cap, M.w2c_memory.data, (size_t) n, NULL, COMPRESSION_LZ4);
    if (!comp) { free(out); return -1; }

    SnapFile files[MAXFD];
    uint32_t nf = 0;
    for (int v = 3; v < MAXFD; v++) {
        if (g_rfd[v] < 0) continue;
        files[nf].vfd = (uint32_t) v;
        files[nf].flags = g_finfo[v].flags;
        files[nf].off = lseek(g_rfd[v], 0, SEEK_CUR);
        memset(files[nf].path, 0, sizeof files[nf].path);
        snprintf(files[nf].path, sizeof files[nf].path, "%s", g_finfo[v].path);
        nf++;
    }
    SnapHdr h;
    memset(&h, 0, sizeof h);
    memcpy(h.magic, "J2MESNAP", 8);
    h.version = 2; h.data_ptr = g_data;
    h.aud_open = g_aud.open; h.aud_paused = g_aud.paused; h.aud_freq = g_aud.freq; h.aud_channels = g_aud.channels;
    h.aud_samples = g_aud.samples; h.aud_cb = g_aud.cb; h.aud_ud = g_aud.ud; h.aud_stream = g_aud.stream; h.aud_init = g_audio_inited;
    h.mem_size = n; h.pages = M.w2c_memory.pages; h.comp_size = comp;
    h.sp = M.w2c_0x5F_stack_pointer; h.send = M.w2c_0x5F_stack_end; h.sbase = M.w2c_0x5F_stack_base;
    h.g3 = M.w2c_g3; h.g4 = M.w2c_g4;
    h.args_str = g_args_str; h.videoinfo = g_videoinfo; h.errstr = g_errstr; h.tempret0 = g_tempret0;
    h.vnow = vnow(); h.wall = wall_ms() - g_wskew;
    h.nfiles = nf;

    char tmp[1100];
    snprintf(tmp, sizeof tmp, "%s.tmp", path);
    FILE *f = fopen(tmp, "wb");
    int ok = f && fwrite(&h, sizeof h, 1, f) == 1 && fwrite(files, sizeof files[0], nf, f) == nf
             && fwrite(out, 1, comp, f) == comp;
    if (f) ok = fclose(f) == 0 && ok;
    free(out);
    if (ok) ok = rename(tmp, path) == 0;
    else unlink(tmp);
    return ok ? 0 : -1;
}

static int restore_snapshot(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    SnapHdr h;
    int ok = fread(&h, sizeof h, 1, f) == 1 && memcmp(h.magic, "J2MESNAP", 8) == 0 && h.version == 2;
    SnapFile *files = NULL;
    uint8_t *comp = NULL;
    if (ok && h.nfiles <= MAXFD) {
        files = calloc(h.nfiles + 1, sizeof *files);
        ok = files && fread(files, sizeof *files, h.nfiles, f) == h.nfiles;
        comp = malloc((size_t) h.comp_size);
        ok = ok && comp && fread(comp, 1, (size_t) h.comp_size, f) == h.comp_size;
    } else ok = 0;
    fclose(f);
    if (ok && h.pages > M.w2c_memory.pages)
        ok = wasm_rt_grow_memory(&M.w2c_memory, h.pages - M.w2c_memory.pages) != (uint64_t) -1;
    if (ok) ok = M.w2c_memory.size == h.mem_size &&
        compression_decode_buffer(M.w2c_memory.data, (size_t) h.mem_size, comp, (size_t) h.comp_size, NULL, COMPRESSION_LZ4) == h.mem_size;
    free(comp);
    if (!ok) { free(files); return -1; }

    M.w2c_0x5F_stack_pointer = h.sp; M.w2c_0x5F_stack_end = h.send; M.w2c_0x5F_stack_base = h.sbase;
    M.w2c_g3 = h.g3; M.w2c_g4 = h.g4;
    g_data = h.data_ptr;
    audio_reset();
    g_aud.open = h.aud_open; g_aud.paused = h.aud_paused; g_aud.freq = h.aud_freq; g_aud.channels = h.aud_channels;
    g_aud.samples = h.aud_samples; g_aud.cb = h.aud_cb; g_aud.ud = h.aud_ud; g_aud.stream = h.aud_stream;
    g_aud.bytes = h.aud_samples * h.aud_channels * 2;
    g_audio_inited = (int) h.aud_init;
    g_args_str = h.args_str; g_videoinfo = h.videoinfo; g_errstr = h.errstr; g_tempret0 = h.tempret0;
    g_skew = now_ms() - h.vnow;
    g_wskew = wall_ms() - h.wall;
    for (uint32_t i = 0; i < h.nfiles; i++) {
        int fl = files[i].flags & ~(O_TRUNC | O_EXCL | O_CREAT);
        int fd = open(files[i].path, fl);
        if (fd < 0) { fprintf(stderr, "vm: restore: cannot reopen %s: %s\n", files[i].path, strerror(errno)); continue; }
        lseek(fd, files[i].off, SEEK_SET);
        g_rfd[files[i].vfd] = fd;
        snprintf(g_finfo[files[i].vfd].path, sizeof g_finfo[0].path, "%s", files[i].path);
        g_finfo[files[i].vfd].flags = files[i].flags;
    }
    free(files);
    return 0;
}

int host_save_state(const char *path) {
    if (!g_running) return -1;
    pthread_mutex_lock(&g_savelock);
    if (g_trace) fprintf(stderr, "host: save requested for %s\n", path);
    snprintf(g_save_path, sizeof g_save_path, "%s", path);
    g_save_state = 1;
    g_save_req = 1;
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    ts.tv_sec += 8;
    while (g_save_state == 1) {
        if (pthread_cond_timedwait(&g_savecond, &g_savelock, &ts) != 0) break;
    }
    int r = g_save_state == 2 ? 0 : -1;
    if (g_save_state == 1) { g_save_req = 0; r = -2; }   /* the game never went idle */
    g_save_state = 0;
    pthread_mutex_unlock(&g_savelock);
    return r;
}

/* ------------------------------------------------------------ VM thread */

static void *vm_thread(void *arg) {
    (void) arg;
    g_skew = g_t0 = now_ms();
    g_wskew = 0;
    g_trace = getenv("J2ME_TRACE") != NULL;
    wasm_rt_init();
    wasm2c_midp_instantiate(&M, &g_env, &g_wasi);
    int rewind = 0;
    if (g_restore_path) {
        if (restore_snapshot(g_restore_path) != 0) {
            fprintf(stderr, "vm: cannot load the saved state\n");
            g_exit_status = -1; g_running = 0;
            return NULL;
        }
        rewind = 1;
    } else {
        w2c_midp_0x5F_wasm_call_ctors(&M);
        g_data = w2c_midp_malloc(&M, ASYNC_BUF + 16);
    }
    int status;
    for (;;) {
        if (rewind) { w2c_midp_asyncify_start_rewind(&M, g_data); rewind = 0; }
        status = (int) w2c_midp_main(&M, 0, 0);
        if (!g_unwinding) break;
        /* main returned because the VM unwound itself for a save */
        g_unwinding = 0;
        w2c_midp_asyncify_stop_unwind(&M);
        int r = write_snapshot(g_save_path);
        if (g_trace) fprintf(stderr, "host: snapshot %s: %d\n", g_save_path, r);
        pthread_mutex_lock(&g_savelock);
        g_save_state = r == 0 ? 2 : -1;
        pthread_cond_broadcast(&g_savecond);
        pthread_mutex_unlock(&g_savelock);
        rewind = 1;   /* and go on where it was */
    }
    g_exit_status = status;
    g_running = 0;
    return NULL;
}

int host_start(const char *const *args, const char *const *env, const char *restore) {
    if (g_running) return -1;
    g_args = args;
    g_environ = env;
    g_restore_path = restore;
    g_args_str = g_videoinfo = g_errstr = 0;
    g_ev_head = g_ev_count = 0;
    g_jb = NULL;
    g_save_req = g_unwinding = 0;
    g_kill = 0;
    audio_reset();
    g_audio_inited = 0;
    for (int i = 0; i < MAXFD; i++) g_rfd[i] = -1;
    memset(g_dirs, 0, sizeof g_dirs);
    if (M.w2c_memory.data) wasm2c_midp_free(&M);
    memset(&M, 0, sizeof M);
    g_running = 1;
    pthread_attr_t at;
    pthread_attr_init(&at);
    pthread_attr_setstacksize(&at, 256u << 20);   /* the C interpreter recurses natively */
    int r = pthread_create(&g_thread, &at, vm_thread, NULL);
    pthread_attr_destroy(&at);
    if (r != 0) { g_running = 0; return -1; }
    pthread_detach(g_thread);
    return 0;
}

int host_running(void) { return g_running; }

/* Ends the running game (at its next event poll or idle point). */
int host_stop(void) {
    g_kill = 1;
    for (int i = 0; i < 300 && g_running; i++) usleep(10000);
    g_kill = 0;
    return g_running ? -1 : 0;
}
