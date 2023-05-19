import Foundation

enum MobileScannerError: Error {
    case noCamera
    case noOutput
    case alreadyStarted
    case alreadyStopped
    case torchError(_ error: Error)
    case cameraError(_ error: Error)
}
