/*
 * Native host for the VM translated from WebAssembly (ios/build-wasm-c.sh).
 * Replaces what the browser page and Emscripten's JavaScript supplied:
 * SDL 1.2 events and video, the file system, time and the setjmp/longjmp
 * trampolines. See docs/ios-port-feasibility.md.
 */
#ifndef HOST_H
#define HOST_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Directory that holds the VM's absolute paths (/midp, /game, /rms, /cfg, /tmp). */
void host_set_root(const char *dir);

/* Starts the VM on its own thread. argv/env are NULL-terminated; argv[0] is
 * not included (the VM's main takes the list as the page's Module.arguments). */
int host_start(const char *const *args, const char *const *env, const char *restore_path);

/* Ends the running game; 0 when the VM thread is gone. */
int host_stop(void);

/* Save state: blocks until the VM has reached an idle point and written the
 * file (0 ok, -1 failed, -2 the game never went idle). Load = host_start with
 * restore_path; args/env must be those of the saved game. */
int host_save_state(const char *path);

/* Input: the SDL key symbol the launcher's PHONEME_PC_KEYS maps to a phone key. */
void host_key(int sym, int down);
/* The game area changed size (pixels). */
void host_resize(int w, int h);
/* The app asks the game to end (SDL_QUIT). */
void host_quit(void);

/* Audio: the game's output as interleaved stereo S16. host_audio_active gives
 * the sample rate; host_audio_read (audio thread) fills frames, silence when empty. */
int host_audio_active(int *rate);
int host_audio_read(int16_t *dst, int frames);

/* 1 while the VM thread runs. */
int host_running(void);

/*
 * Latest frame, 32-bit RGBA (little endian, alpha 255). The pointer stays valid
 * until host_frame_release(). *gen increases with every frame the game drew.
 */
const uint32_t *host_frame_acquire(int *w, int *h, uint64_t *gen);
void host_frame_release(void);

#ifdef __cplusplus
}
#endif
#endif
