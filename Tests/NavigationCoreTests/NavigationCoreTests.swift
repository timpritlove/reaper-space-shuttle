import Foundation
import Testing
@testable import NavigationCore
import SpaceMouseKit

struct AxisShapingTests {
    let shaping = AxisShaping()

    @Test func restAndDeadZoneGiveZero() {
        #expect(shaping.shaped(.zero, fullScale: 350) == .zero)
        #expect(shaping.shaped(SpaceMouseAxes(x: 40), fullScale: 350)[.x] == 0)
    }

    @Test func fullDeflectionGivesOneWithSign() {
        #expect(shaping.shaped(SpaceMouseAxes(x: 350), fullScale: 350)[.x] == 1)
        #expect(shaping.shaped(SpaceMouseAxes(z: -400), fullScale: 350)[.z] == -1)
    }

    @Test func deflectionSetsSpeedProgressively() {
        let half = shaping.shaped(SpaceMouseAxes(x: 175), fullScale: 350)[.x]
        let most = shaping.shaped(SpaceMouseAxes(x: 300), fullScale: 350)[.x]
        #expect(half > 0 && half < 0.5)
        #expect(most > half)
    }

    @Test func crosstalkIsSuppressed() {
        // Measured worst case: sliding forward lifts z to 151 of 350.
        let shaped = shaping.shaped(SpaceMouseAxes(y: -350, z: 151), fullScale: 350)
        #expect(shaped[.y] == -1)
        #expect(shaped[.z] == 0)
    }

    @Test func deliberateDiagonalSurvives() {
        let shaped = shaping.shaped(SpaceMouseAxes(x: 300, z: 250), fullScale: 350)
        #expect(shaped[.x] > 0)
        #expect(shaped[.z] > 0)
    }

    @Test func twistScrollsLikeSliding() {
        let mapping = AxisMapping()
        let twist = shaping.shaped(SpaceMouseAxes(rz: 350), fullScale: 350)
        let slide = shaping.shaped(SpaceMouseAxes(x: 350), fullScale: 350)
        #expect(twist.value(for: .scroll, in: mapping) == 1)
        #expect(slide.value(for: .scroll, in: mapping) == 1)
        #expect(twist.value(for: .vzoom, in: mapping) == 0)
        let both = shaping.shaped(SpaceMouseAxes(x: 350, rz: 350), fullScale: 350)
        #expect(both.value(for: .scroll, in: mapping) == 1)   // limited, not 2
    }

    @Test func parsesAxisLists() {
        #expect(AxisMapping.axes(from: "x, rz") == [.x, .rz])
        #expect(AxisMapping.axes(from: "none") == [])
        #expect(AxisMapping.axes(from: "x,q") == nil)
    }

    @Test func mappingAppliesInversion() {
        var mapping = AxisMapping()
        mapping.inverted[.scroll] = true
        let shaped = shaping.shaped(SpaceMouseAxes(x: 350), fullScale: 350)
        #expect(shaped.value(for: .scroll, in: mapping) == -1)
        #expect(shaped.value(for: .zoom, in: mapping) == 0)
    }
}

struct ArrangeMotionTests {
    let view = TimeRange(start: 10, end: 20)

    @Test func scrollMovesByWidthsPerSecond() {
        let next = ArrangeMotion.step(view, scroll: 1, zoom: 0, anchor: 15, scrollSpeed: 1.5, zoomSpeed: 2, deltaTime: 0.5)
        #expect(abs(next.start - 17.5) < 1e-9)
        #expect(abs(next.width - 10) < 1e-9)
    }

    @Test func scrollFeelsTheSameAtEveryZoom() {
        let wide = ArrangeMotion.step(TimeRange(start: 0, end: 100), scroll: 1, zoom: 0, anchor: 50,
                                      scrollSpeed: 1, zoomSpeed: 1, deltaTime: 0.1)
        let narrow = ArrangeMotion.step(TimeRange(start: 0, end: 1), scroll: 1, zoom: 0, anchor: 0.5,
                                        scrollSpeed: 1, zoomSpeed: 1, deltaTime: 0.1)
        #expect(abs(wide.start / 100 - narrow.start / 1) < 1e-9)
    }

    @Test func zoomKeepsTheAnchorInPlace() {
        let anchor = 12.0
        let next = ArrangeMotion.step(view, scroll: 0, zoom: 1, anchor: anchor, scrollSpeed: 1, zoomSpeed: 2, deltaTime: 0.25)
        #expect(next.width < view.width)
        let before = (anchor - view.start) / view.width
        let after = (anchor - next.start) / next.width
        #expect(abs(before - after) < 1e-9)
    }

