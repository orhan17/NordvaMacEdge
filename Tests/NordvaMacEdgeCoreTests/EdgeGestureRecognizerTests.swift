import Testing
@testable import NordvaMacEdgeCore

/// Most tests check gesture logic, not the brush filter, so side slides may start at once.
private func instantSideSlides() -> EdgeGestureRecognizer.Config {
    var config = EdgeGestureRecognizer.Config()
    config.minSideSlideAge = 0
    return config
}

/// Feeds frames 10 ms apart by default, like the real trackpad.
private struct Driver {
    var recognizer = EdgeGestureRecognizer(config: instantSideSlides())
    var time = 0.0
    var buttonDown = false

    mutating func frame(_ touches: [TouchPoint], after step: Double = 0.01) -> [GestureEvent] {
        time += step
        return recognizer.process(touches, at: time, isButtonDown: buttonDown)
    }

    mutating func frames(_ list: [[TouchPoint]]) -> [GestureEvent] {
        list.flatMap { frame($0) }
    }

    mutating func tap(_ x: Double, _ y: Double, after pause: Double = 0.01, holding: Double = 0.08) -> [GestureEvent] {
        frame(finger(x, y), after: pause) + frame([], after: holding)
    }

    var holdsPointer: Bool { recognizer.holdsPointer }
}

private func finger(_ x: Double, _ y: Double, id: Int32 = 1) -> [TouchPoint] {
    [TouchPoint(id: id, x: x, y: y)]
}

private func totalDelta(_ events: [GestureEvent]) -> Double {
    events.reduce(0) { sum, event in
        if case let .moved(_, delta) = event { return sum + delta }
        return sum
    }
}

private func doubleTaps(_ events: [GestureEvent]) -> [Corner] {
    events.compactMap { event in
        if case let .doubleTapped(corner) = event { return corner }
        return nil
    }
}

// MARK: - Side edges

@Test func slideUpOnRightEdge() {
    var d = Driver()
    let events = d.frames([finger(0.97, 0.20), finger(0.97, 0.24), finger(0.97, 0.34), finger(0.97, 0.44), []])
    #expect(events.first == .began(.right))
    #expect(events.last == .ended(.right))
    #expect(abs(totalDelta(events) - 0.24) < 0.0001) // the whole travel from touch-down
}

@Test func slideDownOnLeftEdgeGivesNegativeDelta() {
    var d = Driver()
    let events = d.frames([finger(0.02, 0.7), finger(0.02, 0.65), finger(0.02, 0.5), []])
    #expect(events.first == .began(.left))
    #expect(totalDelta(events) < 0)
}

@Test func fingerStartedInCenterAndReachedEdgeIsJustCursor() {
    var d = Driver()
    #expect(d.frames([finger(0.5, 0.5), finger(0.97, 0.5), finger(0.97, 0.9), []]).isEmpty)
}

@Test func horizontalMoveFromEdgeReleasesPointer() {
    var d = Driver()
    #expect(d.frame(finger(0.97, 0.5)).isEmpty)
    #expect(d.holdsPointer)
    #expect(d.frame(finger(0.90, 0.5)).isEmpty)
    #expect(!d.holdsPointer)
    #expect(d.frame(finger(0.90, 0.9)).isEmpty)
}

@Test func tapOnEdgeOutsideCornersProducesNothing() {
    var d = Driver()
    #expect(d.frames([finger(0.97, 0.5), finger(0.97, 0.505), []]).isEmpty)
    #expect(!d.holdsPointer)
}

@Test func twoFingersFromStartAreIgnored() {
    var d = Driver()
    let two = [TouchPoint(id: 1, x: 0.97, y: 0.2), TouchPoint(id: 2, x: 0.5, y: 0.2)]
    #expect(d.frames([two, two, []]).isEmpty)
}

