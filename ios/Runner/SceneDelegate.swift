import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let flutterViewController = window?.rootViewController as? FlutterViewController {
      HydraBoxDeepLinkBridge.shared.configure(binaryMessenger: flutterViewController.binaryMessenger)
    }
    if let url = connectionOptions.urlContexts.first?.url {
      HydraBoxDeepLinkBridge.shared.handle(url: url)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    if let url = URLContexts.first?.url {
      HydraBoxDeepLinkBridge.shared.handle(url: url)
    }
  }
}
