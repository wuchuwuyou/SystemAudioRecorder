import CoreAudio

func makeSystemAudioTapDescription() -> CATapDescription {
    let tap = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
    tap.isPrivate = true
    tap.muteBehavior = .unmuted
    tap.name = "System Audio Capture"
    return tap
}
