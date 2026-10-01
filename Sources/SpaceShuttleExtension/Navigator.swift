import AppKit
import NavigationCore
import ReaperKit
import SpaceMouseKit

/// Drives REAPER's arrange view from the SpaceMouse: deflection → velocity → view, integrated per tick
/// (ADR-0004 to ADR-0006). Everything runs on REAPER's main thread (ADR-0002).
@MainActor
final class Navigator {
    static let settingsSection = "spaceshuttle"
    /// The section before the rename to Space Shuttle (ADR-0013), read for keys the new section does not have yet.
    static let legacySettingsSection = "spacemouse"
    /// "View: Toggle auto-view-scroll during playback" / "… while recording"; checked by name at start.
    static let autoscrollPlayback = (command: 40036, name: "auto-view-scroll during playback")
    static let autoscrollRecording = (command: 40262, name: "auto-view-scroll while recording")
    /// Silence after which a streaming input counts as released (the device sends every ~16 ms while deflected).
    static let staleAfter = 0.25

    private let api: ReaperAPI
    private(set) var settings: NavigationSettings
    private var input: SpaceMouseInput?
    private var enabled = true
    /// Set by `hold`: no input until REAPER restarts.
    private var held = false
    private var appActive = NSApplication.shared.isActive

    private var axes = SpaceMouseAxes.zero
    private var axesTime = 0.0
    private var buttons: SpaceMouseButtons = []
    private var rightButton = ModifierButton()

    private var ticker: DispatchSourceTimer?
    private var lastTick: Double?
    private var ourView: TimeRange?
    private var verticalScroll = StepAccumulator()
    private var verticalZoom = StepAccumulator()
    private var autoscroll = AutoscrollGuard()
    private var glide: ReturnGlide?
    private var verticalGate = VerticalGate()
    private var playhead = PlayheadMotion()
    private var scrollOrPlayhead = ExclusiveGate()
    /// Found lazily: while extensions load, REAPER's own actions are not in the action list yet (seen with 7.81:
    /// only the 7 actions registered so far).
    private var resolvedAutoscrollCommands: (playback: Int, recording: Int)?
    private var autoscrollLookupDone = false
    private var autoscrollCommands: (playback: Int, recording: Int)? {
        if !autoscrollLookupDone {
            resolvedAutoscrollCommands = verifyAutoscrollCommands()
        }
        return resolvedAutoscrollCommands
    }

    /// Bumped by every LED pattern, so a newer one (or `stop`) cancels the steps of an older one.
    private var ledPattern = 0

    /// What a user may want to know (failures, fallbacks, confirmations), newest last, for a settings window to show
    /// (ADR-0011). Never put into the console unless diagnostics are on.
    private(set) var messages: [Message] = []
    static let messageLimit = 100

    struct Message {
        let date: Date
        let text: String
    }

    private var observers: [NSObjectProtocol] = []
    private var diagnostics: Diagnostics?

    /// What the settings window shows (ADR-0012).
    let model = SettingsModel()

    init(api: ReaperAPI) {
        self.api = api
        settings = Self.readSettings(api)
        model.onSpeedChange = { [weak self] position, final in self?.setSpeed(position: position, persist: final) }
    }

    private static func readSettings(_ api: ReaperAPI) -> NavigationSettings {
        var settings = NavigationSettings {
            api.extState(section: settingsSection, key: $0) ?? api.extState(section: legacySettingsSection, key: $0)
        }
        if ProcessInfo.processInfo.environment["SPACESHUTTLE_DIAGNOSTICS"] == "1" { settings.diagnostics = true }
        return settings
    }

    // MARK: - Life cycle

    func start() {
        // Look the autoscroll actions up once REAPER has registered its own actions.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in _ = self?.autoscrollCommands }
        observeActivation()
        setDiagnostics(settings.diagnostics)
        startInput(settings.input)
    }

    /// Starts without input until REAPER restarts and tells the user why (ADR-0013).
    func hold(because reason: String) {
        held = true
        setDiagnostics(settings.diagnostics)
        refreshModel()
        report(reason)
    }

    func stop() {
        releaseAutoscroll()
        stopTicking()
        if ledPattern > 0 {
            ledPattern += 1
            input?.setLED(true)
        }
        input?.stop()
        input = nil
        diagnostics = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }

