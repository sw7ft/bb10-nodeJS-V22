set(CMAKE_SYSTEM_NAME QNX)
set(CMAKE_SYSTEM_PROCESSOR armv7)

set(CMAKE_C_COMPILER /root/qnx800/bin/arm-blackberry-qnx8eabi-gcc)
set(CMAKE_CXX_COMPILER /root/qnx800/bin/arm-blackberry-qnx8eabi-g++)
set(CMAKE_AR /root/qnx800/bin/arm-blackberry-qnx8eabi-ar)
set(CMAKE_LINKER /root/qnx800/bin/arm-blackberry-qnx8eabi-ld)

set(CMAKE_SYSROOT /root/qnx800/arm-blackberry-qnx8eabi)
set(CMAKE_FIND_ROOT_PATH /root/qnx800/arm-blackberry-qnx8eabi)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

set(CMAKE_C_FLAGS_INIT "-D_QNX_SOURCE")
set(CMAKE_CXX_FLAGS_INIT "-D_QNX_SOURCE")
set(CMAKE_EXE_LINKER_FLAGS_INIT "-lsocket -lm")
