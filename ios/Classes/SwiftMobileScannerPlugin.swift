import Flutter
import AVFoundation
import UIKit

public class SwiftMobileScannerPlugin: NSObject, FlutterPlugin {
    
    private let mobileScanner: MobileScanner
    private let barcodeHandler: BarcodeHandler

    init(barcodeHandler: BarcodeHandler, registry: FlutterTextureRegistry) {
        self.mobileScanner = MobileScanner(registry: registry, mobileScannerCallback: { barcodes, error in
            if let barcodes {
                if (!barcodes.isEmpty) {
                    let data = barcodes.map({
                        [
                            "rawValue": $0.value,
                            "format": 256 /* QR */,
                            "type": 7 /* text */,
                        ] as [String : Any]
                    })
                    barcodeHandler.publishEvent(["name": "barcode", "data": data])
                }
            } else if let error {
                barcodeHandler.publishEvent(["name": "error", "data": error.localizedDescription])
            }
        }, torchModeChangeCallback: { torchState in
            barcodeHandler.publishEvent(["name": "torchState", "data": torchState])
        })
        self.barcodeHandler = barcodeHandler
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SwiftMobileScannerPlugin(
            barcodeHandler: BarcodeHandler(registrar: registrar),
            registry: registrar.textures()
        )
        let methodChannel = FlutterMethodChannel(
            name: "dev.steenbakker.mobile_scanner/scanner/method",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "state":
            result(mobileScanner.checkPermission())
        case "request":
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { result($0) })
        case "start":
            start(call, result)
        case "stop":
            stop(result)
        case "torch":
            self.toggleTorch(call, result)
        case "updateScanWindow":
            self.updateScanWindow(call, result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    /// Parses all parameters and starts the mobileScanner
    private func start(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let torch: Bool = (call.arguments as! Dictionary<String, Any?>)["torch"] as? Bool ?? false

        do {
            let parameters = try mobileScanner.start(torch: torch ? .on : .off)
            result([
                "textureId": parameters.textureId,
                "size": ["width": parameters.width, "height": parameters.height],
                "torchable": parameters.hasTorch
            ] as [String : Any])
        } catch MobileScannerError.alreadyStarted {
            result(FlutterError(code: "MobileScanner", message: "Called start() while already started!", details: nil))
        } catch MobileScannerError.noCamera {
            result(FlutterError(code: "MobileScanner", message: "No camera found or failed to open camera!", details: nil))
        } catch MobileScannerError.torchError(let error) {
            result(FlutterError(code: "MobileScanner", message: "Error occured when setting torch!", details: error))
        } catch MobileScannerError.cameraError(let error) {
            result(FlutterError(code: "MobileScanner", message: "Error occured when setting up camera!", details: error))
        } catch {
            result(FlutterError(code: "MobileScanner", message: "Unknown error occured..", details: nil))
        }
    }

    /// Stops the mobileScanner and closes the texture
    private func stop(_ result: @escaping FlutterResult) {
        do {
            try mobileScanner.stop()
        } catch {}
        result(nil)
    }

    /// Toggles the torch
    private func toggleTorch(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        do {
            try mobileScanner.setTorch(call.arguments as? Int == 1 ? .on : .off)
        } catch {
            result(FlutterError(code: "MobileScanner", message: "Called toggleTorch() while stopped!", details: nil))
        }
        result(nil)
    }

    /// Toggles the torch
    func updateScanWindow(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        if let points = (call.arguments as? [String: Any])?["rect"] as? [CGFloat] {
            let minX = points[0]
            let minY = points[1]
            let rect = CGRect(x: minX, y: minY, width: points[2]  - minX, height: points[3] - minY)
            mobileScanner.setScanWindow(rect)
        } else {
            mobileScanner.setScanWindow(nil)
        }

        result(nil)
    }
}