    @Test func zoomInAndOutCancel() {
        let zoomedIn = ArrangeMotion.step(view, scroll: 0, zoom: 1, anchor: 15, scrollSpeed: 1, zoomSpeed: 2, deltaTime: 0.3)
        let back = ArrangeMotion.step(zoomedIn, scroll: 0, zoom: -1, anchor: 15, scrollSpeed: 1, zoomSpeed: 2, deltaTime: 0.3)
        #expect(abs(back.start - view.start) < 1e-9)
        #expect(abs(back.end - view.end) < 1e-9)
    }

    @Test func manySmallStepsEqualOneBigStep() {
        var stepped = view
        for _ in 0..<60 {
            stepped = ArrangeMotion.step(stepped, scroll: 0.3, zoom: 0.4, anchor: (stepped.start + stepped.end) / 2,
                                         scrollSpeed: 1.5, zoomSpeed: 2, deltaTime: 1.0 / 60)
        }
        var coarse = view
        for _ in 0..<30 {
            coarse = ArrangeMotion.step(coarse, scroll: 0.3, zoom: 0.4, anchor: (coarse.start + coarse.end) / 2,
                                        scrollSpeed: 1.5, zoomSpeed: 2, deltaTime: 1.0 / 30)
        }
        // 30 Hz and 60 Hz end up in nearly the same place: motion follows elapsed time, not ticks.
        #expect(abs(stepped.width - coarse.width) < 1e-9)
        #expect(abs(stepped.start - coarse.start) < 0.01)
    }

    @Test func anchorChoice() {
        #expect(ArrangeMotion.anchor(.automatic, view: view, editCursor: 12, playPosition: 18) == 18)
        #expect(ArrangeMotion.anchor(.automatic, view: view, editCursor: 12, playPosition: nil) == 12)
        #expect(ArrangeMotion.anchor(.automatic, view: view, editCursor: 50, playPosition: 5) == 15)
        #expect(ArrangeMotion.anchor(.center, view: view, editCursor: 12, playPosition: 18) == 15)
        #expect(ArrangeMotion.anchor(.editCursor, view: view, editCursor: 12, playPosition: 18) == 12)
    }

    @Test func divergenceIgnoresPixelRounding() {
        let ours = TimeRange(start: 10.0004, end: 20.0004)
        let reaper = TimeRange(start: 10, end: 20)
        // 100 px/s: 0.0004 s is 0.04 px.
        #expect(!ArrangeMotion.diverged(reaper, from: ours, pixelsPerSecond: 100))
        #expect(ArrangeMotion.diverged(TimeRange(start: 0, end: 10), from: ours, pixelsPerSecond: 100))
    }
}

struct StepAccumulatorTests {
    @Test func fractionsAddUp() {
        var accumulator = StepAccumulator()
        var total = 0
        for _ in 0..<60 { total += accumulator.steps(rate: 20, deltaTime: 1.0 / 60) }
        #expect(total == 20 || total == 19)
    }

    @Test func slowRateStillMoves() {
        var accumulator = StepAccumulator()
        var total = 0
        for _ in 0..<60 { total += accumulator.steps(rate: -2, deltaTime: 1.0 / 60) }
        #expect(total <= -1)
    }

    @Test func reversingDropsTheRemainder() {
        var accumulator = StepAccumulator()
        _ = accumulator.steps(rate: 10, deltaTime: 0.09)   // 0.9 pending
        #expect(accumulator.steps(rate: -10, deltaTime: 0.05) == 0)   // not +1
    }
}

struct AutoscrollGuardTests {
    let both = AutoscrollState.on

    @Test func motionSwitchesOffAndRestAfterGraceRestores() {
        var guardState = AutoscrollGuard()
        #expect(guardState.update(now: 0, moving: true, current: both, grace: 0.75) == .off)
        #expect(guardState.update(now: 0.1, moving: true, current: .off, grace: 0.75) == nil)
        #expect(guardState.update(now: 0.2, moving: false, current: .off, grace: 0.75) == nil)
        #expect(guardState.update(now: 0.5, moving: false, current: .off, grace: 0.75) == nil)
        #expect(guardState.update(now: 0.96, moving: false, current: .off, grace: 0.75) == both)
        #expect(!guardState.isHolding)
    }

