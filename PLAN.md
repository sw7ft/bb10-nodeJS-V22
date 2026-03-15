# Node.js v22 for BB10 -- Rebuild Plan (v2)

Based on the complete first build cycle: source patching, cross-compilation, deployment, testing, and issue discovery.

---

## Current state

```
Repository: github.com/sw7ft/bb10-nodeJS-V22
Binary:     Node.js v22.0.0 + OpenSSL 3.0.13+quic (35 MB stripped ARM32 ELF)
Tested on:  BlackBerry Passport (Snapdragon 801, QNX 8.0.0)
Status:     Functional with --jitless workaround for SIGBUS
```

### What works
- V8 12.4 JS engine, full crypto (SHA/AES/RSA/ECDH/HMAC), TLS 1.2/1.3
- HTTPS client, fs, http, child_process, timers, promises, streams, buffers, zlib, DNS
- npm 10.5.1 (npm install express@4 works with --jitless)

### What is broken
1. SIGBUS in V8 JIT -- crashes REPL tab-completion, npm load, sustained HTTP
2. os.cpus() / os.totalmem() -- libuv syspage API mismatch
3. No ICU -- Unicode regex fails, no Intl
4. No V8 snapshot -- 466ms startup instead of ~60ms
5. No inspector -- no --inspect debugging

---

## Toolchain

```
Host:       x86_64 Linux (Ubuntu 22.04)
GCC cross:  /root/qnx800/bin/arm-blackberry-qnx8eabi-{gcc,g++,ar} (9.3.0)
Clang alt:  /usr/lib/llvm-17/bin/clang
Sysroot:    /root/qnx800/arm-blackberry-qnx8eabi/
Host GCC:   gcc/g++ -m32 (V8 host tools ia32)
```

### Environment variables
```bash
export CC=/root/qnx800/bin/arm-blackberry-qnx8eabi-gcc
export CXX=/root/qnx800/bin/arm-blackberry-qnx8eabi-g++
export AR=/root/qnx800/bin/arm-blackberry-qnx8eabi-ar
export CC_host=gcc CXX_host=g++ AR_host=ar LINK_host=g++
export QNX_INC=/root/qnx800/include QNX_HOST=/root/qnx800 QNX_TARGET=/root/qnx800
```

---

## Phase 1: Fix SIGBUS (Priority: CRITICAL)

Without this fix, --jitless required for non-trivial workloads (2-5x slower).

### Root cause

```
Signal:   SIGBUS code=1 fltno=5 (data access alignment fault)
Location: std::string::_M_construct (libstdc++ 9.3.0)
Trigger:  V8 Turbofan JIT generates unaligned ARM memory accesses
Pattern:  ip= constant (_M_construct offset), ref= varies (heap)
```

ARM SCTLR.A bit: Linux=0 (permissive), QNX=1 (strict trap).
V8 JIT assumes unaligned OK on ARMv7+ -- true on Linux, not QNX.

### Investigation steps

1. **QNX alignment relaxation** -- check procnto -ae, SCTLR.A from userspace
2. **Userspace SIGBUS handler** -- catch, decode, emulate (ref: Linux alignment.c)
3. **V8 flags** -- check code-generator-arm.cc for kUnalignedStore/Load, try --no-turbofan
4. **Clang 17 rebuild** -- different ARM codegen, Chromium uses this without SIGBUS
5. **V8 source** -- patch MemoryRepresentation in ARM backend to force aligned ops

### Fix ranking

| Approach | Effort | Likelihood |
|---|---|---|
| V8 alignment flag/patch | Medium | High |
| QNX SCTLR.A disable | Low | Medium |
| Userspace SIGBUS fixup | High | Medium |
| Clang 17 rebuild | Medium | Medium |
| Replace libstdc++ 9.3 | High | Low |

---

## Phase 2: Add ICU (Priority: High)

Unlocks Express 5, Unicode regex, Intl API.

**Option A:** --with-intl=small-icu (bundled, ~5MB increase)
**Option B:** Chromium's pre-built ICU libs from /root/chromium/src/out/qnx-arm/

---

## Phase 3: V8 Snapshot (Priority: Medium)

Startup from ~466ms to ~60ms.

Options: QEMU user-mode, on-device mksnapshot, Chromium snapshot reference.

---

## Phase 4: Fix os.cpus()/os.totalmem() (Priority: Medium)

Patch libuv qnx.c: use SYSPAGE_ENTRY() or confstr() instead of _SYSPAGE_ELEMENT_SIZE.

---

## Phase 5: Bundle npm (Priority: Medium)

Extract lib/node_modules/npm from Node v22.0.0, ship with prebuilt.

---

## Phase 6: Inspector (Priority: Low)

Remove --without-inspector. Depends on SIGBUS fix.

---

## All patches (34 Node files, 5 libuv files, 1 sysroot)

### Node.js changes (1706 lines)

**Build system:** configure.py (QNX dest_os, arm_fpu=neon), common.gypi (defines/libs/flags), gyp_node.py (-Dhost_os), v8.gyp (no -lbacktrace)

**V8 QNX:** platform-posix.cc (MAP_LAZY, no madvise/pthread_getattr_np), memory.h (no malloc_usable_size), stack_trace_posix.cc/sampler.cc (no SA_ONSTACK), log.cc (disable Ticker), v8config.h (TARGET_OS macros=1)

**V8 GCC 9.3:** v8-memory-span.h (SFINAE), type-parser.h/string-16.cc/torque-parser.cc/civil_time.cc (stoul/stoi/strtoll shims), strings.h (cstdarg), time_zone_libc.cc (narrowing)

**V8 math:** machine-operator-reducer.cc (copysign), js-temporal-objects.cc (fmod), charconv.cc (ldexp)

**OpenSSL:** openssl_common.gypi (QNX defines), 3x gypi files (OS list), 27x config headers (dispatch)

**c-ares:** cares.gyp + config/qnx/ares_config.h (no epoll/getrandom/pipe2)

**zlib:** zlib.gyp (arm_crc32 arm64 only), cpu_features.c (QNX noop)

**Node native:** debug_utils.cc (no execinfo.h), node_credentials.cc (uid_t/gid_t), node_errors.cc (EALREADY guard), node_options-inl.h (atoll), cares_wrap.cc (AI_* flags)

### libuv changes (291 lines)
uv-common.c (errno), fs.c (futime/utime), qnx.c (APIs), udp.c (multicast), uv.h (math.h)

### Sysroot: unique_ptr.h SFINAE relaxation

---

## Benchmarks (Passport, JIT)

| Test | Time |
|---|---|
| Startup | 466 ms |
| 100M loop | 5,833 ms |
| fib(35) | 570 ms |
| JSON 10K | 276 ms |
| Regex 100K | 114 ms |
| Buffer 100MB | 246 ms |
| FS 1K x 1000 | 1,429 ms |
| RSA-2048 keygen | ~2 sec |
| npm install express@4 | ~50 sec (jitless) |

---

## Priority order

1. Fix SIGBUS (V8 ARM alignment / QNX SCTLR / Clang)
2. Add ICU (small-icu)
3. Bundle npm
4. V8 snapshot
5. Fix os.cpus()
6. Inspector
