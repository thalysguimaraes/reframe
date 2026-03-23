import AutoFrameCore
import Foundation
import SystemExtensions

@MainActor
final class SystemExtensionManager: NSObject, ObservableObject {
    @Published private(set) var statusMessage = "Extension not requested yet."

    func activateExtension() {
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: AppConstants.extensionBundleIdentifier,
            queue: .main
        )
        request.delegate = self
        updateStatus("Requesting extension activation…")
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func deactivateExtension() {
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: AppConstants.extensionBundleIdentifier,
            queue: .main
        )
        request.delegate = self
        updateStatus("Requesting extension removal…")
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    nonisolated private func updateStatus(_ message: String) {
        Task { @MainActor [weak self] in
            self?.statusMessage = message
        }
    }
}

extension SystemExtensionManager: OSSystemExtensionRequestDelegate {
    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        updateStatus("Extension approval required in System Settings.")
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        switch result {
        case .completed:
            updateStatus("Extension request completed.")
        case .willCompleteAfterReboot:
            updateStatus("Extension will finish installing after a reboot.")
        @unknown default:
            updateStatus("Extension completed with an unknown result.")
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        updateStatus("Extension request failed: \(error.localizedDescription)")
    }

    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }
}
