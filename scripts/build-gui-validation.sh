#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Recorder UI Check-$(date +%Y%m%d-%H%M%S).app"
mkdir -p "$APP/Contents/MacOS"
/usr/bin/plutil -convert xml1 -o "$APP/Contents/Info.plist" "$ROOT/Resources/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.codex.SystemAudioRecorder.UICheck' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable RecorderUICheck' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Synthetic Waveform Test (No Capture)' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Synthetic Waveform Test (No Capture)' "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
for LANGUAGE in en zh-Hans; do
    if [[ -d "$ROOT/Resources/$LANGUAGE.lproj" ]]; then
        cp -R "$ROOT/Resources/$LANGUAGE.lproj" "$APP/Contents/Resources/"
        if [[ "$LANGUAGE" == "zh-Hans" ]]; then
            TEST_NAME='合成波形测试（不录电脑声音）'
        else
            TEST_NAME='Synthetic Waveform Test (No Capture)'
        fi
        LOCALIZED_INFO="$APP/Contents/Resources/$LANGUAGE.lproj/InfoPlist.strings"
        /usr/bin/plutil -convert xml1 "$LOCALIZED_INFO"
        /usr/libexec/PlistBuddy -c "Set :CFBundleName $TEST_NAME" "$LOCALIZED_INFO"
        /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $TEST_NAME" "$LOCALIZED_INFO"
    fi
done
TARGET="$(uname -m)-apple-macosx26.0"
xcrun swiftc -swift-version 5 -target "$TARGET" "$ROOT/Tests/GUIValidation/FixtureBackend.swift" "$ROOT/Sources/Backend/WaveformTelemetry.swift" \
    -o "$APP/Contents/MacOS/FixtureBackend" -Xlinker -no_adhoc_codesign
/usr/bin/codesign --sign - "$APP/Contents/MacOS/FixtureBackend"
xcrun swiftc -swift-version 5 -target "$TARGET" \
    "$ROOT/Sources/App/RecorderWindowController.swift" "$ROOT/Sources/App/RecordingProcess.swift" \
    "$ROOT/Sources/App/RecordingSaveOperation.swift" "$ROOT/Sources/App/WaveformView.swift" \
    "$ROOT/Sources/App/Localization.swift" \
    "$ROOT"/Sources/Shared/*.swift "$ROOT/Tests/GUIValidation/main.swift" \
    -o "$APP/Contents/MacOS/RecorderUICheck" -Xlinker -no_adhoc_codesign
/usr/bin/codesign --sign - "$APP"
printf '%s\n' "$APP" > "$ROOT/build/latest-validation-app-path.txt"
printf 'Synthetic-only GUI validation app: %s\n' "$APP"