    func reloadSettings() {
        let previousInput = settings.input
        settings = Self.readSettings(api)
        setDiagnostics(settings.diagnostics)
        if settings.input != previousInput {
            input?.stop()
            input = nil
            startInput(settings.input)
        }
        refreshModel()
        report("settings reloaded")
    }

    func toggleEnabled() {
        enabled.toggle()
        report("navigation \(enabled ? "on" : "off")")
        if !enabled { releaseAutoscroll() }
    }

    func toggleDiagnostics() {
        settings.diagnostics.toggle()
        setDiagnostics(settings.diagnostics)
        console("Space Shuttle: diagnostics \(settings.diagnostics ? "on" : "off")\n")
    }

    private func startInput(_ choice: NavigationSettings.InputChoice) {
        guard !held else { return }
        let registration = DriverSpaceMouse.Registration(rawValue: settings.driverRegistration) ?? .application
        let input: SpaceMouseInput = switch choice {
        case .driver: DriverSpaceMouse(registration: registration)
        case .native: NativeSpaceMouse()
        case .automatic: DriverSpaceMouse.isInstalled ? DriverSpaceMouse(registration: registration) : NativeSpaceMouse()
        }
        self.input = input
        model.connection = .starting
        refreshModel()
        log("using \(input.name)")
        input.setActive(appActive)
        input.start { [weak self, weak input] event in
            guard let self, let input, input === self.input else { return }
            self.handle(event, from: input, choice: choice)
        }
    }

