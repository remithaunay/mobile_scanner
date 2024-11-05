import AVFoundation

extension AVMetadataObject.ObjectType {
    static func from(_ format: Int) -> AVMetadataObject.ObjectType? {
        switch format {
            case 0:
                return nil
            case 1:
                return .code128
            case 2:
                return .code39
            case 4:
                return .code93
            case 8:
                return .code39Mod43
            case 16:
                return .dataMatrix
            case 32:
                return .ean13
            case 64:
                return .ean8
            case 128:
                return .interleaved2of5
            case 256:
                return .qr
            case 512:
                return .upce
            case 1024:
                return .pdf417
            case 2048:
                return .aztec
            default:
                return nil
        }
    }
}