# System Audio Recorder

A small native AppKit recorder for **all computer playback**. It does not open a microphone input, install an audio driver, access WeChat data, or upload recordings.

## Compact interface

- A 360 × 240 native window with its title only in the title bar, a small timer, and one icon-only control for Record, Stop, or Save pending audio.
- A live waveform derived from **actual captured PCM**, with eight amplitude-envelope points published at 20 Hz and retained in bounded rolling history. Idle is flat, silence produces zero peaks, and the waveform freezes when recording stops. It is not a decorative animation or speaker identification.
- English (`en`) and Simplified Chinese (`zh-Hans`) follow the OS automatically; there is no language picker.
- The small information button reveals privacy disclosure, help, and status details instead of persistent paragraphs. Icons have localized accessibility labels and tooltips; Space activates the main control and ⌘I opens information. Native colors adapt to light and dark appearance.

## Requirements

- macOS 26.0 or later; development and testing were performed on macOS 26.7.3.
- Xcode / Command Line Tools with the macOS 26 SDK to build from source.
- The prebuilt app targets the architecture of the build machine.

No Xcode project is needed: the build scripts use `swiftc` directly with the installed macOS SDK.

This is a locally ad-hoc-signed app, not a notarized distribution or an App Store release. Compatibility with older macOS versions has not been validated.

## Use

1. Open **System Audio Recorder.app**.
2. Click the red circular **Record icon**. If macOS requests system-audio recording permission, grant it yourself. No microphone permission is needed.
3. Wait until the status says recording, then play the sound you want to capture.
4. Click the **Stop icon** in the same control. The app stops and finalizes a WAV before displaying the native save panel.
5. Choose the filename and destination. If you cancel, the recording remains pending: the same control becomes a **Save arrow icon**; click it to try again. Replacing an existing file requires explicit confirmation, with Cancel as the default. A failed save also keeps the temporary recording. After a successful save, the app removes only its owned private temporary copy. Cleanup failures are reported without mislabeling a successful destination save as failed. Usable captures interrupted by an error are clearly labeled as partial recordings.

Do not quit with an active or unsaved recording. The app warns instead of silently discarding it. Starting a new recording is disabled until the pending one is saved.

The app records all playback, including notifications, other applications, and call playback. It cannot separate a wanted voice from other simultaneous sounds. It is a playback copy, not an export of the original source file. Files written to a cloud-synced folder may be synchronized by that folder's service; this app itself contains no upload code.

## Build and run

```bash
./scripts/build_and_run.sh
```

Build without launching:

```bash
./scripts/build_and_run.sh --build-only
```

The output is placed under `build/`; `build/latest-app-path.txt` records the actual path. Rebuilding does not terminate an existing recorder: save your recording and close it first. Repeated builds retain previous app bundles instead of deleting them.

## Tests

```bash
./scripts/test.sh
```

The assertions use real Core Audio tap descriptions, real planar/interleaved PCM buffers, and real WAV files. They check global playback scope, digital-silence rejection, telemetry-pipe backpressure, empty-capture exit classification, normal saving, authorized replacement, overwrite refusal, private output permissions, and preservation of recordings when saving fails. Test fixtures are synthetic and local. These tests do not record live system audio or approve privacy prompts.

## Source layout

- `Sources/App/`: compact AppKit window, waveform, localization, and Record/Stop/Save workflow.
- `Sources/Backend/`: Core Audio process tap, WAV writer, silence checks, and PCM waveform telemetry.
- `Sources/Shared/RecordingFileStore.swift`: streamed copying and atomic destination replacement; temporary source retained on failure.
- `Resources/`: app and helper privacy descriptions, plus English and Simplified Chinese localizations.
- `Tests/`: assert-based behavior tests.

The GUI launches its bundled `AudioRecorderBackend` helper with a private temporary WAV path. The helper emits `RECORDING:` after capture starts, and receives a newline to stop. There is no fixed time limit; available disk space and WAV/container limits still apply. A write error stops the backend instead of continuing to pretend that audio is being saved.

Audio is saved as uncompressed PCM WAV in the format supplied by the tap. The implementation currently validates Float32 PCM. It does not apply normalization, denoising, MP3 compression, or trimming. Long recordings can consume substantial disk space.

## Synthetic GUI validation

```bash
./scripts/build-gui-validation.sh
```

This creates a separate `Recorder UI Check-<timestamp>.app` under `build/`. Its localized app name and window title explicitly distinguish it from production:

- English: **Synthetic Waveform Test (No Capture)**
- Simplified Chinese: **合成波形测试（不录电脑声音）**

**The synthetic UI test does not capture computer audio or a microphone.** It reuses the production UI with `FixtureBackend`, which generates a one-second tone and publishes the generated PCM's envelope at 20 Hz until Stop. Its waveform is synthetic test data, not live computer playback. It is for testing the waveform and Record/Stop/Save control, Save cancellation/retry, and unsaved-close protection. Use **System Audio Recorder.app**, not this test app, for real recording. Building the validation bundle does not launch it.

Earlier synthetic native GUI validation checked that the recording status arrived before Stop, Stop opened the save panel, Cancel retained the audio, an unsaved close was blocked, retrying Save wrote a readable WAV to the selected directory, and the private temporary copy was cleaned after success. These fixture checks do not validate live system capture.

## Current validation limits

The native save panel is scheduled with `RunLoop.main.perform`, using `MainActor.assumeIsolated` around `panel.runModal()` outside a main-dispatch callback. This avoids the disabled Save controls and cancel/retry hangs encountered with the earlier presentation approaches while retaining the pending-recording guards.

On November 19, 2026, the final English synthetic app (`Recorder UI Check-20261119-121438.app`) verified this exact flow: Record → Stop → enabled Save → Cancel returns to pending without hanging → retry opens a focused save panel → ⌘⇧G selects the workspace `work/` directory → Save writes `compact-ui-final-synthetic-20261119.wav` and the UI reports “Recording saved”. Earlier Simplified Chinese checks verified information/help, the waveform, icon states, and unsaved-close protection. The saved WAV’s audio content was not part of this UI verification. Live system capture remains unchecked for this upgrade.

Builds, capture-policy tests, signal checks, and atomic-save behavior are separate from end-to-end recording. Verify a short recording through the GUI on your machine before relying on a long session. System recording permission may need to be approved again after rebuilding or moving the app. Never treat a silent or failed recording as successful.
