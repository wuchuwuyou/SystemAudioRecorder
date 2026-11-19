#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ONLY=false
if [[ "${1:-}" == "--build-only" ]]; then BUILD_ONLY=true
elif [[ $# -gt 0 ]]; then echo "Usage: $0 [--build-only]" >&2; exit 64
fi
if /usr/bin/pgrep -x SystemAudioRecorder >/dev/null 2>&1; then
    echo "Save your recording and close System Audio Recorder before rebuilding." >&2
    exit 1
fi
APP="$ROOT/build/System Audio Recorder.app"
if [[ -e "$APP" ]]; then
    APP="$ROOT/build/System Audio Recorder-$(/bin/date +%Y%m%d-%H%M%S).app"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
for LANGUAGE in en zh-Hans; do
    if [[ -d "$ROOT/Resources/$LANGUAGE.lproj" ]]; then
        cp -R "$ROOT/Resources/$LANGUAGE.lproj" "$APP/Contents/Resources/"
    fi
done
TARGET="$(uname -m)-apple-macosx26.0"
xcrun swiftc -swift-version 5 -O -target "$TARGET" \
    "$ROOT"/Sources/Backend/*.swift -o "$APP/Contents/MacOS/AudioRecorderBackend" \
    -Xlinker -no_adhoc_codesign \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist \
    -Xlinker "$ROOT/Resources/BackendInfo.plist"
/usr/bin/codesign --sign - "$APP/Contents/MacOS/AudioRecorderBackend"
xcrun swiftc -swift-version 5 -O -target "$TARGET" \
    "$ROOT"/Sources/App/*.swift "$ROOT"/Sources/Shared/*.swift \
    -o "$APP/Contents/MacOS/SystemAudioRecorder" -Xlinker -no_adhoc_codesign
/usr/bin/codesign --sign - "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
printf '%s\n' "$APP" > "$ROOT/build/latest-app-path.txt"
printf 'Built: %s\n' "$APP"
if [[ "$BUILD_ONLY" == false ]]; then /usr/bin/open -n "$APP"; fi
