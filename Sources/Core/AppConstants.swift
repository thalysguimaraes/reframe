import Foundation

public enum AppConstants {
    private static let defaultAppGroupID = "group.dev.autoframe.cam"
    public static let displayName = "Reframe"
    public static let cliExecutableName = "reframe"

    public static var appGroupID: String {
        guard
            let configuredAppGroupID = infoString(forKey: "ReframeAppGroupID") ?? infoString(forKey: "AutoFrameAppGroupID"),
            !configuredAppGroupID.isEmpty
        else {
            return defaultAppGroupID
        }

        return configuredAppGroupID
    }

    public static let supportDirectoryName = "Reframe"
    public static let legacySupportDirectoryName = "AutoFrameCam"
    public static let virtualCameraName = displayName
    public static let providerManufacturer = displayName
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

    public static var marketingVersion: String {
        infoString(forKey: "CFBundleShortVersionString") ?? "0.0.0"
    }

    public static var buildVersion: String {
        infoString(forKey: kCFBundleVersionKey as String) ?? "0"
    }

    public static var versionDisplayString: String {
        if buildVersion == "0" || buildVersion == marketingVersion {
            return marketingVersion
        }
        return "\(marketingVersion) (\(buildVersion))"
    }

    private static func infoString(forKey key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