    @Test func movingAgainDuringGraceKeepsItOff() {
        var guardState = AutoscrollGuard()
        _ = guardState.update(now: 0, moving: true, current: both, grace: 0.75)
        _ = guardState.update(now: 0.2, moving: false, current: .off, grace: 0.75)
        #expect(guardState.update(now: 0.6, moving: true, current: .off, grace: 0.75) == nil)
        #expect(guardState.update(now: 1.0, moving: false, current: .off, grace: 0.75) == nil)
        #expect(guardState.update(now: 1.8, moving: false, current: .off, grace: 0.75) == both)
    }

    @Test func onlyWhatWasOnComesBack() {
        var guardState = AutoscrollGuard()
        let recordingOnly = AutoscrollState(playback: false, recording: true)
        _ = guardState.update(now: 0, moving: true, current: recordingOnly, grace: 0.5)
        #expect(guardState.update(now: 0.1, moving: false, current: .off, grace: 0.5) == nil)
        #expect(guardState.update(now: 0.7, moving: false, current: .off, grace: 0.5) == recordingOnly)
    }

    @Test func nothingHappensWhenAutoscrollIsOff() {
        var guardState = AutoscrollGuard()
        #expect(guardState.update(now: 0, moving: true, current: .off, grace: 0.5) == nil)
        #expect(guardState.update(now: 2, moving: false, current: .off, grace: 0.5) == nil)
    }

    @Test func buttonTogglesWhenIdle() {
        var guardState = AutoscrollGuard()
        #expect(guardState.toggle(current: .off) == .on)
        #expect(guardState.toggle(current: AutoscrollState(playback: true, recording: false)) == .off)
    }

    @Test func buttonWhileHoldingChangesWhatComesBack() {
        var guardState = AutoscrollGuard()
        _ = guardState.update(now: 0, moving: true, current: both, grace: 0.5)
        #expect(guardState.toggle(current: .off) == nil)       // user wants it off: nothing comes back
        _ = guardState.update(now: 0.1, moving: false, current: .off, grace: 0.5)
        #expect(guardState.update(now: 1, moving: false, current: .off, grace: 0.5) == nil)

        var other = AutoscrollGuard()
        _ = other.update(now: 0, moving: true, current: .off, grace: 0.5)
        #expect(other.toggle(current: .off) == nil)            // was off, user wants it on after the motion
        _ = other.update(now: 0.1, moving: false, current: .off, grace: 0.5)
        #expect(other.update(now: 0.7, moving: false, current: .off, grace: 0.5) == .on)
    }

    @Test func releaseRestoresAtOnce() {
        var guardState = AutoscrollGuard()
        _ = guardState.update(now: 0, moving: true, current: both, grace: 0.5)
        #expect(guardState.release(current: .off) == both)
        #expect(!guardState.isHolding)
        #expect(guardState.release(current: .off) == nil)
    }
}

struct SettingsTests {
    @Test func defaultsWithoutValues() {
        #expect(NavigationSettings(lookup: { _ in nil }) == NavigationSettings())
    }

    @Test func readsKnownKeysAndIgnoresNonsense() {
        let values = ["input": "native", "scroll_speed": "3", "deadzone": "2", "tick_rate": "30",
                      "zoom_axis": "y", "zoom_invert": "1", "zoom_anchor": "edit", "diagnostics": "1"]
        let settings = NavigationSettings { values[$0] }
        #expect(settings.input == .native)
        #expect(settings.scrollSpeed == 3)
        #expect(settings.shaping.deadzone == AxisShaping().deadzone)
        #expect(settings.tickRate == 30)
        #expect(settings.mapping[.zoom] == [.y])
        #expect(settings.mapping.inverted[.zoom] == true)
        #expect(settings.zoomAnchor == .editCursor)
        #expect(settings.diagnostics)
    }
}

struct ReturnGlideTests {
    /// Runs a glide at 60 Hz; returns the views and the number of ticks until arrival.
    private func run(from view: TimeRange, target: (Int) -> Double) -> (views: [TimeRange], ticks: Int) {
        var glide = ReturnGlide(distance: (target(0) - view.start) / view.width)
        var views = [view]
        var current = view
        for tick in 1...600 {
            let (next, arrived) = glide.step(current, targetStart: target(tick), deltaTime: 1.0 / 60)
            current = next
            views.append(next)
            if arrived { return (views, tick) }
        }
        return (views, 600)
    }

    @Test func arrivesAtAFixedTargetWithinTheDuration() {
        let view = TimeRange(start: 0, end: 10)
        let (views, ticks) = run(from: view) { _ in 200 }   // 20 widths away
        #expect(views.last?.start == 200)
        #expect(views.last?.width == 10)
        #expect(Double(ticks) / 60 <= ReturnGlide.duration(for: 20) + 0.1)
    }

