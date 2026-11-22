# Post-processes the wasm2c output (run by build-wasm-c.sh; safe to run twice).
import glob, sys
gen = sys.argv[1]

# J2ME_TRACE=1: log every exception thrown from the VM's native code with the native call stack.
sig = "void w2c_midp_JVMThrow0x3A0x3Aallocate_and_throw0x28JVMSymbol0x2A0x2C0x20char0x2A0x2C0x20ErrorMsgTag0x29(w2c_midp* instance, u32 var_p0, u32 var_p1, u32 var_p2) {"
for f in sorted(glob.glob(gen + "/midp_*.c")):
    s = open(f).read()
    i = s.find(sig)
    if i < 0: continue
    if "host_throw_trace" in s[i:i + 400]: print("throw trace already applied"); break
    s = s[:i] + "extern void host_throw_trace(unsigned, unsigned);\n" + s[i:i + len(sig)] + "\n  host_throw_trace(var_p0, var_p1);" + s[i + len(sig):]
    open(f, "w").write(s); print("throw trace patched in", f); break
else:
    sys.exit("patch-generated: allocate_and_throw not found")
