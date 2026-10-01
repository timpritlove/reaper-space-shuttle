import AppKit
import NavigationCore
import SwiftUI

/// What the settings window shows; written by `Navigator`, read by `SettingsView` (ADR-0012).
@MainActor @Observable
final class SettingsModel {
    struct Message: Identifiable {
        let id = UUID()
        let date: Date
        let text: String
    }

    enum Connection: Equatable {
        case starting, connected, disconnected
        case failed(String)
    }

    var modeTitle = ""
    var modeDetail = ""
    var connection = Connection.starting
    /// Slider position, -1 … 1, 0 = normal speed (`SpeedScale`).
    var speedPosition = 0.0
    var controls: ControlsDescription?
    var messages: [Message] = []

    /// Called on every slider change; `final` when the drag ends or the value was set by a button.
    var onSpeedChange: (_ position: Double, _ final: Bool) -> Void = { _, _ in }
}

/// The panes of the settings window, listed in its sidebar like System Settings (ADR-0012).
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, speed, controls, messages

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .speed: "Speed"
        case .controls: "Controls"
        case .messages: "Messages"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .speed: "gauge.with.dots.needle.67percent"
        case .controls: "rotate.3d"
        case .messages: "text.bubble.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .speed: .blue
        case .controls: .orange
        case .messages: .green
        }
    }
}

struct SettingsView: View {
    @Bindable var model: SettingsModel
    @State private var pane: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    PaneIcon(pane: pane)
                }
            }
            .navigationSplitViewColumnWidth(190)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            let pane = pane ?? .general
            Form { content(pane) }
                .formStyle(.grouped)
                .navigationTitle(pane.title)
        }
        .frame(width: 700, height: 460)
    }

    @ViewBuilder private func content(_ pane: SettingsPane) -> some View {
        switch pane {
        case .general:
            Section("Input") {
                LabeledContent("Mode", value: model.modeTitle)
                LabeledContent("Status") { status }
                if !model.modeDetail.isEmpty {
                    Text(model.modeDetail).font(.callout).foregroundStyle(.secondary)
                }
            }
        case .speed:
            Section {
                Slider(value: speed, in: -1...1) {
                    Text("Speed")
                } minimumValueLabel: {
                    Text("Slower")
                } maximumValueLabel: {
                    Text("Faster")
                } onEditingChanged: { editing in
                    if !editing { model.onSpeedChange(model.speedPosition, true) }
                }
                HStack {
                    Text(speedText).monospacedDigit().foregroundStyle(.secondary)
                    Spacer()
                    Button("Normal") {
                        model.speedPosition = 0
                        model.onSpeedChange(0, true)
                    }
                    .disabled(model.speedPosition == 0)
                }
            } footer: {
                Text("Sets how fast every movement of the cap is, at full deflection.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        case .controls:
            if let controls = model.controls {
                Section("Cap") { lines(controls.cap) }
                Section("Buttons") { lines(controls.buttons) }
            }
        case .messages:
            Section {
                if model.messages.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ForEach(model.messages.suffix(50).reversed()) { message in
                        HStack(alignment: .firstTextBaseline) {
                            Text(message.date, style: .time).monospacedDigit().foregroundStyle(.secondary)
                            Text(message.text).textSelection(.enabled)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    private var speed: Binding<Double> {
        Binding {
            model.speedPosition
        } set: { value in
            model.speedPosition = SpeedScale.snapped(value)
            model.onSpeedChange(model.speedPosition, false)
        }
    }

    private var speedText: String {
        model.speedPosition == 0 ? "Normal" : String(format: "×%.2f", SpeedScale.speed(at: model.speedPosition))
    }

    @ViewBuilder private var status: some View {
        switch model.connection {
        case .starting: Text("Starting…")
        case .connected: Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .disconnected: Label("No SpaceMouse", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .failed(let reason): Label(reason, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    private func lines(_ lines: [ControlsDescription.Line]) -> some View {
        ForEach(lines) { line in
            LabeledContent(line.control) { Text(line.function).multilineTextAlignment(.trailing) }
        }
    }
}

/// A white symbol on a coloured rounded square, like the sidebar of System Settings.
private struct PaneIcon: View {
    let pane: SettingsPane

    var body: some View {
        Image(systemName: pane.symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(pane.tint.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// Opens and closes the settings window (action "Space Shuttle: Settings…").
@MainActor
final class SettingsWindowController {
    private let model: SettingsModel
    private var window: NSWindow?
    private var themeObserver: NSObjectProtocol?

    init(model: SettingsModel) {
        self.model = model
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        window = nil
        if let themeObserver { DistributedNotificationCenter.default().removeObserver(themeObserver) }
        themeObserver = nil
    }

    /// REAPER's Info.plist sets `NSRequiresAquaSystemAppearance`, which keeps every window of the process light;
    /// ours follows the system setting explicitly instead (ADR-0012).
    private func followSystemAppearance(_ window: NSWindow) {
        applySystemAppearance(window)
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let window = self?.window else { return }
                self?.applySystemAppearance(window)
            }
        }
    }

    private func applySystemAppearance(_ window: NSWindow) {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let style = CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication) as? String
        window.appearance = NSAppearance(named: style == "Dark" ? .darkAqua : .aqua)
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: SettingsView(model: model))
        controller.sizingOptions = .preferredContentSize
        // The sidebar runs the full height under a unified toolbar that shows the pane's title, as in System Settings.
        controller.sceneBridgingOptions = [.toolbars, .title]
        let window = EditKeysWindow(contentViewController: controller)
        window.title = "Space Shuttle"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.center()
        followSystemAppearance(window)
        return window
    }
}

/// REAPER's main menu takes Cmd-A/C/V/X/Z even while one of our text fields has focus (Cmd-Z undid the project);
/// the accelerator hook cannot stop that. Sending them to the first responder ourselves can (spike 2026-10-01,
/// docs/feasibility.md; ADR-0012). Cmd-W and Escape close the window instead of reaching REAPER.
final class EditKeysWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.function, .numericPad, .capsLock])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == .command, key == "w" {
            performClose(nil)
            return true
        }
        if firstResponder is NSText, let action = Self.editAction(modifiers: modifiers, key: key),
           NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }

    private static func editAction(modifiers: NSEvent.ModifierFlags, key: String?) -> Selector? {
        switch (modifiers, key) {
        case (.command, "a"): #selector(NSText.selectAll(_:))
        case (.command, "c"): #selector(NSText.copy(_:))
        case (.command, "v"): #selector(NSText.paste(_:))
        case (.command, "x"): #selector(NSText.cut(_:))
        case (.command, "z"): Selector(("undo:"))
        case ([.command, .shift], "z"): Selector(("redo:"))
        default: nil
        }
    }
}
