#!/bin/bash
set -e

# Build Node.js v22.0.0 for BlackBerry 10 (QNX ARM32)
# Requires: QNX toolchain at /root/qnx800/, host gcc-multilib, Python 3, CMake

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
WORK_DIR="${WORK_DIR:-/root/node-qnx}"
QNX_ROOT="${QNX_ROOT:-/root/qnx800}"
NODE_VERSION="22.0.0"
NPROC=$(nproc)

echo "=== Node.js $NODE_VERSION for QNX ARM32 ==="
echo "Work dir: $WORK_DIR"
echo "QNX root: $QNX_ROOT"
echo ""

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# --- Download Node.js source ---
if [ ! -d "node-v${NODE_VERSION}" ]; then
    echo ">>> Downloading Node.js v${NODE_VERSION}..."
    wget -q "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}.tar.gz"
    tar xzf "node-v${NODE_VERSION}.tar.gz"
fi

# --- Clone libuv ---
if [ ! -d "libuv" ]; then
    echo ">>> Cloning libuv..."
    git clone https://github.com/libuv/libuv.git
fi

# --- Apply patches ---
echo ">>> Applying libuv patches..."
cd libuv
git checkout -- . 2>/dev/null || true
git apply "$REPO_DIR/patches/libuv/libuv-qnx-bb10.patch"
cd ..

echo ">>> Applying Node.js patches..."
cd "node-v${NODE_VERSION}"
patch -p1 --forward < "$REPO_DIR/patches/node/node-v22.0.0-qnx.patch" || true
cd ..

echo ">>> Applying QNX sysroot patches..."
echo "NOTE: You must manually apply patches/qnx-sysroot/unique_ptr_ice_fix.patch"
echo "      to $QNX_ROOT/include/libstdc++/9.3.0/bits/unique_ptr.h"

# --- Build libuv (target) ---
echo ">>> Building libuv (QNX ARM32)..."
cmake -B build/libuv-build -S libuv \
    -DCMAKE_TOOLCHAIN_FILE="$REPO_DIR/scripts/toolchain-qnx-arm.cmake" \
    -DCMAKE_INSTALL_PREFIX="$WORK_DIR/build/libuv" \
    -DBUILD_TESTING=OFF -DLIBUV_BUILD_SHARED=ON
cmake --build build/libuv-build -j$NPROC
cmake --install build/libuv-build

# --- Build libuv (host, 32-bit) ---
echo ">>> Building libuv (host x86_32)..."
CC=gcc CXX=g++ cmake -B build/libuv-host-build -S libuv \
    -DCMAKE_C_FLAGS="-m32" -DCMAKE_CXX_FLAGS="-m32" \
    -DCMAKE_INSTALL_PREFIX="$WORK_DIR/build/libuv-host" \
    -DBUILD_TESTING=OFF -DLIBUV_BUILD_SHARED=OFF
cmake --build build/libuv-host-build -j$NPROC
cmake --install build/libuv-host-build

# --- Configure Node.js ---
echo ">>> Configuring Node.js..."
cd "node-v${NODE_VERSION}"

export CC="$QNX_ROOT/bin/arm-blackberry-qnx8eabi-gcc"
export CXX="$QNX_ROOT/bin/arm-blackberry-qnx8eabi-g++"
export AR="$QNX_ROOT/bin/arm-blackberry-qnx8eabi-ar"
export CC_host=gcc
export CXX_host=g++
export AR_host=ar
export LINK_host=g++

python3 configure.py \
    --dest-os=qnx --dest-cpu=arm --cross-compiling \
    --without-ssl --without-intl \
    --shared-libuv \
    --shared-libuv-libpath="$WORK_DIR/build/libuv" \
    --shared-libuv-includes="$WORK_DIR/libuv/include" \
    --without-node-snapshot --without-inspector --without-corepack

# --- Fix host libuv paths ---
echo ">>> Fixing host libuv paths..."
cd out
find . -name '*.host.mk' \
    -exec sed -i "s|$WORK_DIR/build/libuv\b|$WORK_DIR/build/libuv-host|g" {} +
sed -i "s|$WORK_DIR/build/libuv\b|$WORK_DIR/build/libuv-host|g" \
    node_js2c.host.mk 2>/dev/null || true
find . -name '*.host.mk' \
    -exec sed -i 's|libuv-host-host|libuv-host|g' {} +
cd ..

# --- Build ---
echo ">>> Building Node.js (this takes ~30 minutes)..."
export QNX_INC="$QNX_ROOT/include"
export QNX_HOST="$QNX_ROOT"
export QNX_TARGET="$QNX_ROOT"
make -j$NPROC

# --- Package ---
echo ">>> Packaging..."
DEPLOY_DIR="$WORK_DIR/deploy"
mkdir -p "$DEPLOY_DIR"
cp out/Release/node "$DEPLOY_DIR/"
"$QNX_ROOT/bin/arm-blackberry-qnx8eabi-strip" "$DEPLOY_DIR/node"
cp "$WORK_DIR/build/libuv/libuv.so.1.0.0" "$DEPLOY_DIR/libuv.so.1"
cp "$QNX_ROOT/x86_64-linux/arm-blackberry-qnx8eabi/lib64/gcc/arm-blackberry-qnx8eabi/9.3.0/libstdc++.so.6" "$DEPLOY_DIR/"
cp "$QNX_ROOT/x86_64-linux/arm-blackberry-qnx8eabi/lib64/gcc/arm-blackberry-qnx8eabi/9.3.0/libgcc_s.so.1" "$DEPLOY_DIR/"

echo ""
echo "=== BUILD COMPLETE ==="
echo "Binary: $DEPLOY_DIR/node"
ls -lh "$DEPLOY_DIR/"
