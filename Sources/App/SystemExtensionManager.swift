import AutoFrameCore
import Foundation
import SystemExtensions

private enum SystemExtensionErrorCode: Int {
    case unknown = 1
    case missingEntitlement = 2
    case unsupportedParentBundleLocation = 3
    case extensionNotFound = 4
    case extensionMissingIdentifier = 5
    case duplicateExtensionIdentifier = 6
    case unknownExtensionCategory = 7
    case codeSignatureInvalid = 8
    case validationFailed = 9
    case forbiddenBySystemPolicy = 10
    case requestCanceled = 11
    case requestSuperseded = 12
    case authorizationRequired = 13
}

private enum SystemExtensionRequestKind {
    case activation
    case deactivation
    case properties
}

private enum ExtensionInstallationState: Equatable {
    case unknown
    case readyToInstall
    case awaitingUserApproval(version: String)
    case installed(version: String, isCurrentBuild: Bool)
    case installedDisabled(version: String)
    case uninstalling(version: String)
}

private struct ExtensionPropertiesSnapshot: Sendable {
    let bundleVersion: String
    let isEnabled: Bool
    let isAwaitingUserApproval: Bool
    let isUninstalling: Bool
}

@MainActor
final class SystemExtensionManager: NSObject, ObservableObject {
    @Published private(set) var statusMessage = "Checking virtual camera readiness..."

    private let fileManager: FileManager
    private let mainBundle: Bundle
    private var hasAttemptedAutomaticReplacement = false
    private var installationState: ExtensionInstallationState = .unknown
    private var requestKinds: [ObjectIdentifier: SystemExtensionRequestKind] = [:]

    init(fileManager: FileManager = .default, mainBundle: Bundle = .main) {
        self.fileManager = fileManager
        self.mainBundle = mainBundle
        super.init()
        refreshStatus()
    }

    var primaryActionTitle: String {
        switch installationState {
        case .unknown, .readyToInstall:
            return "Install"
        case .awaitingUserApproval:
            return "Pending"
        case let .installed(_, isCurrentBuild):
            return isCurrentBuild ? "Installed" : "Replace"
        case .installedDisabled:
            return "Install"
        case .uninstalling:
            return "Replace"
        }
    }

    var secondaryActionTitle: String {
        switch installationState {
        case .uninstalling:
            return "Pending"
        default:
            return "Uninstall"
        }
    }

    var canActivateExtension: Bool {
        guard activationPreflightFailure() == nil else {
            return false
        }

        switch installationState {
        case .unknown, .readyToInstall, .installedDisabled, .uninstalling:
            return true
        case let .installed(_, isCurrentBuild):
            return !isCurrentBuild
        case .awaitingUserApproval:
            return false
        }
    }

    var canDeactivateExtension: Bool {
        guard embeddedExtensionBundle() != nil else {
            return false
        }

        switch installationState {
        case .installed, .installedDisabled:
            return true
        case .unknown, .readyToInstall, .awaitingUserApproval, .uninstalling:
            return false
        }
    }

    func refreshStatus() {
        if let failure = activationPreflightFailure() {
            installationState = .unknown
            statusMessage = failure
            return
        }

        let request = OSSystemExtensionRequest.propertiesRequest(
            forExtensionWithIdentifier: AppConstants.extensionBundleIdentifier,
            queue: .main
        )
        request.delegate = self
        requestKinds[ObjectIdentifier(request)] = .properties
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func activateExtension() {
        if let failure = activationPreflightFailure() {
            updateStatus(failure)
            return
        }

        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: AppConstants.extensionBundleIdentifier,
            queue: .main
        )
        request.delegate = self
        requestKinds[ObjectIdentifier(request)] = .activation
        updateStatus("Requesting extension activation or replacement…")
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func deactivateExtension() {
        if !canDeactivateExtension {
            updateStatus("Embedded system extension not found in this app bundle.")
            return
        }

        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: AppConstants.extensionBundleIdentifier,
            queue: .main
        )
        request.delegate = self
        requestKinds[ObjectIdentifier(request)] = .deactivation
        updateStatus("Requesting extension removal…")
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    nonisolated private func updateStatus(_ message: String) {
        Task { @MainActor [weak self] in
            self?.statusMessage = message
        }
    }

    private func activationPreflightFailure() -> String? {
        let appURL = mainBundle.bundleURL.resolvingSymlinksInPath()
        guard isInsideApplicationsDirectory(appURL) else {
            let appName = mainBundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? appURL.lastPathComponent
            let locationHint: String

            if appURL.path.contains("/AppTranslocation/") {
                locationHint = "\(appName) is running from a translocated location, not /Applications."
            } else {
                locationHint = "\(appName) is currently running from \(appURL.path)."
            }

            return "Virtual camera install requires the app to run from /Applications. Move the app to /Applications, relaunch that copy, then install again. \(locationHint)"
        }

        guard let extensionBundle = embeddedExtensionBundle() else {
            return "Embedded system extension not found in \(embeddedSystemExtensionsDirectoryURL().path)."
        }

        guard let bundleIdentifier = extensionBundle.bundleIdentifier else {
            return "Embedded system extension is missing CFBundleIdentifier."
        }

        guard bundleIdentifier == AppConstants.extensionBundleIdentifier else {
            let discoveredBundles = embeddedSystemExtensionBundles()
                .map { $0.bundleIdentifier ?? $0.bundleURL.lastPathComponent }
                .joined(separator: ", ")

            return "Embedded system extension identifier mismatch. Expected \(AppConstants.extensionBundleIdentifier), found \(bundleIdentifier). Embedded bundles: \(discoveredBundles)."
        }

        guard fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupID) != nil else {
            return "App Group \(AppConstants.appGroupID) is unavailable. Check the App Groups capability and provisioning for both the app and the extension."
        }

        return nil
    }