@Test func secondFingerDuringCandidateCancels() {
    var d = Driver()
    _ = d.frame(finger(0.97, 0.2))
    let two = [TouchPoint(id: 1, x: 0.97, y: 0.4), TouchPoint(id: 2, x: 0.5, y: 0.2)]
    #expect(d.frame(two).isEmpty)
    #expect(!d.holdsPointer)
}

@Test func secondFingerDuringSlideEndsIt() {
    var d = Driver()
    #expect(d.frames([finger(0.97, 0.2), finger(0.97, 0.3)]).first == .began(.right))
    let two = [TouchPoint(id: 1, x: 0.97, y: 0.4), TouchPoint(id: 2, x: 0.5, y: 0.2)]
    #expect(d.frame(two) == [.ended(.right)])
    #expect(d.frame(finger(0.97, 0.6)).isEmpty)
    #expect(!d.holdsPointer)
}

@Test func pressedButtonMeansDragNotSlide() {
    var d = Driver()
    d.buttonDown = true
    #expect(d.frames([finger(0.97, 0.2), finger(0.97, 0.4), []]).isEmpty)
}

@Test func pointerIsHeldThroughWholeSlide() {
    var d = Driver()
    #expect(!d.holdsPointer)
    _ = d.frame(finger(0.97, 0.2))
    #expect(d.holdsPointer)
    _ = d.frame(finger(0.97, 0.4))
    #expect(d.holdsPointer)
    _ = d.frame([])
    #expect(!d.holdsPointer)
}

@Test func worksAgainAfterLift() {
    var d = Driver()
    _ = d.frames([finger(0.97, 0.2), finger(0.97, 0.4), []])
    #expect(d.frames([finger(0.02, 0.4), finger(0.02, 0.6), []])
        == [.began(.left), .moved(.left, delta: 0.6 - 0.4), .ended(.left)])
}

// MARK: - Brushes past the edge

/// The finger moves along y by `step` per 10 ms frame, then lifts.
private func edgeStroke(x: Double = 0.985, from y: Double, step: Double, frames count: Int) -> [[TouchPoint]] {
    [finger(x, y)] + (1...count).map { finger(x, y + step * Double($0)) } + [[]]
}

@Test func quickBrushAtTheEdgeLeavesTheVolumeAlone() {
    // Like the logged false triggers: 0.1 s at the very edge, about 4 mm of travel.
    var d = Driver()
    d.recognizer = EdgeGestureRecognizer()
    #expect(d.frames(edgeStroke(from: 0.30, step: 0.005, frames: 10)).isEmpty)
}

@Test func realSlideStartsAfterTheDelayWithoutLosingTravel() {
    var d = Driver()
    d.recognizer = EdgeGestureRecognizer()
    let events = d.frames(edgeStroke(from: 0.30, step: 0.005, frames: 40))
    #expect(events.first == .began(.right))
    #expect(abs(totalDelta(events) - 0.2) < 0.0001)
}

@Test func sidewaysMoveDuringTheDelayStillFreesThePointer() {
    var d = Driver()
    d.recognizer = EdgeGestureRecognizer()
    _ = d.frame(finger(0.97, 0.5))
    #expect(d.holdsPointer)
    #expect(d.frame(finger(0.90, 0.5)).isEmpty)
    #expect(!d.holdsPointer)
}

@Test func disabledEdgeIsOrdinaryTrackpad() {
    var d = Driver()
    d.recognizer.config.enabledEdges = [.left]
    #expect(d.frames([finger(0.97, 0.2), finger(0.97, 0.4), []]).isEmpty)
    #expect(!d.holdsPointer)
    #expect(d.frames([finger(0.02, 0.4), finger(0.02, 0.6), []])
        == [.began(.left), .moved(.left, delta: 0.6 - 0.4), .ended(.left)])
}

@Test func resetReleasesPointer() {
    var d = Driver()
    _ = d.frame(finger(0.97, 0.2))
    d.recognizer.reset()
    #expect(!d.holdsPointer)
}

