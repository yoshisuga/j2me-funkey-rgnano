# Star Catcher (demo game)

A small original MIDP 2.0 game bundled with the app so there is something to play
(and review) without importing a jar. Source: `src/StarCatcher.java`.

Rebuild: compile with a JDK 8 `javac -source 1.3 -target 1.3` against MIDP stubs, then run the
CLDC `preverify` tool (`runtime/preverifier`) on the classes, and zip them with a manifest
(`MIDlet-1: Star Catcher, , StarCatcher`, CLDC-1.1, MIDP-2.0) into `StarCatcher.jar`.
The `.jad` must carry the jar's size in `MIDlet-Jar-Size`.