    private func observeActivation() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.setAppActive(true) }
        })
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.setAppActive(false) }
        })
    }

    private func setAppActive(_ active: Bool) {
        appActive = active
        log(active ? "REAPER active" : "REAPER in background")
        input?.setActive(active)
        if !active {
            axes = .zero
            releaseAutoscroll()
        }
    }

    // MARK: - Settings window (ADR-0012)

    private func refreshModel() {
        switch input {
        case is DriverSpaceMouse:
            model.modeTitle = "3DxWare driver"
            model.modeDetail = "Through 3Dconnexion's driver. Leave the speed in the 3DxWare settings in its middle "
                + "position and set it here."
        case is NativeSpaceMouse:
            model.modeTitle = "Native"
            model.modeDetail = "Read directly, without 3Dconnexion's driver. Held only while REAPER is in front; other "
                + "apps can use the SpaceMouse meanwhile."
        default:
            model.modeTitle = "None"
            model.modeDetail = ""
        }
        model.speedPosition = SpeedScale.position(for: settings.speed)
        model.controls = ControlsDescription(settings: settings, ledFeedback: input is NativeSpaceMouse) { [api] in
            api.actionName($0)
        }
    }

    /// Takes effect at once; saved when the slider is let go.
    private func setSpeed(position: Double, persist: Bool) {
        settings.speed = SpeedScale.speed(at: position)
        guard persist else { return }
        api.setExtState(section: Self.settingsSection, key: "speed", value: String(format: "%.3f", settings.speed))
        log("speed \(String(format: "%.3f", settings.speed))")
    }

    // MARK: - Input

    private func handle(_ event: SpaceMouseEvent, from input: SpaceMouseInput, choice: NavigationSettings.InputChoice) {
        diagnostics?.note(event)
        switch event {
        case .connected(let what):
            model.connection = .connected
            log("connected: \(what)")
        case .disconnected:
            model.connection = .disconnected
            log("disconnected")
            axes = .zero
            releaseAutoscroll()
        case .failed(let reason):
            model.connection = .failed(reason)
            report("\(input.name): \(reason)")
            if choice == .automatic, input is DriverSpaceMouse {
                report("falling back to native HID")
                input.stop()
                self.input = nil
                startInput(.native)
            }
        case .axes(let value):
            axes = value
            axesTime = now
            if !value.isZero { startTicking() }
        case .buttons(let value):
            let pressed = SpaceMouseButtons(rawValue: value.rawValue & ~buttons.rawValue)
            let released = SpaceMouseButtons(rawValue: buttons.rawValue & ~value.rawValue)
            buttons = value
            guard enabled, appActive else {
                _ = rightButton.release(now: now, doubleClickInterval: 0)
                return
            }
            if pressed.contains(.left) { toggleAutoscroll() }
            if pressed.contains(.right) { rightButton.press() }
            if released.contains(.right) {
                // The double-click interval from System Settings (a good citizen, not our own constant).
                let action = switch rightButton.release(now: now, doubleClickInterval: NSEvent.doubleClickInterval) {
                case .none: 0
                case .click: settings.rightClickAction
                case .doubleClick: settings.rightDoubleClickAction
                }
                if action > 0 { api.run(action) }
            }
        }
    }

    // MARK: - Ticking

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    private func startTicking() {
        guard ticker == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1 / settings.tickRate, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.tick() } }
        ticker = timer
        lastTick = nil
        timer.resume()
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
        lastTick = nil
        ourView = nil
        verticalScroll.reset()
        verticalZoom.reset()
        verticalGate = VerticalGate()
        playhead.reset()
        scrollOrPlayhead = ExclusiveGate()
    }

    private func tick() {
        let time = now
        let deltaTime = min(time - (lastTick ?? time - 1 / settings.tickRate), 0.1)
        lastTick = time
        diagnostics?.ticks += 1

        var effective = axes
        if !enabled || !appActive { effective = .zero }
        if let input, input.streamsWhileDeflected, time - axesTime > Self.staleAfter { effective = .zero }

        let shaped = settings.shaping.shaped(effective, fullScale: settings.fullScale)
        let mapping = rightButton.isHeld ? settings.mapping.whileHeld : settings.mapping
        let zoom = shaped.value(for: .zoom, in: mapping)
        let playState = api.playState
        // Never while recording; scrolling and the play cursor exclude each other (ADR-0014).
        let (scroll, playheadValue) = scrollOrPlayhead.filter(
            shaped.value(for: .scroll, in: mapping),
            playState & 4 != 0 ? 0 : shaped.value(for: .playhead, in: mapping))
        var verticalValue = shaped.value(for: .vscroll, in: mapping)
        if settings.verticalLock {
            verticalValue = verticalGate.filter(horizontal: max(abs(scroll), abs(zoom), abs(playheadValue)),
                                                vertical: verticalValue)
        }
        let verticalScrollRate = verticalValue * settings.effectiveVerticalScrollSteps
        let verticalZoomRate = shaped.value(for: .vzoom, in: mapping) * settings.effectiveVerticalZoomSteps
        if rightButton.isHeld, settings.mapping.held.keys.contains(where: { shaped.value(for: $0, in: mapping) != 0 }) {
            rightButton.noteUsed()
        }
        let horizontal = scroll != 0 || zoom != 0

        let playing = playState & 5 != 0
        var gliding = false
        if horizontal {
            glide = nil
            moveArrangeView(scroll: scroll, zoom: zoom, playing: playing, deltaTime: deltaTime)
        } else if autoscroll.isReturning, playing {
            gliding = glideToPlayPosition(deltaTime: deltaTime)
        } else {
            glide = nil
            ourView = nil
        }
        if playheadValue != 0 {
            movePlayhead(playheadValue, playState: playState, deltaTime: deltaTime)
        } else {
            playhead.reset()
        }
        let rows = verticalScroll.steps(rate: verticalScrollRate, deltaTime: deltaTime)
        if rows != 0 { api.scroll(x: 0, y: rows) }
        let heights = verticalZoom.steps(rate: verticalZoomRate, deltaTime: deltaTime)
        if heights != 0 { api.zoom(x: 0, y: heights) }

        if let commands = autoscrollCommands {
            let current = readAutoscroll(commands)
            // Idle: return only if the play position is out of sight; returning: until the glide arrived.
            let needsReturn = playing && (autoscroll.isReturning ? gliding : !playPositionVisible())
            let wasReturning = autoscroll.isReturning
            if let target = autoscroll.update(now: time, moving: horizontal, current: current,
                                              grace: settings.autoscrollGrace, needsReturn: needsReturn) {
                apply(target, current: current, commands: commands)
            }
            if autoscroll.isReturning != wasReturning {
                log(autoscroll.isReturning ? "gliding back to the play position" : "glide ended")
            }
        }

        let resting = !horizontal && playheadValue == 0 && verticalScrollRate == 0 && verticalZoomRate == 0
        if resting && !autoscroll.isHolding { stopTicking() }
    }

    /// REAPER's view, or our own fractional one while REAPER only rounded it (ADR-0004).
    private func baseView() -> TimeRange {
        let current = api.arrangeView()
        let reaperView = TimeRange(start: current.start, end: current.end)
        if let ourView, !ArrangeMotion.diverged(reaperView, from: ourView, pixelsPerSecond: api.horizontalZoom) {
            return ourView
        }
        return reaperView
    }

    private func setView(_ view: TimeRange) {
        api.setArrangeView(start: view.start, end: view.end)
        ourView = view
        diagnostics?.viewSets += 1
    }

    private func playPositionVisible() -> Bool {
        let view = api.arrangeView()
        return TimeRange(start: view.start, end: view.end).contains(api.playPosition)
    }

    private func moveArrangeView(scroll: Double, zoom: Double, playing: Bool, deltaTime: Double) {
        let base = baseView()
        let anchor = ArrangeMotion.anchor(settings.zoomAnchor, view: base, editCursor: api.editCursor,
                                          playPosition: playing ? api.playPosition : nil)
        setView(ArrangeMotion.step(base, scroll: scroll, zoom: zoom, anchor: anchor,
                                   scrollSpeed: settings.effectiveScrollSpeed, zoomSpeed: settings.effectiveZoomSpeed,
                                   deltaTime: deltaTime))
    }

    /// Moves the play cursor (ADR-0014): the edit cursor while stopped, the play position while playing or paused.
    private func movePlayhead(_ value: Double, playState: Int, deltaTime: Double) {
        let transport = playState & 3 != 0
        let running = playState & 1 != 0 && playState & 2 == 0
        let view = ourView ?? {
            let current = api.arrangeView()
            return TimeRange(start: current.start, end: current.end)
        }()
        let position = playhead.step(reaper: transport ? api.playPosition : api.editCursor,
                                     playRate: running ? api.playRate : 0, value: value,
                                     speed: settings.effectivePlayheadSpeed, viewWidth: view.width,
                                     deltaTime: deltaTime)
        api.setEditCursor(position, seekPlay: transport)
        diagnostics?.playheadSets += 1
    }

    /// One step of the glide back to the play position (ADR-0006). Returns true while still under way.
    private func glideToPlayPosition(deltaTime: Double) -> Bool {
        let base = baseView()
        let targetStart = api.playPosition - settings.returnPosition * base.width
        var current = glide ?? ReturnGlide(distance: (targetStart - base.start) / base.width)
        let (next, arrived) = current.step(base, targetStart: targetStart, deltaTime: deltaTime)
        setView(next)
        glide = arrived ? nil : current
        return !arrived
    }

    // MARK: - Autoscroll (ADR-0006)

    /// Finds both autoscroll toggles by name in the action list; IDs are only the expected values.
    private func verifyAutoscrollCommands() -> (playback: Int, recording: Int)? {
        let actions = api.mainActions()
        // Too early while REAPER is still starting; try again on the next use.
        guard actions.count > 100 else { return nil }
        autoscrollLookupDone = true
        func find(_ check: (command: Int, name: String)) -> Int? {
            let matches = actions.filter { $0.name.localizedCaseInsensitiveContains(check.name) }
            for match in matches { log("action \(match.command): \(match.name)") }
            return matches.first { $0.command == check.command }?.command ?? matches.first?.command
        }
        guard let playback = find(Self.autoscrollPlayback), let recording = find(Self.autoscrollRecording) else {
            report("autoscroll actions not found among \(actions.count) actions; autoscroll handling is off")
            return nil
        }
        return (playback, recording)
    }

    private func readAutoscroll(_ commands: (playback: Int, recording: Int)) -> AutoscrollState {
        AutoscrollState(playback: api.toggleState(commands.playback) == 1,
                        recording: api.toggleState(commands.recording) == 1)
    }

    private func apply(_ target: AutoscrollState, current: AutoscrollState, commands: (playback: Int, recording: Int)) {
        if target.playback != current.playback { api.run(commands.playback) }
        if target.recording != current.recording { api.run(commands.recording) }
        log("autoscroll playback \(target.playback ? "on" : "off"), recording \(target.recording ? "on" : "off")")
    }

    private func toggleAutoscroll() {
        guard let commands = autoscrollCommands else { return }
        let current = readAutoscroll(commands)
        if let target = autoscroll.toggle(current: current) {
            apply(target, current: current, commands: commands)
            flashLED(autoscrollOn: target.any)
        } else {
            log("autoscroll after rest: \(autoscroll.suspended.any ? "on" : "off")")
            flashLED(autoscrollOn: autoscroll.suspended.any)
        }
    }

    /// Confirms the button at the device (ADR-0010): one flash for on, two for off.
    private func flashLED(autoscrollOn: Bool) {
        guard let input else { return }
        ledPattern += 1
        let pattern = ledPattern
        for step in LEDFlash.autoscroll(on: autoscrollOn) {
            DispatchQueue.main.asyncAfter(deadline: .now() + step.delay) { [weak self, weak input] in
                guard let self, let input, input === self.input, pattern == self.ledPattern else { return }
                input.setLED(step.on)
            }
        }
    }

    private func releaseAutoscroll() {
        guard let commands = autoscrollCommands else { return }
        let current = readAutoscroll(commands)
        if let target = autoscroll.release(current: current) { apply(target, current: current, commands: commands) }
    }

    // MARK: - Diagnostics

    /// Development log file (`SPACESHUTTLE_LOG`, set by `make run`), so console output can be read outside REAPER.
    private static let logFile: FileHandle? = {
        guard let path = ProcessInfo.processInfo.environment["SPACESHUTTLE_LOG"] else { return nil }
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()

    /// Writes to REAPER's console (which opens it) and, during development, to the log file. Only for diagnostics
    /// and the diagnostics action itself (ADR-0011).
    private func console(_ text: String) {
        api.showConsoleMessage(text)
        writeLogFile(text)
    }

    private func writeLogFile(_ text: String) {
        guard let file = Self.logFile else { return }
        let stamp = String(format: "%.3f ", now)
        file.write(Data((stamp + text).utf8))
    }

    /// A message for the user: kept in `messages`, shown in the console only while diagnostics are on.
    private func report(_ message: String) {
        messages.append(Message(date: Date(), text: message))
        if messages.count > Self.messageLimit { messages.removeFirst(messages.count - Self.messageLimit) }
        model.messages = messages.map { SettingsModel.Message(date: $0.date, text: $0.text) }
        if settings.diagnostics {
            console("Space Shuttle: \(message)\n")
        } else {
            writeLogFile("Space Shuttle: \(message)\n")
        }
    }

    private func log(_ message: String) {
        guard settings.diagnostics else { return }
        console("Space Shuttle: \(message)\n")
    }

    private func setDiagnostics(_ on: Bool) {
        guard on != (diagnostics != nil) else { return }
        guard on else {
            diagnostics = nil
            return
        }
        let diagnostics = Diagnostics { [weak self] line in self?.console(line) }
        self.diagnostics = diagnostics
        console("Space Shuttle: diagnostics on, REAPER \(api.appVersion), input \(settings.input.rawValue), "
            + "autoscroll actions \(resolvedAutoscrollCommands == nil ? "not yet found" : "found")\n")
        diagnostics.start()
    }
}

