# iOS port: 64-bit feasibility spike

Question: can the phoneME VM be built 64-bit (arm64) for a native iOS app?
Method: static audit of `runtime/cldc/src/vm` (about 170k lines in `share`,
`cpu/c`, `os`). No 64-bit build was attempted (it needs a Linux container and
a JDK 7 download); the audit already settles the main question.

## Verdict

A native arm64 build of the VM is a **deep port, not a recompile**. The VM is
a 32-bit VM by construction.

## Evidence

| Finding | Where | Why it blocks |
|---|---|---|
| `LogBytesPerWord = 2` is a constant, "word" is 4 bytes everywhere | `share/utilities/GlobalDefinitions.hpp:578` | `BytesPerStackElement` (157 uses) and all frame/field layout derive from it |
| Interpreter stack and locals are `jint` slots (`g_jsp += sizeof(jint)`) | `cpu/c/Interpreter_c.cpp:544,561,2047` | an object reference does not fit in a 32-bit slot on arm64 |
| ROM image stores pointers as `int` (`OriginalMethodInfo.method`, `_rom_text_block[]`) | `share/ROM/ROMImage.hpp` | romgen emits 32-bit images; the generator would need a 64-bit layout mode |
| `intptr_t`/`uintptr_t` typedef'd to 32-bit `int` in the gcc header | `share/utilities/GlobalDefinitions_gcc.hpp:59-64` (under `NO_STDINT`) | only when `NO_STDINT` is set; shows the 32-bit assumption |
| about 50 explicit `(int)pointer` style casts in `share`, `cpu/c`, `os` | grep | each needs review |
| the working non-ARM targets are all 32-bit: linux_i386, win32, wasm32 | build scripts | no 64-bit configuration exists to start from |
| the wasm JIT and the ARM JIT cannot be used on iOS | `WasmJit_c.hpp` needs runtime wasm compile; iOS forbids JIT | C interpreter only |

## Options