    @Test func speedsUpThenSlowsDownAroundTheMiddle() {
        let (views, _) = run(from: TimeRange(start: 0, end: 10)) { _ in 200 }
        let steps = zip(views.dropFirst(), views).map { $0.start - $1.start }
        let fastest = steps.indices.max { steps[$0] < steps[$1] }!
        let positionAtFastest = views[fastest + 1].start
        #expect(positionAtFastest > 60 && positionAtFastest < 140)   // about half way
        #expect(steps.first! < steps[fastest] && steps.last! < steps[fastest])
    }

    @Test func goesBackwardsToo() {
        let (views, _) = run(from: TimeRange(start: 500, end: 510)) { _ in 100 }
        #expect(views.last?.start == 100)
        #expect(zip(views.dropFirst(), views).allSatisfy { $0.start <= $1.start })
    }

    @Test func followsAMovingPlayPosition() {
        // Zoomed in (2 s wide) while playing at 1 s/s: the target moves half a width per second.
        let (views, ticks) = run(from: TimeRange(start: 0, end: 2)) { tick in 50 + Double(tick) / 60 }
        #expect(ticks < 600)
        #expect(abs(views.last!.start - (50 + Double(ticks) / 60)) < 1e-9)
    }

    @Test func farJumpsStayShort() {
        #expect(ReturnGlide.duration(for: 0.5) < ReturnGlide.duration(for: 10))
        #expect(ReturnGlide.duration(for: 100_000) == 1.8)
    }
}

struct AutoscrollReturnTests {
    @Test func glidesBeforeRestoringWhenThePlayPositionIsOutOfSight() {
        var guardState = AutoscrollGuard()
        _ = guardState.update(now: 0, moving: true, current: .on, grace: 1.5)
        #expect(guardState.update(now: 0.1, moving: false, current: .off, grace: 1.5, needsReturn: true) == nil)
        #expect(guardState.update(now: 1.7, moving: false, current: .off, grace: 1.5, needsReturn: true) == nil)
        #expect(guardState.isReturning)
        #expect(guardState.update(now: 2.0, moving: false, current: .off, grace: 1.5, needsReturn: true) == nil)
        #expect(guardState.update(now: 2.5, moving: false, current: .off, grace: 1.5, needsReturn: false) == .on)
        #expect(!guardState.isReturning && !guardState.isHolding)
    }

    @Test func restoresAtOnceWhenThePlayPositionIsVisible() {
        var guardState = AutoscrollGuard()
        _ = guardState.update(now: 0, moving: true, current: .on, grace: 1.5)
        _ = guardState.update(now: 0.1, moving: false, current: .off, grace: 1.5, needsReturn: false)
        #expect(guardState.update(now: 1.7, moving: false, current: .off, grace: 1.5, needsReturn: false) == .on)
    }

    @Test func touchingTheCapDuringTheGlideHoldsAgain() {
        var guardState = AutoscrollGuard()
        _ = guardState.update(now: 0, moving: true, current: .on, grace: 1.5)
        _ = guardState.update(now: 0.1, moving: false, current: .off, grace: 1.5, needsReturn: true)
        _ = guardState.update(now: 1.7, moving: false, current: .off, grace: 1.5, needsReturn: true)
        #expect(guardState.isReturning)
        #expect(guardState.update(now: 1.8, moving: true, current: .off, grace: 1.5, needsReturn: true) == nil)
        #expect(!guardState.isReturning)
        _ = guardState.update(now: 1.9, moving: false, current: .off, grace: 1.5, needsReturn: true)
        #expect(guardState.update(now: 3.0, moving: false, current: .off, grace: 1.5, needsReturn: true) == nil)
        #expect(!guardState.isReturning)   // a fresh grace period first
        _ = guardState.update(now: 3.5, moving: false, current: .off, grace: 1.5, needsReturn: true)
        #expect(guardState.isReturning)
    }

    @Test func buttonDuringTheGlideCancelsIt() {
        var guardState = AutoscrollGuard()
        _ = guardState.update(now: 0, moving: true, current: .on, grace: 1.5)
        _ = guardState.update(now: 0.1, moving: false, current: .off, grace: 1.5, needsReturn: true)
        _ = guardState.update(now: 1.7, moving: false, current: .off, grace: 1.5, needsReturn: true)
        #expect(guardState.toggle(current: .off) == nil)
        #expect(!guardState.isReturning && !guardState.isHolding)
    }
}

