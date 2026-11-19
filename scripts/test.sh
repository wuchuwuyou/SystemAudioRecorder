#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p build
TARGET="$(uname -m)-apple-macosx26.0"
xcrun swiftc -swift-version 5 -target "$TARGET" \
    Sources/Backend/TapPolicy.swift Sources/Backend/AudioSignal.swift Sources/Backend/WaveformTelemetry.swift Sources/Backend/CaptureDiagnostics.swift Tests/BackendTests/main.swift \
    -o build/backend-tests
build/backend-tests
xcrun swiftc -swift-version 5 -target "$TARGET" \
    Sources/Shared/RecordingFileStore.swift Tests/SaveTests/main.swift -o build/save-tests
build/save-tests
xcrun swiftc -swift-version 5 -target "$TARGET" \
    Sources/App/RecordingProcess.swift Tests/AppTests/RecordingProcessTests.swift -o build/app-process-tests
build/app-process-tests
xcrun swiftc -swift-version 5 -target "$TARGET" \
    Sources/Shared/RecordingFileStore.swift Sources/App/RecordingSaveOperation.swift \
    Tests/AppTests/RecordingSaveOperationTests.swift -o build/app-save-tests
build/app-save-tests
printf 'Capture-policy, signal, atomic-save, and helper-lifecycle tests passed. No system audio was recorded.\n' 

xcrun swiftc -swift-version 5 -target "$TARGET" \
    Sources/App/Localization.swift Sources/App/WaveformView.swift Tests/UIModelTests/WaveformHistoryTests.swift \
    -o build/waveform-view-tests
build/waveform-view-tests
xcrun swiftc -swift-version 5 -target "$TARGET" \
    Sources/App/Localization.swift Tests/UIModelTests/LocalizationTests.swift -o build/localization-tests
build/localization-tests