**A. WKWebView shell (cheapest, recommended first).** A UIKit app hosts the
existing web build in a `WKWebView` (WebAssembly and its JIT work there), with
a native UIKit touch overlay posting key events to the page (or reusing the
page's own `#pad`, which already uses pointer events), a document picker for
jars and `.sp` files, and native storage. Keeps the wasm JIT. Risks: audio
policy, memory ceiling, no true native feel.

**B. wasm to C (w2c2 / wasm2c) inside a native app.** Translate
`runMidlet.wasm` to C, compile it with Xcode for arm64 (no JIT needed,
App Store safe). Keeps wasm32 pointers, so no VM changes. Cost: replacing the
Emscripten JavaScript imports (SDL, asyncify, file system, `fk_jit_load`) with
native code, and the VM runs interpreted (no wasm JIT).

**C. True 64-bit VM port.** Make word size 8, widen stack slots or use
compressed 32-bit heap offsets, add a 64-bit ROM layout to romgen, and audit
about 50 pointer casts plus 128 `sizeof(int/pointer)` uses. Likely months and
the highest risk; only worth it if A and B are unacceptable.

## Not verified

No 64-bit compile was run; the cast counts are grep approximations. A
`linux_c` build in an amd64 Linux container (JDK 7 needed) would give a real
error list if option C is pursued.

## Option B prototype result (wasm to C)

Done on macOS arm64 with `wabt` 1.0.42 (`wasm2c`) and the published
`runMidlet.wasm` from `origin/gh-pages` (3.2 MB):

- `wasm2c --num-outputs=8` produced about 35 MB of C in under a second.
- `clang -arch arm64 -O1` compiled all of it in about 3 s to about 5 MB of
  objects, with no errors.
- With every import stubbed, the module **links and instantiates natively**
  (64 MB linear memory, 1024 pages). The VM itself needs no source changes.

What a real port must supply (61 imports + the asyncify driver):

| Group | Imports | Host replacement |
|---|---|---|
| SDL 1.2 (video info, events, joystick, audio, ticks) | 20 | SDL2 on iOS, or a UIKit/AVAudioEngine shim (touch pad pushes `SDL_PushEvent`-style key events) |
| Web glue | `fk_web_present`, `fk_web_yield_js`, `fk_web_wait_js` | present RGB565 to a `CALayer`; yield/wait become the run-loop step |
| Asyncify | exported `asyncify_start/stop_unwind/rewind`, `get_state` | the host drives unwind/rewind where the JS glue did, or run the VM on its own thread and block there instead |
| Syscalls and WASI | `__syscall_*` (13), `fd_*`, `environ_*`, `proc_exit` | map to POSIX on the app sandbox, translating wasm32 pointers through linear memory |
| setjmp/longjmp | `invoke_v`, `_emscripten_throw_longjmp`, `get/setTempRet0` | C `setjmp`/`longjmp` |
| JIT | `fk_jit_setting`, `fk_jit_load`, `fk_jit_report_at_exit` | stubs that report "no JIT" (iOS forbids runtime code) |
| Script eval | `emscripten_run_script*` (4) | `Interpreter_c.cpp:1266` asks JS for real wasm table signatures (`Module.fkSig`): replace with `funcref` type info in wasm-rt; `runMidlet_md.c:51` needs a native equivalent |
| Misc | `exit`, `abort`, `__assert_fail`, `gettimeofday`, `emscripten_*` (now, sleep, memcpy_big, resize_heap) | trivial |

Notes for iOS: build with `WASM_RT_USE_MMAP=0` (bounds-checked memory, no 8 GB
guard-region reservation); keep `--num-outputs` split so Xcode compiles in
parallel; the wasm JIT cannot be used, so speed is that of the C interpreter
compiled natively. Not yet measured: speed, and whether asyncify rewinds
survive wasm2c (they should, it is plain wasm code).

## Option B: working prototype (`ios/`)

`ios/` is a UIKit app that runs the translated VM natively on arm64. Verified
in the iOS Simulator (iPhone 17): the bundled demo game (MotherLoad) starts,
draws its menu, and the on-screen pad works (menu navigation, OK, held
direction keys while playing). Not yet tried: other games, a real device.

Build:

    brew install wabt xcodegen
    ios/build-wasm-c.sh        # published web build -> C (ios/Generated), runtime files
    cd ios && xcodegen generate
    xcodebuild -project J2MEfun.xcodeproj -scheme J2MEfun -sdk iphonesimulator \
        -destination 'generic/platform=iOS Simulator' ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build

Layout: `Sources/Host/host.c` implements the 61 imports (events, file system
with path mapping into the app sandbox, time, setjmp/longjmp, video present);
`Sources/App/` is the UIKit app (game list, game view, touch pad, jar reader,
launcher that sets the same env/args as launchers/web). Games: drop `.jar`
files into the app's Documents/java folder.

Lessons: Emscripten's SDL 1.2 events are 28 bytes with a 32-bit type (SDL2
values: key down 0x300, up 0x301, quit 0x100, resize 0x7001; key sym at +16),
not the stock SDL 1.2 layout. The wasm's `struct stat` is 88 bytes; zeroing more corrupted the
caller's stack (symptom: a file handle turned into 0). iOS 27 requires the
UIScene lifecycle. `J2ME_TRACE=1` logs file calls.

Open: i-appli (.jam) games, in-game
runtime menu / settings, device signing, speed measurement, pointer events,
saves surviving across launches (RMS is under Application Support/j2me/rms).

## Save states (prototype, works)

Save/Load buttons in the game view. Verified in the simulator with MotherLoad:
save at 0 m, dig to 20 m, Load: back at 0 m with the tunnel gone, and the
restored game takes input and plays on. A state file is about 3.3 MB
(LZ4 of the 100 MB linear memory, mostly zeros).