struct HeldButtonTests {
    @Test func twistChangesTrackHeightWhileTheRightButtonIsHeld() {
        let shaped = AxisShaping().shaped(SpaceMouseAxes(rz: 350), fullScale: 350)
        let held = AxisMapping().whileHeld
        #expect(shaped.value(for: .vzoom, in: held) == 1)
        #expect(shaped.value(for: .scroll, in: held) == 0)
        let slide = AxisShaping().shaped(SpaceMouseAxes(x: 350), fullScale: 350)
        #expect(slide.value(for: .scroll, in: held) == 1)   // sliding still scrolls
    }

    @Test func clicksAndDoubleClicks() {
        var button = ModifierButton()
        button.press()
        let first = button.release(now: 0, doubleClickInterval: 0.5)
        button.press()
        let second = button.release(now: 0.3, doubleClickInterval: 0.5)
        button.press()
        let third = button.release(now: 0.5, doubleClickInterval: 0.5)
        #expect(first == .click)
        #expect(second == .doubleClick)
        #expect(third == .click)       // a double click consumes both clicks
    }

    @Test func slowClicksAreSingleClicks() {
        var button = ModifierButton()
        button.press()
        _ = button.release(now: 0, doubleClickInterval: 0.5)
        button.press()
        let late = button.release(now: 0.8, doubleClickInterval: 0.5)
        #expect(late == .click)
    }

    @Test func holdingToTwistIsNoClickAndBreaksADoubleClick() {
        var button = ModifierButton()
        button.press()
        _ = button.release(now: 0, doubleClickInterval: 0.5)
        button.press()
        button.noteUsed()
        let used = button.release(now: 0.2, doubleClickInterval: 0.5)
        button.press()
        let after = button.release(now: 0.4, doubleClickInterval: 0.5)
        #expect(used == .none)
        #expect(after == .click)
    }

    @Test func heldMappingIsASetting() {
        let settings = NavigationSettings { ["vzoom_axis_held": "ry", "vscroll_steps": "50"][$0] }
        #expect(settings.mapping.held[.vzoom] == [.ry])
        #expect(settings.verticalScrollSteps == 50)
        #expect(NavigationSettings().verticalScrollSteps == 500)
    }
}

struct SpeedTests {
    @Test func overallSpeedScalesEveryMovement() {
        let settings = NavigationSettings { ["speed": "1.5"][$0] }
        let base = NavigationSettings()
        #expect(settings.effectiveScrollSpeed == base.scrollSpeed * 1.5)
        #expect(settings.effectiveZoomSpeed == base.zoomSpeed * 1.5)
        #expect(settings.effectiveVerticalScrollSteps == base.verticalScrollSteps * 1.5)
        #expect(settings.effectiveVerticalZoomSteps == base.verticalZoomSteps * 1.5)
        #expect(base.speed == 1)
        #expect(NavigationSettings { ["speed": "0"][$0] }.speed == 1)   // out of range keeps the default
    }
}

struct VerticalGateTests {
    @Test func horizontalStartBlocksVerticalUntilItEnds() {
        var gate = VerticalGate()
        #expect(gate.filter(horizontal: 0.5, vertical: 0) == 0)
        #expect(gate.filter(horizontal: 0.3, vertical: 0.6) == 0)     // drift forward while scrolling: ignored
        #expect(gate.filter(horizontal: 0.2, vertical: 0.1) == 0)
        #expect(gate.filter(horizontal: 0, vertical: 0.4) == 0.4)     // horizontal over, still pushing: vertical
    }

    @Test func verticalStartScrollsVertically() {
        var gate = VerticalGate()
        #expect(gate.filter(horizontal: 0.1, vertical: 0.5) == 0.5)
        #expect(gate.filter(horizontal: 0.6, vertical: 0.2) == 0.2)   // stays vertical while it lasts
        #expect(gate.filter(horizontal: 0.6, vertical: 0) == 0)       // vertical ended: now horizontal
        #expect(gate.filter(horizontal: 0.4, vertical: 0.7) == 0)
    }

    @Test func restResetsTheGate() {
        var gate = VerticalGate()
        _ = gate.filter(horizontal: 0.5, vertical: 0)
        _ = gate.filter(horizontal: 0, vertical: 0)
        #expect(gate.filter(horizontal: 0, vertical: -0.3) == -0.3)
    }

    @Test func lockIsASetting() {
        #expect(NavigationSettings().verticalLock)
        #expect(!NavigationSettings { ["vertical_lock": "0"][$0] }.verticalLock)
    }
}
