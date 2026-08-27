#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./run.sh \
    --endpoint <endpoint> \
    --device-id <device_id> \
    --device-secret-key <device_secret_key> \
    --token <device_access_token>
EOF
}

endpoint=""
device_id=""
device_secret_key=""
token=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --endpoint)
      [[ $# -ge 2 && -n "$2" ]] || {
        printf 'Missing value for --endpoint\n' >&2
        usage >&2
        exit 2
      }
      endpoint="${2:-}"
      shift 2
      ;;
    --device-id)
      [[ $# -ge 2 && -n "$2" ]] || {
        printf 'Missing value for --device-id\n' >&2
        usage >&2
        exit 2
      }
      device_id="${2:-}"
      shift 2
      ;;
    --device-secret-key)
      [[ $# -ge 2 && -n "$2" ]] || {
        printf 'Missing value for --device-secret-key\n' >&2
        usage >&2
        exit 2
      }
      device_secret_key="${2:-}"
      shift 2
      ;;
    --token)
      [[ $# -ge 2 && -n "$2" ]] || {
        printf 'Missing value for --token\n' >&2
        usage >&2
        exit 2
      }
      token="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$endpoint" || -z "$device_id" || -z "$device_secret_key" || -z "$token" ]]; then
  usage >&2
  exit 2
fi

host_os="$(uname -s)"
host_arch="$(uname -m)"

case "$host_os/$host_arch" in
  Darwin/arm64)
    platform="macos-arm64-desktop"
    sdk_dir="$script_dir/sdk/$platform"
    build_dir="$script_dir/build/$platform"
    sdk_library="$sdk_dir/lib/libTiRTC.dylib"
    companion_library="$sdk_dir/lib/libtgrtc.dylib"
    ;;
  Linux/x86_64|Linux/amd64)
    platform="linux-x86_64"
    sdk_dir="$script_dir/sdk/$platform"
    build_dir="$script_dir/build/$platform"
    sdk_library="$sdk_dir/lib/libTiRTC.so"
    companion_library=""
    ;;
  *)
    printf 'Unsupported platform: %s/%s\n' "$host_os" "$host_arch" >&2
    exit 1
    ;;
esac

header="$sdk_dir/include/tirtc/ticloudstorage.h"
if [[ ! -f "$header" || ! -f "$sdk_library" ]]; then
  printf 'Nano SDK is incomplete under %s\n' "$sdk_dir" >&2
  printf 'Read %s/README.md and extract the latest standard package first.\n' "$script_dir" >&2
  exit 1
fi
if [[ -n "$companion_library" && ! -f "$companion_library" ]]; then
  printf 'Required macOS runtime library is missing: %s\n' "$companion_library" >&2
  exit 1
fi

command -v cc >/dev/null 2>&1 || {
  printf 'C compiler not found: cc\n' >&2
  exit 1
}

mkdir -p "$build_dir"

common_flags=(
  -std=c11
  -O2
  -Wall
  -Wextra
  -I"$sdk_dir/include/tirtc"
  "$script_dir/src/main.c"
  "$script_dir/src/media_reader.c"
  -L"$sdk_dir/lib"
  -lTiRTC
  -pthread
)

if [[ "$platform" == "macos-arm64-desktop" ]]; then
  cc "${common_flags[@]}" -Wl,-rpath,@executable_path -o "$build_dir/nano_upload_sample"
  cp "$sdk_library" "$build_dir/libTiRTC.dylib"
  cp "$companion_library" "$build_dir/libtgrtc.dylib"
else
  cc "${common_flags[@]}" -Wl,-rpath,'$ORIGIN' -o "$build_dir/nano_upload_sample"
  cp "$sdk_library" "$build_dir/libTiRTC.so"
fi

printf '[run] platform=%s\n' "$platform"
printf '[run] sdk=%s\n' "$sdk_dir"

cd "$build_dir"
exec ./nano_upload_sample \
  --endpoint "$endpoint" \
  --device-id "$device_id" \
  --device-secret-key "$device_secret_key" \
  --token "$token" \
  --video-file "$script_dir/assets/video.h264" \
  --audio-file "$script_dir/assets/audio.g711a"
