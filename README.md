# Node.js v22.0.0 for BlackBerry 10

Cross-compiled Node.js v22.0.0 with OpenSSL 3.0.13 for BB10 devices (QNX ARM32). Tested on BlackBerry Passport.

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
./node -e "console.log('Hello from BB10!')"
```

You should see:
```
Hello from BB10!
```

### Using Node.js in Term49

Every time you open Term49, set the library path first:
```bash
export LD_LIBRARY_PATH=/accounts/1000/shared/misc/node:$LD_LIBRARY_PATH
alias node=/accounts/1000/shared/misc/node/node
```

Then use Node.js normally:
```bash
# Interactive REPL
node

# Run a script
node -e "console.log('Hello!')"

# Start an HTTP server
node -e "
require('http').createServer((req, res) => {
  res.end('Hello from Node.js on BB10!');
}).listen(8080, () => console.log('Server on http://localhost:8080'));
"

# File system
node -e "
const fs = require('fs');
fs.writeFileSync('/tmp/test.txt', 'Hello BB10!');
console.log(fs.readFileSync('/tmp/test.txt', 'utf8'));
"

# System info
node -e "
console.log('Node.js', process.version);
console.log('Platform:', process.platform);
console.log('Arch:', process.arch);
console.log('PID:', process.pid);
"
```

### Tip: auto-setup in Term49

Add this to your shell profile so Node.js is always available:
```bash
echo 'export LD_LIBRARY_PATH=/accounts/1000/shared/misc/node:$LD_LIBRARY_PATH' >> ~/.profile
echo 'alias node=/accounts/1000/shared/misc/node/node' >> ~/.profile
```

## What works

| Feature | Status |
|---|---|
| V8 JavaScript engine (Turbofan JIT) | Working |
| `console.log`, REPL | Working |
| `fs` (read, write, stat, readdir) | Working |
| `http` client and server | Working |
| `child_process` (execSync, spawn) | Working |
| Timers (setTimeout, setInterval) | Working |
| Promises, async/await | Working |
| Streams, Buffers | Working |
| JSON, RegExp, Math | Working |
| zlib compression | Working |
| DNS resolution (c-ares) | Working |
| `crypto` (SHA, AES, RSA, ECDH) | Working |
| `https` client (TLS 1.2/1.3) | Working |
| `tls` (TLSv1.2, TLSv1.3, ChaCha20) | Working |

## Known issues

| Issue | Details |
|---|---|
| `os.cpus()` / `os.totalmem()` | Crashes -- libuv syspage API mismatch on BB10's QNX |
| SIGBUS on sustained HTTP | ARM alignment issue in libstdc++ `std::string` under heavy load |
| No `Intl` | Built without ICU (`--without-intl`) |
| Slow startup (~466ms) | No V8 snapshot; could be ~100ms with snapshot |

## Prebuilt files

| File | Size | Description |
|---|---|---|
| `node` | 35 MB | Node.js v22.0.0 binary with OpenSSL (stripped, ARM32 ELF) |
| `libuv.so.1` | 105 KB | libuv event loop library |
| `libstdc++.so.6` | 2.0 MB | GCC 9.3.0 C++ runtime |
| `libgcc_s.so.1` | 215 KB | GCC runtime support |

All four files are required. The other dependencies (`libc.so.3`, `libsocket.so.3`, `libm.so.2`) are already on the device.

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

**Node.js patches** (`patches/node/node-v22.0.0-qnx.patch`):
- Adds QNX as a target OS in the build system (configure.py, common.gypi, gyp files)
- Fixes V8 for GCC 9.3.0: missing C++17 stdlib functions (`stoul`, `stoi`, `strtoll`, etc.), math function ambiguity (`fmod`, `copysign`), missing POSIX APIs (`SA_ONSTACK`, `execinfo.h`, `madvise`)
- Fixes GCC 9.3.0 Internal Compiler Errors in complex C++ template SFINAE patterns
- Adds QNX support to c-ares, zlib, OpenSSL, and Node.js native bindings
- Configures OpenSSL 3.0.13 for QNX (no-async, no-afalgeng, no-secure-memory, no-asm)
- Adds QNX ARM to 27 OpenSSL config header dispatch files
- Handles QNX-specific errno values, uid_t/gid_t types, missing linker flags

**libuv patches** (`patches/libuv/libuv-qnx-bb10.patch`):
- Fixes for BB10's older QNX: `futime()`/`utime()` instead of `utimensat()`, process info APIs, multicast support, `math.h` C++ linkage issue

**QNX sysroot patch** (`patches/qnx-sysroot/unique_ptr_ice_fix.patch`):
- Simplifies `unique_ptr<T[]>` SFINAE that triggers GCC 9.3.0 ICE in `strip_typedefs`

## Benchmarks (BlackBerry Passport, Snapdragon 801)

| Test | Time |
|---|---|
| Startup | 466 ms |
| 100M integer loop | 5,833 ms |
| fib(35) recursive | 570 ms |
| JSON (10K ops) | 276 ms |
| Regex (100K matches) | 114 ms |
| Buffer (100MB fill) | 246 ms |
| FS (1K write+read x1000) | 1,429 ms |

## License

Node.js is licensed under the [MIT License](https://github.com/nodejs/node/blob/main/LICENSE). Patches in this repository follow the same license.
