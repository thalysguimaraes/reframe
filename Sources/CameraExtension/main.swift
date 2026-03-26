import CoreMediaIO
import Foundation

let providerSource = ReframeCameraProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)
CFRunLoopRun()
