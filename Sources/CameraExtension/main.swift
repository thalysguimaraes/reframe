import AutoFrameCore
import CoreMediaIO
import Foundation

ExtensionBootstrapTrace.log("main: starting camera extension service bootstrap")
let providerSource = ReframeCameraProviderSource(clientQueue: nil)
ExtensionBootstrapTrace.log("main: provider source initialized")
CMIOExtensionProvider.startService(provider: providerSource.provider)
ExtensionBootstrapTrace.log("main: CMIOExtensionProvider.startService returned")
CFRunLoopRun()
