#!/usr/bin/env python3
"""Build splink_plugin for multiple platforms.

Usage:
    python3 build.py                  # Build for current platform
    python3 build.py --all            # Build for all platforms
    python3 build.py --debug          # Debug build (sanitizers)

Requires stplugin.h and stplugin.c in this directory.
Download from: https://www.stata.com/plugins/
"""
import subprocess
import sys
import platform
import os
import argparse

PLATFORMS = {
    'darwin-arm64': {
        'cc': 'gcc',
        'cflags': '-O3 -fPIC -DSYSTEM=APPLEMAC -arch arm64',
        'ldflags': '-bundle -arch arm64 -pthread',
    },
    'darwin-x86_64': {
        'cc': 'gcc',
        'cflags': '-O3 -fPIC -DSYSTEM=APPLEMAC -target x86_64-apple-macos10.12',
        'ldflags': '-bundle -target x86_64-apple-macos10.12 -pthread',
    },
    'linux-x86_64': {
        'cc': 'gcc',
        'cflags': '-O3 -fPIC -DSYSTEM=OPUNIX',
        'ldflags': '-shared -pthread -lm',
    },
    'windows-x86_64': {
        'cc': 'x86_64-w64-mingw32-gcc',
        'cflags': '-O3 -DSYSTEM=STWIN32',
        'ldflags': '-shared -lwinpthread',
    },
}

SOURCES = ['splink_plugin.c', 'stplugin.c']
PLUGIN_NAME = 'splink_plugin'
OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')


def detect_platform():
    system = platform.system().lower()
    machine = platform.machine().lower()
    if system == 'darwin':
        if machine == 'arm64':
            return 'darwin-arm64'
        return 'darwin-x86_64'
    elif system == 'linux':
        return 'linux-x86_64'
    elif system == 'windows':
        return 'windows-x86_64'
    return None


def build(plat, debug=False):
    cfg = PLATFORMS[plat]
    output = os.path.join(OUTPUT_DIR, f'{PLUGIN_NAME}.{plat}.plugin')

    cflags = cfg['cflags']
    if debug:
        cflags = cflags.replace('-O3', '-O0 -g -fsanitize=address')

    cmd = f"{cfg['cc']} {cflags} {cfg['ldflags']} -o \"{output}\" {' '.join(SOURCES)}"

    print(f"Building {PLUGIN_NAME}.{plat}.plugin...")
    print(f"  {cmd}")

    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  FAILED:")
        print(result.stderr)
        return False
    print(f"  OK -> {output}")
    return True


def main():
    parser = argparse.ArgumentParser(description='Build splink Stata plugin')
    parser.add_argument('--all', action='store_true', help='Build for all platforms')
    parser.add_argument('--debug', action='store_true', help='Debug build with sanitizers')
    parser.add_argument('--platform', choices=list(PLATFORMS.keys()), help='Specific platform')
    args = parser.parse_args()

    # Check stplugin files exist
    for f in ['stplugin.h', 'stplugin.c']:
        if not os.path.exists(f):
            print(f"ERROR: {f} not found in current directory.")
            print(f"Download from: https://www.stata.com/plugins/")
            sys.exit(1)

    if args.all:
        targets = list(PLATFORMS.keys())
    elif args.platform:
        targets = [args.platform]
    else:
        detected = detect_platform()
        if not detected:
            print("Could not detect platform. Use --platform or --all.")
            sys.exit(1)
        targets = [detected]

    ok = True
    for plat in targets:
        if not build(plat, debug=args.debug):
            ok = False

    if not ok:
        print("\nSome builds failed.")
        sys.exit(1)
    print("\nAll builds succeeded.")


if __name__ == '__main__':
    main()
