import Foundation
import AVFoundation

struct Barcode {
    let value: String
}

struct MobileScannerStartParameters {
    var width: Double
    var height: Double
    var hasTorch: Bool
    var textureId: Int64
}

typealias MobileScannerCallback = ((Array<Barcode>?, Error?) -> ())
typealias TorchModeChangeCallback = ((Int?) -> ())

public class MobileScanner: NSObject {

    private var captureSession: AVCaptureSession!
    private var device: AVCaptureDevice!
    private var metadataOutput: AVCaptureMetadataOutput!

    private var scanWindow: CGRect?
    private var torchMode: AVCaptureDevice.TorchMode = .off

    private let mobileScannerCallback: MobileScannerCallback
    private let torchModeChangeCallback: TorchModeChangeCallback

    // To communicate with flutter
    private let flutterTextureRegistry: FlutterTextureRegistry?
    private var flutterTextureId: Int64!
    private var latestBuffer: CVImageBuffer!

    init(
        registry: FlutterTextureRegistry?,
        mobileScannerCallback: @escaping MobileScannerCallback,
        torchModeChangeCallback: @escaping TorchModeChangeCallback
    ) {
        self.flutterTextureRegistry = registry
        self.mobileScannerCallback = mobileScannerCallback
        self.torchModeChangeCallback = torchModeChangeCallback
        super.init()
    }

    func checkPermission() -> Int {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined: return 0
        case .authorized: return 1
        default: return 2
        }
    }

    func start(torch: AVCaptureDevice.TorchMode) throws -> MobileScannerStartParameters {
        guard (device == nil) else { throw MobileScannerError.alreadyStarted }

        captureSession = AVCaptureSession()
        flutterTextureId = flutterTextureRegistry?.register(self)

        device = AVCaptureDevice.default(for: .video)
        guard (device != nil) else { throw MobileScannerError.noCamera }

        device.addObserver(self, forKeyPath: #keyPath(AVCaptureDevice.torchMode), options: .new, context: nil)

        // Add device input
        do {
            let input = try AVCaptureDeviceInput(device: device)
            captureSession.addInput(input)
        } catch {
            throw MobileScannerError.cameraError(error)
        }

        metadataOutput = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)

            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            throw MobileScannerError.noOutput
        }

        let videoOutput = AVCaptureVideoDataOutput()
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)

            for connection in videoOutput.connections {
                connection.videoOrientation = .portrait
            }
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.main)
        } else {
            throw MobileScannerError.noOutput
        }

        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
                self.torchMode = torch
                try? self.updateTorch()
                self.updateScanWindow()
            }
        }

        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        return MobileScannerStartParameters(
            width: Double(dimensions.height),
            height: Double(dimensions.width),
            hasTorch: device.hasTorch,
            textureId: flutterTextureId
        )
    }

    func stop() throws {
        if (device == nil) {
            throw MobileScannerError.alreadyStopped
        }
        captureSession.stopRunning()
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }
        device.removeObserver(self, forKeyPath: #keyPath(AVCaptureDevice.torchMode))
        flutterTextureRegistry?.unregisterTexture(flutterTextureId)
        flutterTextureId = nil
        captureSession = nil
        device = nil
    }

    func setTorch(_ torch: AVCaptureDevice.TorchMode) throws {
        torchMode = torch
        if (device != nil) {
            try updateTorch()
        }
    }

    private func updateTorch() throws {
        if (device.hasTorch && device.isTorchAvailable) {
            do {
                try device.lockForConfiguration()
                device.torchMode = torchMode
                device.unlockForConfiguration()
            } catch {
                throw MobileScannerError.torchError(error)
            }
        }
    }

    func setScanWindow(_ rect: CGRect?) {
        if let rect {
            // invert rect as the output is on landscape mode
            scanWindow = CGRect(x: rect.minY, y: rect.minX, width: rect.height, height: rect.width)
        } else {
            scanWindow = nil
        }
        if (captureSession != nil && captureSession?.isRunning == true) {
            updateScanWindow()
        }
    }

    private func updateScanWindow() {
        if let scanWindow {
            metadataOutput.rectOfInterest = metadataOutput.metadataOutputRectConverted(fromOutputRect: scanWindow)
        } else {
            metadataOutput.rectOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
        }
    }

    public override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        switch keyPath {
        case "torchMode":
            // off = 0; on = 1; auto = 2;
            let state = change?[.newKey] as? Int
            torchModeChangeCallback(state)
        default:
            break
        }
    }
}

extension MobileScanner: AVCaptureMetadataOutputObjectsDelegate {
    public func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        if
            let readableObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            readableObject.type == AVMetadataObject.ObjectType.qr,
            let value = readableObject.stringValue
        {
            let barcode = Barcode(value: value)
            mobileScannerCallback([barcode], nil)
        }
    }
}

extension MobileScanner: AVCaptureVideoDataOutputSampleBufferDelegate, FlutterTexture {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to get image buffer from sample buffer.")
            return
        }
        latestBuffer = imageBuffer
        flutterTextureRegistry?.textureFrameAvailable(flutterTextureId)
    }

    public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        if latestBuffer == nil {
            return nil
        }
        return Unmanaged<CVPixelBuffer>.passRetained(latestBuffer)
    }
}
