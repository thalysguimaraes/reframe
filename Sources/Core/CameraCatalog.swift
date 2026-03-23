@preconcurrency import AVFoundation
import CoreMedia
import Foundation

public enum CameraCatalog {
    public static func videoDevices() -> [CameraDeviceDescriptor] {
        discoverySession.devices
            .filter { !isVirtualAutoFrameCamera($0) }
            .map(makeDescriptor)
            .sorted { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }
    }

    public static func defaultPhysicalCameraID(preferredID: String?) -> String? {
        let devices = videoDevices()
        if let preferredID, devices.contains(where: { $0.uniqueID == preferredID }) {
            return preferredID
        }
        return devices.first?.uniqueID
    }

    public static func device(for uniqueID: String?) -> AVCaptureDevice? {
        let preferredID = defaultPhysicalCameraID(preferredID: uniqueID)
        guard let preferredID else { return nil }
        return discoverySession.devices
            .first(where: { $0.uniqueID == preferredID && !isVirtualAutoFrameCamera($0) })
    }

    private static func makeDescriptor(for device: AVCaptureDevice) -> CameraDeviceDescriptor {
        let formatSummaries = device.formats.map { format -> (CGSize, Double) in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let resolution = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
            let maxFrameRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            return (resolution, maxFrameRate)
        }

        let maxResolution = formatSummaries
            .map(\.0)
            .max { lhs, rhs in lhs.width * lhs.height < rhs.width * rhs.height }

        let maxFrameRate = formatSummaries.map(\.1).max()

        return CameraDeviceDescriptor(
            uniqueID: device.uniqueID,
            localizedName: device.localizedName,
            maxResolution: maxResolution,
            maxFrameRate: maxFrameRate
        )
    }

    private static func isVirtualAutoFrameCamera(_ device: AVCaptureDevice) -> Bool {
        device.localizedName == AppConstants.virtualCameraName
    }

    private static let discoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.externalUnknown, .builtInWideAngleCamera],
        mediaType: .video,
        position: .unspecified
    )
}
