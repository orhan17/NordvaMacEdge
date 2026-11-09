import Testing
@testable import NordvaMacEdgeCore

@Test func crossingADetentClicks() {
    #expect(haptic(from: 0.55, to: 0.61) == .detent)
    #expect(haptic(from: 0.61, to: 0.59) == .detent)
}

@Test func movingWithinADetentIsSilent() {
    #expect(haptic(from: 0.61, to: 0.68) == nil)
    #expect(haptic(from: 0.5, to: 0.5) == nil)
}

@Test func landingExactlyOnABoundaryClicks() {
    #expect(haptic(from: 0.59, to: 0.6) == .detent)
    #expect(haptic(from: 0.6, to: 0.61) == nil)
}

@Test func reachingTheEndsIsAStop() {
    #expect(haptic(from: 0.97, to: 1) == .stop)
    #expect(haptic(from: 0.03, to: 0) == .stop)
}

@Test func pushingPastTheEndStaysSilent() {
    #expect(haptic(from: 1, to: 1) == nil)
    #expect(haptic(from: 0, to: 0) == nil)
}

@Test func fullSlideGivesNineDetentsAndOneStop() {
    var level = 0.0
    var clicks: [Haptic] = []
    while level < 1 {
        let next = min(1, level + 0.013)
        if let click = haptic(from: level, to: next) { clicks.append(click) }
        level = next
    }
    #expect(clicks.filter { $0 == .detent }.count == 9)
    #expect(clicks.last == .stop)
}
