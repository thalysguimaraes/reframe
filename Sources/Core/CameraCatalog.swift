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
            isBuiltIn: device.deviceType == .builtInWideAngleCamera,
            maxResolution: maxResolution,
            maxFrameRate: maxFrameRate
        )
    }

    private static func isVirtualAutoFrameCamera(_ device: AVCaptureDevice) -> Bool {
        let normalizedName = normalized(device.localizedName)
        let normalizedManufacturer = normalized(device.manufacturer)
        let normalizedModel = normalized(device.modelID)
        let normalizedUniqueID = normalized(device.uniqueID)

        let knownNames = Set(([AppConstants.virtualCameraName] + AppConstants.legacyVirtualCameraNames).map(normalized))
        let knownManufacturers = Set(AppConstants.virtualCameraManufacturers.map(normalized))
        let knownModels = AppConstants.virtualCameraModelNames.map(normalized)

        if knownNames.contains(normalizedName) || knownNames.contains(normalizedUniqueID) {
            return true
        }

        if knownManufacturers.contains(normalizedManufacturer) {
            return true
        }

        return knownModels.contains { normalizedModel.contains($0) }
    }

    private static let discoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.externalUnknown, .builtInWideAngleCamera],
        mediaType: .video,
        position: .unspecified
    )

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