/// Once a second: what came in and what we did, to learn how the driver and REAPER behave (spike).
@MainActor
private final class Diagnostics {
    var ticks = 0
    var viewSets = 0
    var playheadSets = 0
    private var axisEvents = 0
    private var zeroEvents = 0
    private var peak = SpaceMouseAxes.zero
    private var last = SpaceMouseAxes.zero
    private var timer: DispatchSourceTimer?
    private let write: @MainActor (String) -> Void

    init(write: @escaping @MainActor (String) -> Void) { self.write = write }

    deinit { timer?.cancel() }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.flush() } }
        self.timer = timer
        timer.resume()
    }

    func note(_ event: SpaceMouseEvent) {
        switch event {
        case .axes(let axes):
            axisEvents += 1
            if axes.isZero { zeroEvents += 1 }
            last = axes
            peak = SpaceMouseAxes(x: max(peak.x, abs(axes.x)), y: max(peak.y, abs(axes.y)), z: max(peak.z, abs(axes.z)),
                                  rx: max(peak.rx, abs(axes.rx)), ry: max(peak.ry, abs(axes.ry)), rz: max(peak.rz, abs(axes.rz)))
        case .buttons(let buttons):
            write("Space Shuttle: buttons 0x\(String(buttons.rawValue, radix: 16))\n")
        default:
            break
        }
    }

    private func flush() {
        guard axisEvents > 0 || ticks > 0 else { return }
        write("Space Shuttle: \(axisEvents) axis events/s (\(zeroEvents) zero), \(ticks) ticks, \(viewSets) view sets, "
            + "\(playheadSets) play cursor sets; "
            + "last [\(last)] peak [\(peak)]\n")
        axisEvents = 0
        zeroEvents = 0
        ticks = 0
        viewSets = 0
        playheadSets = 0
        peak = .zero
    }
}
