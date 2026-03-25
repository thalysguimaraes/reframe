import Foundation

public enum AppConstants {
    private static let defaultAppGroupID = "group.dev.autoframe.cam"

    public static var appGroupID: String {
        guard
            let configuredAppGroupID = Bundle.main.object(forInfoDictionaryKey: "AutoFrameAppGroupID") as? String,
            !configuredAppGroupID.isEmpty
        else {
            return defaultAppGroupID
        }

        return configuredAppGroupID
    }

    public static let supportDirectoryName = "AutoFrameCam"
    public static let virtualCameraName = "Reframe"
    public static let providerManufacturer = "Reframe"
    public static let extensionBundleIdentifier = "dev.autoframe.AutoFrameCam.CameraExtension"
    public static let legacyVirtualCameraNames = [
        "AutoFrame Cam",
        "Auto Frame Cam"
    ]
    public static let virtualCameraManufacturers = [
        providerManufacturer,
        "AutoFrame Cam",
        "Auto Frame Cam"
    ]
    public static let virtualCameraModelNames = [
        "Reframe Virtual Camera",
        "AutoFrame Cam Virtual Camera",
        "Auto Frame Cam Virtual Camera"
    ]

    public static let virtualDeviceUUID = UUID(uuidString: "6A250C8B-70A5-4E29-BBA9-83E1572E7846")!
    public static let virtualStreamUUID = UUID(uuidString: "A7E9D870-B0BB-4D52-A4E3-9274F5A3FCEB")!
}