    private func embeddedSystemExtensionsDirectoryURL() -> URL {
        mainBundle.bundleURL
            .appendingPathComponent("Contents/Library/SystemExtensions", isDirectory: true)
    }

    private func embeddedSystemExtensionBundles() -> [Bundle] {
        let extensionsDirectory = embeddedSystemExtensionsDirectoryURL()

        guard let candidates = try? fileManager.contentsOfDirectory(
            at: extensionsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return candidates
            .filter { $0.pathExtension == "systemextension" }
            .compactMap(Bundle.init(url:))
    }

    private func embeddedExtensionBundle() -> Bundle? {
        let bundles = embeddedSystemExtensionBundles()

        if let matchingBundle = bundles.first(where: { $0.bundleIdentifier == AppConstants.extensionBundleIdentifier }) {
            return matchingBundle
        }

        return bundles.first
    }

    private func embeddedExtensionVersion() -> String {
        let version = embeddedExtensionBundle()?
            .object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return version ?? "unknown"
    }

    private func isInsideApplicationsDirectory(_ appURL: URL) -> Bool {
        let appPath = appURL.path
        return appPath.hasPrefix("/Applications/")
            || appPath == "/Applications/\(appURL.lastPathComponent)"
    }

    nonisolated private func formattedStatus(for error: Error) -> String {
        let nsError = error as NSError
        var parts = ["Extension request failed"]

        if nsError.domain == OSSystemExtensionErrorDomain,
           let code = SystemExtensionErrorCode(rawValue: nsError.code) {
            parts[0] += ": \(description(for: code))"
        } else {
            parts[0] += ": \(nsError.localizedDescription)"
        }

        if let failureReason = nsError.localizedFailureReason, !failureReason.isEmpty {
            parts.append(failureReason)
        }

        if let recoverySuggestion = nsError.localizedRecoverySuggestion, !recoverySuggestion.isEmpty {
            parts.append(recoverySuggestion)
        }

        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("Underlying error: \(underlyingError.domain) \(underlyingError.code) \(underlyingError.localizedDescription)")
        }

        parts.append("(\(nsError.domain) error \(nsError.code))")
        return parts.joined(separator: " ")
    }

    private func updateInstalledProperties(_ snapshots: [ExtensionPropertiesSnapshot]) {
        guard let snapshot = preferredSnapshot(from: snapshots) else {
            installationState = .readyToInstall
            statusMessage = "Ready to install virtual camera."
            return
        }

        let bundledVersion = embeddedExtensionVersion()

        if snapshot.isUninstalling {
            installationState = .uninstalling(version: snapshot.bundleVersion)
            statusMessage = "Virtual camera build \(snapshot.bundleVersion) is uninstalling. Click Replace to install the current build \(bundledVersion), or reboot to finish removal."
            return
        }

        if snapshot.isAwaitingUserApproval {
            installationState = .awaitingUserApproval(version: snapshot.bundleVersion)
            statusMessage = "Virtual camera build \(snapshot.bundleVersion) is waiting for approval in System Settings > General > Login Items & Extensions > Camera Extensions."
            return
        }

        if snapshot.isEnabled {
            let isCurrentBuild = snapshot.bundleVersion == bundledVersion
            installationState = .installed(version: snapshot.bundleVersion, isCurrentBuild: isCurrentBuild)
            if isCurrentBuild {
                hasAttemptedAutomaticReplacement = false
                statusMessage = "Virtual camera build \(snapshot.bundleVersion) is installed and active."
            } else {
                statusMessage = "Virtual camera build \(snapshot.bundleVersion) is active. Replacing it with bundled build \(bundledVersion)…"
                automaticallyReplaceActiveBuildIfNeeded()
            }
            return
        }

        installationState = .installedDisabled(version: snapshot.bundleVersion)
        statusMessage = "Virtual camera build \(snapshot.bundleVersion) is installed but disabled. Enable it in System Settings > General > Login Items & Extensions > Camera Extensions."
    }

