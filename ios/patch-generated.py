# Post-processes the wasm2c output (run by build-wasm-c.sh; safe to run twice).
# Thread.sleep(negative): a game computes "frame time minus work time" and on a slower
# device that goes negative. The VM throws IllegalArgumentException, which the game shows as
# an error. Treat a negative value as 0 (return at once), as a phone with a fast CPU would.
import glob, sys
gen = sys.argv[1]
old = """  var_l4 = var_j0;
  var_j1 = 0ull;
  var_i0 = (u64)((s64)var_j0 < (s64)var_j1);
  if (var_i0) {
    var_i0 = 1507876u;"""
new = """  if ((s64)var_j0 < 0) var_j0 = 0;   /* patched: negative sleep means no sleep */
  var_l4 = var_j0;
  var_j1 = 0ull;
  var_i0 = (u64)((s64)var_j0 < (s64)var_j1);
  if (var_i0) {
    var_i0 = 1507876u;"""
done = 0
for f in sorted(glob.glob(gen + "/midp_*.c")):
    s = open(f).read()
    i = s.find("void w2c_midp_Java_java_lang_Thread_sleep(w2c_midp* instance) {")
    if i < 0: continue
    if "patched: negative sleep" in s[i:i + 2500]: print("sleep patch already applied"); done = 1; continue
    j = s.find(old, i)
    if j < 0 or j - i > 2000:
        sys.exit("patch-generated: Thread.sleep body not as expected")
    open(f, "w").write(s[:j] + new + s[j + len(old):])
    print("patched Thread.sleep in", f); done = 1
if not done: sys.exit("patch-generated: Thread.sleep not found")
