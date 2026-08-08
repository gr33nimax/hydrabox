import Flutter
import Foundation

final class HydraBoxDeepLinkBridge: NSObject {
  static let shared = HydraBoxDeepLinkBridge()

  private let methodChannelName = "io.hydrabox.client/deep_links"
  private let eventChannelName = "io.hydrabox.client/deep_link_events"
  private var pendingPayload: [String: Any]?
  private var eventSink: FlutterEventSink?
  private var isConfigured = false

  private override init() {
    super.init()
  }

  func configure(binaryMessenger: FlutterBinaryMessenger) {
    if isConfigured {
      return
    }
    isConfigured = true

    let methods = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: binaryMessenger
    )
    methods.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getInitialImportRequest":
        result(self?.pendingPayload)
        self?.pendingPayload = nil
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let events = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: binaryMessenger
    )
    events.setStreamHandler(self)
  }

  func handle(url: URL) {
    guard let payload = payload(for: url) else {
      return
    }

    if let eventSink {
      eventSink(payload)
    } else {
      pendingPayload = payload
    }
  }

  private func payload(for url: URL) -> [String: Any]? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let scheme = components.scheme?.lowercased() else {
      return nil
    }

    if scheme == "happ" {
      let host = components.host?.lowercased() ?? ""
      let path = components.path
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        .lowercased()
      if host == "routing" || path == "routing" || path.hasPrefix("routing/") {
        return nil
      }

      let queryItems = components.queryItems ?? []
      let importUrl = queryItems.first(where: { $0.name == "url" })?.value?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let name = queryItems.first(where: { $0.name == "name" })?.value?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

      return [
        "scheme": scheme,
        "url": importUrl.isEmpty ? url.absoluteString : importUrl,
        "name": name,
      ]
    }

    guard scheme == "hydrabox" else {
      return nil
    }

    let host = components.host?.lowercased() ?? ""
    let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    guard host == "import" || path == "import" else {
      return nil
    }

    let queryItems = components.queryItems ?? []
    guard let rawUrl = queryItems.first(where: { $0.name == "url" })?.value?.trimmingCharacters(
      in: .whitespacesAndNewlines
    ), !rawUrl.isEmpty else {
      return nil
    }

    let name = queryItems.first(where: { $0.name == "name" })?.value?.trimmingCharacters(
      in: .whitespacesAndNewlines
    ) ?? ""

    return [
      "scheme": scheme,
      "url": rawUrl,
      "name": name,
    ]
  }
}

extension HydraBoxDeepLinkBridge: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    if let pendingPayload {
      events(pendingPayload)
      self.pendingPayload = nil
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}
