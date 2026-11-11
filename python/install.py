#!/usr/bin/env python3
"""Install this exact TiRTC wheel pair on a supported CPython platform."""
import platform
from pathlib import Path
import subprocess
import sys
import sysconfig

def supported_platform():
    if (sys.implementation.name != "cpython" or sys.version_info < (3, 11)
            or sysconfig.get_config_var("Py_GIL_DISABLED")):
        raise RuntimeError("TiRTC requires CPython 3.11+ with the GIL")
    machine = platform.machine().lower()
    if (sys.platform, machine) not in (("darwin", "arm64"), ("linux", "x86_64")):
        raise RuntimeError("TiRTC supports only macOS arm64 and glibc Linux x86_64")
    if sys.platform == "darwin":
        version = tuple(int(value) for value in platform.mac_ver()[0].split(".")[:2])
        if version < (11, 5):
            raise RuntimeError("TiRTC requires macOS 11.5+")
    else:
        libc, version = platform.libc_ver()
        if libc != "glibc" or tuple(int(value) for value in version.split(".")[:2]) < (2, 35):
            raise RuntimeError("TiRTC requires glibc 2.35+ Linux x86_64")

def main():
    try:
        supported_platform()
    except (RuntimeError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    if sys.argv[1:] == ["--check"]:
        return 0
    if sys.argv[1:]:
        print("usage: python install.py [--check]", file=sys.stderr)
        return 1
    return subprocess.call([sys.executable, "-m", "pip", "install", "--require-hashes",
                            "--only-binary=:all:", "-r", str(Path(__file__).with_name("requirements.txt"))])

if __name__ == "__main__":
    raise SystemExit(main())