How: no VM change. The wasm already carries the Asyncify unwind/rewind
exports. When a save is requested, the next call of the idle imports
(`fk_web_wait_js` / `fk_web_yield_js`, made from the main event loop, outside
`invoke_v`) starts an unwind; `main` returns with the whole call stack saved
in linear memory; the host writes memory, the wasm globals, the open files
(path, flags, offset) and its clock offset; then it rewinds and the game goes
on. Load = fresh instance, memory and globals restored, files reopened,
`asyncify_start_rewind`, call `main` again.

Needed on the host side: VM file descriptors are indices into a table (not
host fds), the VM clock is virtual (continues from the saved value), and the
game's `rms/` folder is saved with the state.

Limits: a save waits for an idle point (a game that never sleeps between
frames gets "busy, try again" after 8 s); states only fit the same wasm build
and game jar; one slot per game so far; load was tested by restarting the VM
in the same process, not yet from a cold app start.

## Sound (works, by measurement)

SDL audio as Emscripten did it: the game's callback (`fka_sdl.c`, 44100 Hz,
stereo S16, 2048 samples) runs on the VM thread at its idle points
(`pump_audio` in host.c: before each wait/yield and event poll), filling a
lock-free ring buffer about 125 ms ahead. `Sources/App/AudioOutput.swift`
drains it from an `AVAudioSourceNode` (AVAudioEngine). The wasm instance stays
single threaded, so `SDL_LockAudio` is a no-op. The audio device state is part
of the save state (version 2). Check with `J2ME_AUDIO_TRACE=1`: frames pumped,
loud frames, underruns.

Verified by counters only (I cannot listen from here): MotherLoad's menu music
produced about 20 s of non-silent audio in real time, 0 underruns, the ring
kept draining, and it went on after Save/Load (3 underruns at the load).
Not verified by ear: quality, latency of sound effects, the silent switch /
interruption handling (AVAudioSession is `.playback`, mixes with others).

## i-appli (DoJa) games

The app launches an i-appli from a folder in Documents/java holding the `.jar`,
`.jam` and optionally `.sp` (or a `.jam` with the jar's name, or the only one next
to it). `Game.swift` reads the `.jam` (Shift_JIS: AppClass, AppParam, AppVer,
SPsize, DrawArea, TargetDevice), `Launcher.swift` passes the DoJa command line
of docs/runtime-interface.md and sets the screen to the DrawArea (240x240 when
absent). The `.sp` only seeds an empty scratchpad, so later saves are kept; the
scratchpad lives in the game's `rms/` folder, which the save state includes.

Verified in the simulator with "Nekketsu High School Dodge Ball (reprint)":
title screen, input (OK starts the game), the intro, a match, and Save then
Load (state 4.2 MB) without errors. Not verified: that Load lands exactly on
the saved moment for this game, sound by ear, speed, 3D (Mascot Capsule) games.

## Import and settings (iOS app)

Import: "+" on the games list opens the Files picker (files or folders); an i-appli
(.jar + .jam, optional .sp) goes into a folder of its own, plain jars into
Documents/java. "Open in" from Files/AirDrop is declared (not tried). Swipe to delete
(removes saves too).

Settings (gear on the games list; "Game Settings" in a game's ••• menu or its context
menu): Display (scaling, smoothing, frame rate limit, FPS counter), Screen size (plain
jars), Controls (soft key codes, haptics, pad opacity), Sound (volume, MIDI synth,
quality, audio buffer, mono), System (Java heap, keep awake, save state when leaving the
app). Each can be overridden per game ("Same as app setting"). Precedence: runtime menu
choices (cfg/<game>.cfg) > the game's setting > the app's setting; changing a setting for a
game drops the matching runtime-menu choice. Changes apply the next time the game starts.

"Runtime Menu" in the ••• menu opens phoneME's own menu (Display, Controls, Sound, Debug,
Restart game, Exit) with the pad; "Restart game" relaunches the game with the new choices.
