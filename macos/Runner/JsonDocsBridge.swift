import Cocoa
import FlutterMacOS

/// Bridges macOS "open .json file" events to Flutter and performs
/// security-scoped read/write so the opened document can be saved in place.
///
/// Files opened before the Flutter engine is ready are buffered and drained by
/// the Dart side via `getPendingFiles`; files opened while running are pushed
/// through `openFiles`.
class JsonDocsBridge {
  static let shared = JsonDocsBridge()

  private var channel: FlutterMethodChannel?
  private var pendingPaths: [String] = []
  private var urlsByPath: [String: URL] = [:]
  private var dartReady = false

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "arbiter/json_docs", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
    self.channel = channel
  }

  /// Called from AppDelegate when the OS asks the app to open file URLs.
  func handleURLs(_ urls: [URL]) {
    var paths: [String] = []
    for url in urls where url.isFileURL {
      urlsByPath[url.path] = url
      paths.append(url.path)
    }
    guard !paths.isEmpty else { return }
    if dartReady, let channel = channel {
      channel.invokeMethod("openFiles", arguments: paths)
    } else {
      pendingPaths.append(contentsOf: paths)
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "getPendingFiles":
      dartReady = true
      let paths = pendingPaths
      pendingPaths.removeAll()
      result(paths)
    case "displayName":
      guard let path = (call.arguments as? [String: Any])?["path"] as? String else {
        result(FlutterError(code: "bad_args", message: "path required", details: nil))
        return
      }
      result(url(for: path).lastPathComponent)
    case "readFile":
      guard let path = (call.arguments as? [String: Any])?["path"] as? String else {
        result(FlutterError(code: "bad_args", message: "path required", details: nil))
        return
      }
      result(readFile(path))
    case "writeFile":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String,
            let content = args["content"] as? String else {
        result(FlutterError(code: "bad_args", message: "path and content required", details: nil))
        return
      }
      result(writeFile(path, content))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func url(for path: String) -> URL {
    return urlsByPath[path] ?? URL(fileURLWithPath: path)
  }

  private func readFile(_ path: String) -> String? {
    let url = self.url(for: path)
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    return try? String(contentsOf: url, encoding: .utf8)
  }

  private func writeFile(_ path: String, _ content: String) -> Bool {
    let url = self.url(for: path)
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      try content.write(to: url, atomically: true, encoding: .utf8)
      return true
    } catch {
      return false
    }
  }
}
