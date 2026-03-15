# Node.js v22.0.0 for BlackBerry 10

Cross-compiled Node.js v22.0.0 with OpenSSL 3.0.13 for BB10 devices (QNX ARM32). Tested on BlackBerry Passport.

## Quick start

```bash
# Copy prebuilt/* to device, then in Term49:
cd /accounts/1000/shared/misc/node
chmod +x node
export LD_LIBRARY_PATH=/accounts/1000/shared/misc/node:$LD_LIBRARY_PATH

# IMPORTANT: use --jitless to avoid SIGBUS crashes (see Known Issues #1)
./node --jitless -e "console.log('Hello from BB10!')"
```

## Install on your BB10 device

### Prerequisites

- BB10 device with developer mode enabled
- [Term49](https://github.com/nickthecook/term49) terminal app installed
- SSH access or file transfer method (e.g. shared folder)

### Quick install

1. Download the prebuilt files from the `prebuilt/` folder (or clone this repo)

2. Copy all files from `prebuilt/` to your device:
```bash
# Via SSH (if you have SSH set up)
scp prebuilt/* user@device-ip:/accounts/1000/shared/misc/node/

# Or copy to the device's shared folder via USB/WiFi file sharing
# Place files in: Device Storage > misc > node
```

3. Open **Term49** on your BB10 device and run:
```bash
cd /accounts/1000/shared/misc/node
chmod +x node
export LD_LIBRARY_PATH=/accounts/1000/shared/misc/node:$LD_LIBRARY_PATH
./node --jitless -e "console.log('Hello from BB10!')"
```

### Recommended shell setup

Add to `~/.profile` for persistent access:
```bash
export LD_LIBRARY_PATH=/accounts/1000/shared/misc/node:$LD_LIBRARY_PATH
alias node='/accounts/1000/shared/misc/node/node --jitless'
alias npm='/accounts/1000/shared/misc/node/node --jitless /accounts/1000/shared/misc/node/lib/node_modules/npm/bin/npm-cli.js'
export HOME=/accounts/1000/shared/misc
```

### npm

npm 10.5.1 works when using `--jitless`. To set it up:

```bash
# On your host machine, extract npm from a Node.js 22.0.0 distribution:
wget https://nodejs.org/dist/v22.0.0/node-v22.0.0-linux-x64.tar.xz
tar xf node-v22.0.0-linux-x64.tar.xz node-v22.0.0-linux-x64/lib/node_modules/npm
tar cf npm-bundle.tar -C node-v22.0.0-linux-x64 lib/node_modules/npm
scp npm-bundle.tar user@device-ip:/accounts/1000/shared/misc/node/

# On the device:
cd /accounts/1000/shared/misc/node
tar xf npm-bundle.tar && rm npm-bundle.tar

# Test:
./node --jitless lib/node_modules/npm/bin/npm-cli.js --version
# 10.5.1
```

Then use npm:
```bash
cd /accounts/1000/shared/misc/myproject
npm init -y
npm install express@4
```

**Note:** Use Express 4 (not 5). Express 5 uses Unicode property regex escapes (`\p{ID_Start}`) which require ICU (see Known Issue #4).

## What works

| Feature | Status | Notes |
|---|---|---|
| V8 JavaScript engine | Working | JIT works for simple scripts; use `--jitless` for complex workloads |
| `console.log` | Working | |
| `fs` (read, write, stat, readdir) | Working | |
| `http` client and server | Working | Single requests OK; sustained load may SIGBUS (see #1) |
| `https` client (TLS 1.2/1.3) | Working | Verified against httpbin.org |
| `crypto` (SHA, AES, RSA, ECDH) | Working | OpenSSL 3.0.13+quic |
| `tls` (ChaCha20-Poly1305, AES-GCM) | Working | Full TLS 1.3 cipher suite |
| `child_process` (execSync, spawn) | Working | |
| Timers (setTimeout, setInterval) | Working | |
| Promises, async/await | Working | |
| Streams, Buffers | Working | |
| JSON, RegExp, Math | Working | |
| zlib compression | Working | |
| DNS resolution (c-ares) | Working | |
| npm install | Working | Requires `--jitless`; fetches over HTTPS |
| Express 4 | Working | With `--jitless` |

---

## Known issues

### Issue #1: SIGBUS in `std::string::_M_construct` (V8 JIT misaligned access)

**Severity:** High -- affects REPL tab-completion, npm, any heavy `require()` workload

**Symptom:**
```
Process ... (node) terminated SIGBUS code=1 fltno=5
ip=0126989c(...node@_ZNSt7__cxx1112basic_stringIcSt11char_traitsIcESaIcEE12_M_constructIPcEEvT_S7_St20forward_iterator_tag+0x9d8ae7)
ref=024a4a8c bdslot=1
Bus error (core dumped)
```

**When it happens:**
- REPL tab-completion (e.g. typing `console.` and pressing Tab)
- Loading npm (1600+ files via `require()`)
- Sustained HTTP server load (many sequential requests)
- Any workload that triggers heavy V8 JIT compilation + string allocation

**When it does NOT happen:**
- Simple `node -e "..."` one-liners
- Single HTTP request/response
- File system operations (readdir, read, write)
- `crypto` operations (hash, encrypt, sign)
- Running with `--jitless` flag

**Root cause:** V8's Turbofan JIT compiler generates ARM machine code with memory accesses that are not naturally aligned. When this JIT-compiled code interacts with `libstdc++ 9.3.0`'s `std::string::_M_construct` (which copies string data), the misaligned address causes a SIGBUS (bus error, fault number 5 = data access alignment fault) on the QNX ARM kernel. Linux ARM silently fixes up unaligned accesses in the kernel; QNX does not.

**Workaround:** Use `--jitless` flag. This disables V8's optimizing compiler and uses the interpreter only. Performance is ~2-5x slower for computation but all functionality works correctly.

```bash
./node --jitless script.js
```

**Potential fixes for future builds:**
1. **Build V8 with `-munaligned-access`** -- Tell GCC the target supports unaligned access (Cortex-A7/A15 in Passport does handle it in hardware, but QNX kernel traps it). Would need a kernel-side fix or a V8 patch to avoid unaligned stores.
2. **Patch V8's ARM code generator** to ensure all memory accesses are naturally aligned. The crash is specifically in Turbofan's `MemoryRepresentation` for string operations.
3. **Use Clang 17 instead of GCC 9.3.0** -- Clang's code generation may produce better-aligned ARM code, and its `libstdc++` interaction differs.
4. **Patch QNX kernel alignment handler** -- Enable transparent unaligned access fixup (like Linux does with `/proc/cpu/alignment`). BB10's QNX 8.0.0 may support this via `procnto` options.
5. **Replace `libstdc++ 9.3.0`** with a newer version or `libc++` that avoids the problematic `_M_construct` code path.

---

### Issue #2: `os.cpus()` and `os.totalmem()` crash

**Severity:** Medium -- only affects `os` module info queries

**Symptom:**
```
unknown symbol: _SYSPAGE_ELEMENT_SIZE
```
Followed by crash.

**Root cause:** libuv's QNX 8 support uses `_SYSPAGE_ELEMENT_SIZE` macro to read system page information (CPU count, memory). This API exists in modern QNX 8.0 SDP but is **not present** in BlackBerry 10's specific QNX 8.0.0 kernel (BB10 uses a vendor-customized QNX build from ~2013 that predates the modern QNX 8 SDP).

**Workaround:** Avoid calling `os.cpus()` and `os.totalmem()`. Other `os` methods (`os.hostname()`, `os.platform()`, `os.arch()`, `os.tmpdir()`) work fine.

**Potential fix:** Patch `libuv/src/unix/qnx.c` to use BB10-compatible syspage APIs (`SYSPAGE_ENTRY()` macro without the `_SYSPAGE_ELEMENT_SIZE` helper) or hardcode/detect CPU info via `/proc` filesystem.

---

### Issue #3: No `Intl` / Unicode property escapes

**Severity:** Medium -- affects some npm packages

**Symptom:**
```
SyntaxError: Invalid regular expression: /^[$_\p{ID_Start}]$/u: Invalid property name in character class
```

**What breaks:**
- Express 5 (uses `path-to-regexp` v8 which uses `\p{ID_Start}`)
- Any package using Unicode property regex escapes (`\p{...}`)
- `Intl.DateTimeFormat`, `Intl.NumberFormat`, etc.

**Root cause:** Built with `--without-intl` to keep the binary small and avoid cross-compiling ICU (which is ~30MB and complex to build for QNX).

**Workaround:** Use older package versions that don't use Unicode property escapes:
- Express 4 instead of Express 5
- `chalk@4` instead of `chalk@5` (also avoids ESM issue)

**Potential fix:** Cross-compile ICU for QNX ARM32 and rebuild with `--with-intl=full-icu` or `--with-intl=small-icu`. The Chromium build already has ICU compiled for QNX, so the patches exist.

---

### Issue #4: ESM-only packages fail with `require()`

**Severity:** Low -- npm ecosystem workaround exists

**Symptom:**
```
Error [ERR_REQUIRE_ESM]: require() of ES Module ... not supported.
```

**Root cause:** Many modern npm packages (Chalk v5+, node-fetch v3+, etc.) are ESM-only and cannot be loaded with `require()`. This is a Node.js ecosystem issue, not QNX-specific.

**Workaround:** Use CommonJS-compatible versions of packages, or use dynamic `import()` in `.mjs` files.

---

### Issue #5: No V8 snapshot (slow startup)

**Severity:** Low -- ~466ms startup vs ~60ms with snapshot

**Root cause:** Built with `--without-node-snapshot` because V8's `mksnapshot` tool needs to run on the target architecture. Cross-compiling a snapshot for ARM32 from x86_64 requires either QEMU user-mode emulation or a snapshot-compatible cross-build setup.

**Potential fix:** Use QEMU to run the ARM32 `mksnapshot` binary on the host during build, or generate the snapshot on the device itself.

---

### Issue #6: REPL crashes on tab-completion

**Severity:** Medium -- interactive development affected

**Symptom:** Typing a partial expression (e.g. `console.`) in the REPL and pressing Tab triggers SIGBUS. This is a specific case of Issue #1.

**Observed on device:**
```
> console.
Process 112222480 (node) terminated SIGBUS code=1 fltno=5
ip=0126989c(.../node@...std::string::_M_construct...)
ref=024a4a8c bdslot=1
Bus error (core dumped)
```

**Workaround:** Use `--jitless` for REPL sessions:
```bash
./node --jitless
```
Tab-completion works correctly in `--jitless` mode.

---

## Build configuration summary

```
Node.js:     v22.0.0
V8:          12.4.254.14 (bundled, patched for QNX)
OpenSSL:     3.0.13+quic (bundled, no-asm)
Target:      arm-blackberry-qnx8eabi (ARMv7, soft-float ABI)
Compiler:    GCC 9.3.0 (QNX cross-compiler)
libuv:       1.x (latest with QNX 8 support, patched for BB10)
Build flags: --openssl-no-asm --without-intl --without-node-snapshot
             --without-inspector --without-corepack --shared-libuv
             --cross-compiling --dest-os=qnx --dest-cpu=arm
```

## Prebuilt files

| File | Size | Description |
|---|---|---|
| `node` | 35 MB | Node.js v22.0.0 binary with OpenSSL (stripped, ARM32 ELF) |
| `libuv.so.1` | 105 KB | libuv event loop library |
| `libstdc++.so.6` | 2.0 MB | GCC 9.3.0 C++ runtime |
| `libgcc_s.so.1` | 215 KB | GCC runtime support |

All four files are required. System libraries (`libc.so.3`, `libsocket.so.3`, `libm.so.2`) are already on the device.

## Build from source

### Requirements

- x86_64 Linux host
- QNX cross-compilation toolchain (GCC 9.3.0 for `arm-blackberry-qnx8eabi`)
- Host `gcc-multilib` and `g++-multilib` (for 32-bit V8 host tools)
- Python 3, GNU Make, CMake

### Build

```bash
# 1. Apply the QNX sysroot patch (one-time)
#    Manually apply patches/qnx-sysroot/unique_ptr_ice_fix.patch
#    to $QNX_ROOT/include/libstdc++/9.3.0/bits/unique_ptr.h

# 2. Run the build script
QNX_ROOT=/root/qnx800 ./scripts/build.sh
```

The build takes ~75 minutes (OpenSSL adds significant compile time). Output goes to `$WORK_DIR/deploy/`.

### What the patches fix

**Node.js patches** (`patches/node/node-v22.0.0-qnx.patch` -- 1706 lines):
- Adds QNX as a target OS in the build system (configure.py, common.gypi, gyp files)
- Fixes V8 for GCC 9.3.0: missing C++17 stdlib functions (`stoul`, `stoi`, `strtoll`, etc.), math function ambiguity (`fmod`, `copysign`), missing POSIX APIs (`SA_ONSTACK`, `execinfo.h`, `madvise`)
- Fixes GCC 9.3.0 Internal Compiler Errors in complex C++ template SFINAE patterns (`v8-memory-span.h`)
- Adds QNX support to c-ares (no epoll, no getrandom, no pipe2), zlib (ARM CPU features), OpenSSL
- Configures OpenSSL 3.0.13 for QNX (no-async, no-afalgeng, no-secure-memory, no-asm)
- Adds QNX ARM to 27 OpenSSL config header dispatch files (these default to x86 without `__linux`)
- Handles QNX-specific errno values (`EALREADY == EBUSY`), uid_t/gid_t types, missing linker flags (`-rdynamic`, `-lbacktrace`)
- Disables V8 Ticker (causes hangs on QNX), stack traces (`SA_ONSTACK` unavailable)
- Fixes zlib ARMv8 CRC32 SIMD being included in ARMv7 builds

**libuv patches** (`patches/libuv/libuv-qnx-bb10.patch` -- 291 lines):
- `futime()`/`utime()` instead of `utimensat()` (unavailable on BB10)
- `#include <process.h>` instead of `<sys/process.h>`
- Disabled `mem_info_t` usage (BB10 syspage incompatibility)
- `procfs_mapinfo`/`DCMD_PROC_MAPINFO` for `uv_resident_set_memory` 
- Disabled source-specific multicast (no `ip_mreq_source` on BB10)
- Moved `#include <math.h>` outside `extern "C"` block in `uv.h`

**QNX sysroot patch** (`patches/qnx-sysroot/unique_ptr_ice_fix.patch`):
- Simplifies `unique_ptr<T[]>` SFINAE that triggers GCC 9.3.0 ICE in `strip_typedefs`
- Relaxes constructor/reset constraints from `__safe_conversion_raw` to `is_pointer<_Up>`

## Benchmarks (BlackBerry Passport, Snapdragon 801)

| Test | Time | Notes |
|---|---|---|
| Startup | 466 ms | No snapshot; ~60ms possible with snapshot |
| 100M integer loop | 5,833 ms | V8 JIT |
| fib(35) recursive | 570 ms | V8 JIT |
| JSON (10K parse+stringify) | 276 ms | |
| Regex (100K matches) | 114 ms | |
| Buffer (1MB alloc+fill x100) | 246 ms | |
| FS (1K write+read x1000) | 1,429 ms | |
| npm install express@4 | ~50 sec | 65 packages, over HTTPS, --jitless |
| RSA-2048 keygen | ~2 sec | |

## Future work

- [ ] Fix SIGBUS: investigate V8 ARM alignment or QNX kernel alignment handler
- [ ] Add ICU for full `Intl` and Unicode regex support
- [ ] V8 snapshot for faster startup
- [ ] Inspector support for debugging
- [ ] Test `worker_threads`, `cluster` modules
- [ ] Investigate building with Clang 17 instead of GCC 9.3.0

## License

Node.js is licensed under the [MIT License](https://github.com/nodejs/node/blob/main/LICENSE). Patches in this repository follow the same license.