// MARK: - Corner taps

@Test func doubleTapTopLeft() {
    var d = Driver()
    #expect(d.tap(0.03, 0.95) == [.tapped(.topLeft)])
    #expect(d.tap(0.04, 0.93, after: 0.15) == [.tapped(.topLeft), .doubleTapped(.topLeft)])
}

@Test func doubleTapBottomRight() {
    var d = Driver()
    let events = d.tap(0.95, 0.05) + d.tap(0.94, 0.08, after: 0.2)
    #expect(doubleTaps(events) == [.bottomRight])
}

@Test func inactiveCornersAreOrdinaryTrackpad() {
    var d = Driver()
    let events = d.tap(0.03, 0.05) + d.tap(0.03, 0.05, after: 0.15)
        + d.tap(0.97, 0.95, after: 0.5) + d.tap(0.97, 0.95, after: 0.15)
    #expect(events.isEmpty)
}

@Test func swappedCornersFollowEdges() {
    var d = Driver()
    d.recognizer.config.activeCorners = [.topRight, .bottomLeft]
    let events = d.tap(0.97, 0.95) + d.tap(0.97, 0.95, after: 0.15)
        + d.tap(0.03, 0.05, after: 0.5) + d.tap(0.03, 0.05, after: 0.15)
        + d.tap(0.03, 0.95, after: 0.5) + d.tap(0.03, 0.95, after: 0.15)
    #expect(doubleTaps(events) == [.topRight, .bottomLeft])
}

@Test func cornerIsWiderThanEdge() {
    var d = Driver()
    let events = d.tap(0.10, 0.9) + d.tap(0.10, 0.9, after: 0.15)
    #expect(doubleTaps(events) == [.topLeft])
}

@Test func slowSecondTapIsNotDouble() {
    var d = Driver()
    let events = d.tap(0.03, 0.95) + d.tap(0.03, 0.95, after: 0.6)
    #expect(doubleTaps(events).isEmpty)
}

@Test func longPressIsNotTap() {
    var d = Driver()
    #expect(d.tap(0.03, 0.95, holding: 0.5).isEmpty)
}

@Test func tapsInDifferentCornersAreNotDouble() {
    var d = Driver()
    let events = d.tap(0.03, 0.95) + d.tap(0.97, 0.05, after: 0.15)
    #expect(events == [.tapped(.topLeft), .tapped(.bottomRight)])
}

@Test func touchElsewhereBetweenTapsBreaksDouble() {
    var d = Driver()
    let events = d.tap(0.03, 0.95) + d.tap(0.5, 0.5, after: 0.05) + d.tap(0.03, 0.95, after: 0.05)
    #expect(doubleTaps(events).isEmpty)
}

@Test func tripleTapFiresOnce() {
    var d = Driver()
    let events = d.tap(0.03, 0.95) + d.tap(0.03, 0.95, after: 0.15) + d.tap(0.03, 0.95, after: 0.15)
    #expect(doubleTaps(events) == [.topLeft])
}

@Test func physicalClickInCornerIsNotTap() {
    var d = Driver()
    d.buttonDown = true
    let events = d.frames([finger(0.97, 0.05), finger(0.97, 0.05), []])
    #expect(events.isEmpty)
}

@Test func slideFromCornerStillControlsBrightness() {
    var d = Driver()
    let events = d.frames([finger(0.03, 0.95), finger(0.03, 0.90), finger(0.03, 0.7), []])
    #expect(events.first == .began(.left))
    #expect(!events.contains(.tapped(.topLeft)))
}

@Test func verticalMoveInCornerOutsideEdgeIsCursor() {
    var d = Driver()
    #expect(d.frames([finger(0.10, 0.9), finger(0.10, 0.85), finger(0.10, 0.7), []]).isEmpty)
}

