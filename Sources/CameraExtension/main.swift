import CoreMediaIO
import Foundation

let providerSource = AutoFrameCameraProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)
CFRunLoopRun()