    private func preferredSnapshot(from snapshots: [ExtensionPropertiesSnapshot]) -> ExtensionPropertiesSnapshot? {
        guard !snapshots.isEmpty else { return nil }

        let bundledVersion = embeddedExtensionVersion()

        func preferred(
            where predicate: (ExtensionPropertiesSnapshot) -> Bool
        ) -> ExtensionPropertiesSnapshot? {
            snapshots.first(where: { predicate($0) && $0.bundleVersion == bundledVersion })
                ?? snapshots.first(where: predicate)
        }

        if let enabled = preferred(where: { $0.isEnabled }) {
            return enabled
        }

        if let awaitingApproval = preferred(where: { $0.isAwaitingUserApproval }) {
            return awaitingApproval
        }

        if let uninstalling = preferred(where: { $0.isUninstalling }) {
            return uninstalling
        }

        return snapshots.first(where: { $0.bundleVersion == bundledVersion }) ?? snapshots.first
    }

    private func automaticallyReplaceActiveBuildIfNeeded() {
        guard !hasAttemptedAutomaticReplacement else { return }
        guard activationPreflightFailure() == nil else { return }

        hasAttemptedAutomaticReplacement = true
        activateExtension()
    }

    nonisolated private func description(for code: SystemExtensionErrorCode) -> String {
        switch code {
        case .unknown:
            "the system rejected the request before returning a specific cause. Verify the app is signed, has com.apple.developer.system-extension.install, and is running from /Applications"
        case .missingEntitlement:
            "the host app is missing the system-extension install entitlement"
        case .unsupportedParentBundleLocation:
            "the app must be installed in /Applications before the extension can be activated"
        case .extensionNotFound:
            "the embedded system extension bundle was not found by macOS. This usually means you are launching a stale copy or not running the app from /Applications"
        case .extensionMissingIdentifier:
            "the embedded system extension is missing its bundle identifier"
        case .duplicateExtensionIdentifier:
            "multiple embedded system extensions share the same identifier"
        case .unknownExtensionCategory:
            "the embedded system extension category is invalid"
        case .codeSignatureInvalid:
            "the app or embedded extension signature is invalid"
        case .validationFailed:
            "system extension validation failed"
        case .forbiddenBySystemPolicy:
            "the extension was blocked by system policy or device management"
        case .requestCanceled:
            "the request was canceled"
        case .requestSuperseded:
            "the request was superseded by a newer request"
        case .authorizationRequired:
            "administrator authorization is required to continue"
        @unknown default:
            "an unknown system extension error occurred"
        }
    }
}

extension SystemExtensionManager: OSSystemExtensionRequestDelegate {
    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.installationState = .awaitingUserApproval(version: self.embeddedExtensionVersion())
        }
        updateStatus("Extension approval required in System Settings > General > Login Items & Extensions > Camera Extensions. Camera privacy permission is separate.")
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        let requestID = ObjectIdentifier(request)

        switch result {
        case .completed:
            Task { @MainActor [weak self] in
                guard let self else { return }

                let kind = self.requestKinds.removeValue(forKey: requestID)
                switch kind {
                case .activation?, .deactivation?:
                    self.refreshStatus()
                case .properties?:
                    break
                case nil:
                    self.statusMessage = "Extension request completed."
                }
            }
        case .willCompleteAfterReboot:
            Task { @MainActor [weak self] in
                guard let self else { return }
                let kind = self.requestKinds.removeValue(forKey: requestID)
                let bundledVersion = self.embeddedExtensionVersion()

                switch kind {
                case .activation?:
                    self.installationState = .installed(version: bundledVersion, isCurrentBuild: true)
                    self.statusMessage = "Virtual camera build \(bundledVersion) will finish installing after a reboot."
                case .deactivation?:
                    self.installationState = .uninstalling(version: bundledVersion)
                    self.statusMessage = "Virtual camera removal will finish after a reboot."
                case .properties?, nil:
                    self.installationState = .unknown
                    self.statusMessage = "System extension changes will complete after a reboot."
                }
            }
        @unknown default:
            updateStatus("Extension completed with an unknown result.")
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let requestID = ObjectIdentifier(request)
        let errorMessage = formattedStatus(for: error)
        let statusLookupError = "Unable to determine virtual camera status: \((error as NSError).localizedDescription)"

        Task { @MainActor [weak self] in
            guard let self else { return }

            let kind = self.requestKinds.removeValue(forKey: requestID)
            if case .properties? = kind {
                self.statusMessage = statusLookupError
            } else {
                self.statusMessage = errorMessage
            }
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        let requestID = ObjectIdentifier(request)
        let snapshots = properties.map {
            ExtensionPropertiesSnapshot(
                bundleVersion: $0.bundleVersion,
                isEnabled: $0.isEnabled,
                isAwaitingUserApproval: $0.isAwaitingUserApproval,
                isUninstalling: $0.isUninstalling
            )
        }

        Task { @MainActor [weak self] in
            self?.requestKinds.removeValue(forKey: requestID)
            self?.updateInstalledProperties(snapshots)
        }
    }

    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }
}
