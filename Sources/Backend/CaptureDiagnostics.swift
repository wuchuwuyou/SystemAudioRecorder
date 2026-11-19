import Foundation

func report(_ message: String) {
    let data = Data(message.utf8).prefix(Int(PIPE_BUF) - 1) + Data([10])
    _ = writeProtocolFrame(data, to: STDERR_FILENO)
}

struct CaptureError: LocalizedError {
    let errorDescription: String?
    var exitCode: Int32 = 1
}
