import AVFoundation

func bufferHasSignal(_ buffer: AVAudioPCMBuffer) -> Bool {
    guard let channels = buffer.floatChannelData else { return false }
    // Reject digital silence below -120 dBFS without rejecting quiet speech.
    for channel in 0..<Int(buffer.format.channelCount) {
        for frame in 0..<Int(buffer.frameLength) {
            if abs(channels[channel][frame * buffer.stride]) > 0.000001 { return true }
        }
    }
    return false
}
