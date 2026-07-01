import Cocoa
import FlutterMacOS
import SwiftUI

// MARK: - Channel

/// Drives the macOS "Live Activity" menu bar extra (NSStatusItem + NSPopover).
///
/// Mirrors the Android foreground-service pattern: Dart pushes server / log /
/// interception state over a MethodChannel and the native side renders it; user
/// actions in the panel are sent back to Dart over the same channel.
final class MenuBarController: NSObject, NSPopoverDelegate {
  static let channelName = "auravation.arbiter.mock_server/menu_bar"

  private let channel: FlutterMethodChannel
  private let viewModel = MenuBarViewModel()

  private var statusItem: NSStatusItem?
  private var popover: NSPopover?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: MenuBarController.channelName, binaryMessenger: messenger)
    super.init()

    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }

    // Native action closures forward to Dart.
    viewModel.actions = MenuBarActions(
      onStop: { [weak self] in self?.channel.invokeMethod("stopServer", arguments: nil) },
      onContinue: { [weak self] id in
        self?.channel.invokeMethod("interceptionContinue", arguments: ["id": id])
      },
      onDrop: { [weak self] id in
        self?.channel.invokeMethod("interceptionDrop", arguments: ["id": id])
      },
      onEdit: { [weak self] id in
        // Editing the body needs the full dialog, which lives in the Flutter window.
        // Bring the app forward (the dialog already auto-opens on a pending intercept)
        // and notify Dart so it can ensure it is shown.
        NSApp.activate(ignoringOtherApps: true)
        self?.popover?.performClose(nil)
        self?.channel.invokeMethod("interceptionEdit", arguments: ["id": id])
      }
    )
  }

  // MARK: Channel dispatch

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "show":
      showStatusItem()
    case "hide":
      hideStatusItem()
    case "updateStatus":
      viewModel.running = args["running"] as? Bool ?? false
      viewModel.address = args["address"] as? String ?? "localhost"
      viewModel.port = args["port"] as? Int ?? 0
      refreshStatusTitle()
    case "pushLog":
      viewModel.addLog(
        method: args["method"] as? String ?? "GET",
        path: args["path"] as? String ?? "/",
        statusCode: args["statusCode"] as? Int ?? 0,
        responseTimeMs: args["responseTimeMs"] as? Int ?? 0
      )
      refreshStatusTitle()
    case "setIntercepted":
      viewModel.setIntercepted(
        id: args["id"] as? String ?? "",
        isResponse: (args["type"] as? String) == "response",
        method: args["method"] as? String ?? "GET",
        url: args["url"] as? String ?? "/",
        statusCode: args["statusCode"] as? Int,
        body: args["body"] as? String
      )
      refreshStatusTitle()
    case "clearIntercepted":
      viewModel.clearIntercepted()
      refreshStatusTitle()
    default:
      result(FlutterMethodNotImplemented)
      return
    }
    result(true)
  }

  // MARK: Status item lifecycle

  private func showStatusItem() {
    if statusItem != nil { return }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.target = self
    item.button?.action = #selector(togglePopover(_:))
    statusItem = item

    let popover = NSPopover()
    popover.behavior = .transient
    popover.delegate = self
    popover.contentViewController = NSHostingController(
      rootView: ArbiterPanelView(viewModel: viewModel)
    )
    self.popover = popover

    refreshStatusTitle()
  }

  private func hideStatusItem() {
    popover?.performClose(nil)
    popover = nil
    if let item = statusItem {
      NSStatusBar.system.removeStatusItem(item)
    }
    statusItem = nil
  }

  @objc private func togglePopover(_ sender: Any?) {
    guard let button = statusItem?.button, let popover = popover else { return }
    if popover.isShown {
      popover.performClose(sender)
    } else {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      popover.contentViewController?.view.window?.makeKey()
    }
  }

  /// The folded form: last endpoint + status, or the paused call-to-action.
  private func refreshStatusTitle() {
    guard let button = statusItem?.button else { return }
    button.attributedTitle = viewModel.statusBarTitle()
  }
}

// MARK: - View model

struct MenuBarActions {
  var onStop: () -> Void = {}
  var onContinue: (String) -> Void = { _ in }
  var onDrop: (String) -> Void = { _ in }
  var onEdit: (String) -> Void = { _ in }
}

struct LogRow: Identifiable {
  let id = UUID()
  let method: String
  let path: String
  let statusCode: Int
  let responseTimeMs: Int
}

struct InterceptedState {
  let id: String
  let isResponse: Bool
  let method: String
  let url: String
  let statusCode: Int?
  let body: String?
}

