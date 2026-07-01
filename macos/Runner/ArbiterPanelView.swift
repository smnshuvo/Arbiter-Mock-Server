import SwiftUI

/// The expanded drop-down panel for the menu bar Live Activity.
///
/// Two faces: the live request feed (normal) and the intercepted call-to-action
/// (when a request/response is being held). Styling tracks the Claude Design spec
/// "Arbiter Live Activity - macOS".
struct ArbiterPanelView: View {
  @ObservedObject var viewModel: MenuBarViewModel

  var body: some View {
    VStack(spacing: 0) {
      if let held = viewModel.intercepted {
        InterceptedView(viewModel: viewModel, held: held)
      } else {
        feed
      }
    }
    .frame(width: 320)
    .background(Color(Palette.panelBg))
  }

  // MARK: Live feed

  private var feed: some View {
    VStack(spacing: 0) {
      header
      Divider().background(Color.white.opacity(0.07))
      if viewModel.logs.isEmpty {
        Text("Waiting for requests…")
          .font(.system(size: 12, design: .monospaced))
          .foregroundColor(Color(Palette.muted))
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 15)
          .padding(.vertical, 18)
      } else {
        ForEach(viewModel.logs) { row in
          LogRowView(row: row)
          Divider().background(Color.white.opacity(0.04))
        }
      }
      footer
    }
  }

  private var header: some View {
    HStack(spacing: 10) {
      PulseDot()
      Text("Arbiter")
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(Color(Palette.text))
      Text("\(viewModel.address):\(viewModel.port)")
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(Color(Palette.muted))
      Spacer()
      Text(viewModel.running ? "RUNNING" : "STOPPED")
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundColor(Color(viewModel.running ? Palette.green : Palette.muted))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(Color(viewModel.running ? Palette.green : Palette.muted).opacity(0.12))
        )
    }
    .padding(.horizontal, 15).padding(.vertical, 13)
  }

  private var footer: some View {
    HStack(spacing: 8) {
      PanelButton(title: viewModel.feedPaused ? "Resume" : "Pause") {
        viewModel.feedPaused.toggle()
      }
      PanelButton(title: "Stop", destructive: true) {
        viewModel.actions.onStop()
      }
      Spacer()
      Text("\(viewModel.totalRequests) reqs · \(viewModel.errorCount) errors")
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(Color(Palette.muted))
    }
    .padding(.horizontal, 15).padding(.vertical, 11)
    .overlay(Rectangle().frame(height: 1).foregroundColor(Color.white.opacity(0.07)), alignment: .top)
  }
}

// MARK: - Rows

struct LogRowView: View {
  let row: LogRow

  var body: some View {
    HStack(spacing: 10) {
      Text(row.method)
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .foregroundColor(Color(Palette.method(row.method)))
        .frame(width: 46, alignment: .leading)
      Text(row.path)
        .font(.system(size: 12, design: .monospaced))
        .foregroundColor(Color(Palette.text))
        .lineLimit(1).truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
      Text("\(row.responseTimeMs)ms")
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(Color(Palette.muted))
      Text("\(row.statusCode)")
        .font(.system(size: 12, weight: .bold, design: .monospaced))
        .foregroundColor(Color(Palette.status(row.statusCode)))
        .frame(width: 30, alignment: .trailing)
    }
    .padding(.horizontal, 15).padding(.vertical, 9)
  }
}

// MARK: - Intercepted call-to-action

struct InterceptedView: View {
  @ObservedObject var viewModel: MenuBarViewModel
  let held: InterceptedState

  private var accent: NSColor { held.isResponse ? Palette.blue : Palette.amber }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SweepBar(color: Color(accent))
      VStack(alignment: .leading, spacing: 13) {
        HStack(spacing: 9) {
          Circle().fill(Color(accent)).frame(width: 9, height: 9)
          Text(held.isResponse ? "Response intercepted" : "Request intercepted")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Color(accent))
          Spacer()
          Text(viewModel.heldLabel)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(Color(Palette.muted))
        }

        HStack(spacing: 10) {
          Text(held.method)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(Color(Palette.method(held.method)))
          Text(held.url)
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(Color(Palette.text))
            .lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
          if let code = held.statusCode {
            Text("\(code)")
              .font(.system(size: 12, weight: .bold, design: .monospaced))
              .foregroundColor(Color(Palette.status(code)))
          } else {
            Text("→ outbound")
              .font(.system(size: 11, design: .monospaced))
              .foregroundColor(Color(Palette.muted))
          }
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.04)))

        if let body = held.body, !body.isEmpty {
          Text(body)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(Color(Palette.muted))
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.35)))
        }

        HStack(spacing: 9) {
          PanelButton(title: "Continue →", primary: true) {
            viewModel.actions.onContinue(held.id)
          }
          PanelButton(title: held.isResponse ? "Edit body" : "Edit") {
            viewModel.actions.onEdit(held.id)
          }
          PanelButton(title: "Drop", destructive: true) {
            viewModel.actions.onDrop(held.id)
          }
        }
      }
      .padding(16)
    }
  }
}

// MARK: - Reusable bits

struct PulseDot: View {
  @State private var animating = false
  var body: some View {
    Circle()
      .fill(Color(Palette.green))
      .frame(width: 8, height: 8)
      .overlay(
        Circle()
          .stroke(Color(Palette.green), lineWidth: 2)
          .scaleEffect(animating ? 2.4 : 1)
          .opacity(animating ? 0 : 1)
      )
      .onAppear {
        withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) {
          animating = true
        }
      }
  }
}

struct SweepBar: View {
  let color: Color
  @State private var offset: CGFloat = -1
  var body: some View {
    GeometryReader { geo in
      Rectangle()
        .fill(color)
        .frame(width: geo.size.width * 0.4)
        .offset(x: offset * geo.size.width)
        .onAppear {
          withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
            offset = 1.2
          }
        }
    }
    .frame(height: 3)
    .background(color.opacity(0.25))
    .clipped()
  }
}

struct PanelButton: View {
  let title: String
  var primary: Bool = false
  var destructive: Bool = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(foreground)
        .padding(.vertical, 8).padding(.horizontal, 12)
        .frame(maxWidth: primary ? .infinity : nil)
        .background(RoundedRectangle(cornerRadius: 8).fill(background))
    }
    .buttonStyle(.plain)
  }

  private var foreground: Color {
    if primary { return Color(NSColor(srgbRed: 0x06 / 255, green: 0x12 / 255, blue: 0x1f / 255, alpha: 1)) }
    if destructive { return Color(NSColor(srgbRed: 1, green: 0xb4 / 255, blue: 0xb4 / 255, alpha: 1)) }
    return Color(Palette.text)
  }

  private var background: Color {
    if primary { return Color(Palette.blue) }
    if destructive { return Color(Palette.red).opacity(0.12) }
    return Color.white.opacity(0.07)
  }
}