@Test func tapsAroundSlideDoNotPair() {
    var d = Driver()
    _ = d.tap(0.03, 0.95)
    _ = d.frames([finger(0.03, 0.95), finger(0.03, 0.9), []])
    #expect(doubleTaps(d.tap(0.03, 0.95, after: 0.05)).isEmpty)
}

// MARK: - Bottom edge app switcher

private func bottomDriver() -> Driver {
    var d = Driver()
    d.recognizer.config.bottomEdgeEnabled = true
    return d
}

/// The finger rests for `rest` seconds, then moves along x by `step` per 10 ms frame.
private func slide(
    from x: Double, y: Double = 0.03, step: Double, frames count: Int, rest: Double = 0
) -> [[TouchPoint]] {
    let still = Array(repeating: finger(x, y), count: Int(rest / 0.01) + 1)
    let moving = (1...count).map { finger(x + step * Double($0), y) }
    return still + moving + [[]]
}

@Test func slowSlideAlongBottomOpensSwitcher() {
    var d = bottomDriver()
    let events = d.frames(slide(from: 0.3, step: 0.002, frames: 60))
    #expect(events.first == .began(.bottom))
    #expect(events.last == .ended(.bottom))
    #expect(totalDelta(events) > 0)
}

@Test func slowSlideLeftGivesNegativeDelta() {
    var d = bottomDriver()
    let events = d.frames(slide(from: 0.7, step: -0.002, frames: 60))
    #expect(events.first == .began(.bottom))
    #expect(totalDelta(events) < 0)
}

@Test func fastSlideAlongBottomIsCursor() {
    var d = bottomDriver()
    #expect(d.frames(slide(from: 0.3, step: 0.01, frames: 20)).isEmpty)
}

@Test func restThenFastSlideIsCursor() {
    var d = bottomDriver()
    #expect(d.frames(slide(from: 0.3, step: 0.01, frames: 20, rest: 0.4)).isEmpty)
}

@Test func slowSlideStartingHigherInTheBottomZoneOpensSwitcher() {
    var d = bottomDriver()
    #expect(d.frames(slide(from: 0.3, y: 0.14, step: 0.002, frames: 60)).first == .began(.bottom))
}

@Test func slowSlideAboveTheBottomZoneIsCursor() {
    var d = bottomDriver()
    #expect(d.frames(slide(from: 0.3, y: 0.2, step: 0.002, frames: 60)).isEmpty)
}

@Test func restThenSlowSlideOpensSwitcher() {
    var d = bottomDriver()
    #expect(d.frames(slide(from: 0.3, step: 0.002, frames: 60, rest: 0.4)).first == .began(.bottom))
}

@Test func bottomEdgeIsOffByDefault() {
    var d = Driver()
    #expect(d.frames(slide(from: 0.3, step: 0.002, frames: 60)).isEmpty)
}

@Test func touchingBottomDoesNotHoldPointerUntilSwitcherStarts() {
    var d = bottomDriver()
    _ = d.frame(finger(0.3, 0.03))
    #expect(!d.holdsPointer)
    for i in 1...20 { _ = d.frame(finger(0.3 + 0.002 * Double(i), 0.03)) }
    #expect(d.holdsPointer)
}

@Test func verticalFromBottomIsCursor() {
    var d = bottomDriver()
    let frames = (0...20).map { finger(0.5, 0.03 + 0.002 * Double($0)) } + [[]]
    #expect(d.frames(frames).isEmpty)
}

@Test func bottomRightCornerStillTapsWithBottomEdgeOn() {
    var d = bottomDriver()
    let events = d.tap(0.95, 0.04) + d.tap(0.95, 0.04, after: 0.15)
    #expect(doubleTaps(events) == [.bottomRight])
}

@Test func volumeSlideFromBottomRightStillWorks() {
    var d = bottomDriver()
    let frames = (0...20).map { finger(0.97, 0.03 + 0.01 * Double($0)) } + [[]]
    #expect(d.frames(frames).first == .began(.right))
}