final class MenuBarViewModel: ObservableObject {
  @Published var running = false
  @Published var address = "localhost"
  @Published var port = 0
  @Published var logs: [LogRow] = []
  @Published var totalRequests = 0
  @Published var errorCount = 0
  @Published var feedPaused = false
  @Published var intercepted: InterceptedState?
  @Published var heldSeconds = 0

  var actions = MenuBarActions()
  private var heldTimer: Timer?

  private static let maxRows = 5

  func addLog(method: String, path: String, statusCode: Int, responseTimeMs: Int) {
    totalRequests += 1
    if statusCode >= 400 { errorCount += 1 }
    guard !feedPaused else { return }
    let row = LogRow(method: method, path: path, statusCode: statusCode, responseTimeMs: responseTimeMs)
    logs.insert(row, at: 0)
    if logs.count > MenuBarViewModel.maxRows {
      logs.removeLast(logs.count - MenuBarViewModel.maxRows)
    }
  }

  func setIntercepted(id: String, isResponse: Bool, method: String, url: String,
                      statusCode: Int?, body: String?) {
    intercepted = InterceptedState(
      id: id, isResponse: isResponse, method: method, url: url,
      statusCode: statusCode, body: body
    )
    heldSeconds = 0
    heldTimer?.invalidate()
    heldTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      self?.heldSeconds += 1
    }
  }

  func clearIntercepted() {
    intercepted = nil
    heldTimer?.invalidate()
    heldTimer = nil
  }

  var heldLabel: String {
    String(format: "held %d:%02d", heldSeconds / 60, heldSeconds % 60)
  }

  /// Attributed title shown directly in the menu bar.
  func statusBarTitle() -> NSAttributedString {
    let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
    let result = NSMutableAttributedString()

    if let held = intercepted {
      let color = held.isResponse ? Palette.blue : Palette.amber
      result.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: color, .font: mono]))
      let label = held.isResponse ? "Response intercepted" : "Request intercepted"
      result.append(NSAttributedString(string: label, attributes: [.foregroundColor: color, .font: mono]))
      return result
    }

    guard let last = logs.first else {
      result.append(NSAttributedString(string: "Arbiter", attributes: [
        .foregroundColor: Palette.text, .font: mono,
      ]))
      return result
    }

    result.append(NSAttributedString(string: last.method + " ", attributes: [
      .foregroundColor: Palette.method(last.method), .font: mono,
    ]))
    result.append(NSAttributedString(string: last.path + " ", attributes: [
      .foregroundColor: Palette.text, .font: mono,
    ]))
    result.append(NSAttributedString(string: "\(last.statusCode)", attributes: [
      .foregroundColor: Palette.status(last.statusCode), .font: mono,
    ]))
    return result
  }
}

// MARK: - Palette (matches the design tokens)

enum Palette {
  static let panelBg = NSColor(srgbRed: 0x14 / 255, green: 0x18 / 255, blue: 0x1f / 255, alpha: 1)
  static let blue = NSColor(srgbRed: 0x5f / 255, green: 0xa0 / 255, blue: 1, alpha: 1)
  static let green = NSColor(srgbRed: 0x3f / 255, green: 0xd0 / 255, blue: 0x7a / 255, alpha: 1)
  static let amber = NSColor(srgbRed: 0xf0 / 255, green: 0xa9 / 255, blue: 0x2e / 255, alpha: 1)
  static let red = NSColor(srgbRed: 1, green: 0x6b / 255, blue: 0x6b / 255, alpha: 1)
  static let text = NSColor(srgbRed: 0xcd / 255, green: 0xd6 / 255, blue: 0xe2 / 255, alpha: 1)
  static let muted = NSColor(srgbRed: 0x6b / 255, green: 0x74 / 255, blue: 0x80 / 255, alpha: 1)

  static func method(_ m: String) -> NSColor {
    switch m.uppercased() {
    case "GET", "HEAD", "OPTIONS": return blue
    case "POST": return green
    case "PUT", "PATCH": return amber
    case "DELETE", "DEL": return red
    default: return text
    }
  }

  static func status(_ code: Int) -> NSColor {
    switch code {
    case 200 ..< 300: return green
    case 300 ..< 400: return amber
    default: return code >= 400 ? red : text
    }
  }
}

extension Color {
  /// Bridges an `NSColor` to a SwiftUI `Color` without the macOS 12 `init(nsColor:)`.
  init(_ nsColor: NSColor) {
    let c = nsColor.usingColorSpace(.sRGB) ?? nsColor
    self.init(.sRGB,
              red: Double(c.redComponent),
              green: Double(c.greenComponent),
              blue: Double(c.blueComponent),
              opacity: Double(c.alphaComponent))
  }
}
