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
      MeowDeepLinkBridge.shared.configure(binaryMessenger: flutterViewController.binaryMessenger)
    }
    if let url = connectionOptions.urlContexts.first?.url {
      MeowDeepLinkBridge.shared.handle(url: url)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    if let url = URLContexts.first?.url {
      MeowDeepLinkBridge.shared.handle(url: url)
    }
  }
}
