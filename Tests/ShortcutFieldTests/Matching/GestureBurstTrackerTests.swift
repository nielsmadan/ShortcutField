import AppKit
@testable import ShortcutField
import Testing

@MainActor
@Suite(.serialized)
struct GestureBurstTrackerTests {
    private func shape(_ type: NSEvent.EventType, _ phase: NSEvent.Phase) -> ShortcutEventShape {
        ShortcutEventShape(type: type, phase: phase)
    }

    @Test func track_placesASynthesizedTrackpadBurst() {
        var tracker = GestureBurstTracker()
        let events = [
            scrollEvent(),
            scrollEvent(phase: .mayBegin),
            scrollEvent(deltaY: 10, phase: .began),
            scrollEvent(deltaY: 10, phase: .changed),
            scrollEvent(phase: .ended),
            scrollEvent(phase: .cancelled),
        ]

        let positions = events.map { tracker.track(ShortcutEventShape($0)) }

        #expect(positions == [.unphased, .start, .start, .middle(nil), .end(nil), .end(nil)])
    }

    @Test func track_placesAKeyEventOutsideAnyBurst() {
        var tracker = GestureBurstTracker()

        #expect(tracker.track(ShortcutEventShape(keyDown(0))) == .unphased)
    }

    @Test func claim_ofAPhaselessEvent_claimsNothing() {
        var tracker = GestureBurstTracker()
        tracker.claim(ShortcutEventShape(scrollEvent(deltaY: 10)))
        tracker.claim(ShortcutEventShape(keyDown(0)))

        #expect(!tracker.isClaimed(.scrollWheel))
        #expect(!tracker.isClaimed(.keyDown))
        #expect(tracker.track(shape(.scrollWheel, .changed)) == .middle(nil))
    }

    @Test(arguments: [GestureBurstTracker.Claim.consumesRest, .ignoresRest])
    func claimedBurst_reportsItsClaimUntilItEnds(claim: GestureBurstTracker.Claim) {
        var tracker = GestureBurstTracker()
        _ = tracker.track(shape(.magnify, .began))
        tracker.claim(shape(.magnify, .changed), claim)

        let positions = [NSEvent.Phase.changed, .ended, .changed].map { tracker.track(shape(.magnify, $0)) }

        #expect(positions == [.middle(claim), .end(claim), .middle(nil)])
    }

    @Test(arguments: [NSEvent.Phase.mayBegin, .began])
    func newBurst_dropsAClaimWhoseEndNeverArrived(start: NSEvent.Phase) {
        var tracker = GestureBurstTracker()
        tracker.claim(shape(.rotate, .changed), .consumesRest)

        let positions = [start, .changed].map { tracker.track(shape(.rotate, $0)) }

        #expect(positions == [.start, .middle(nil)])
    }

    @Test func claims_arePerEventType() {
        var tracker = GestureBurstTracker()
        tracker.claim(shape(.magnify, .changed), .ignoresRest)
        tracker.claim(shape(.rotate, .changed), .consumesRest)

        #expect(tracker.track(shape(.rotate, .ended)) == .end(.consumesRest))
        #expect(tracker.track(shape(.magnify, .changed)) == .middle(.ignoresRest))
        #expect(tracker.track(shape(.scrollWheel, .changed)) == .middle(nil))
    }

    @Test func wheelNotch_keepsTheClaimOfTheBurstInProgress() {
        var tracker = GestureBurstTracker()
        tracker.claim(shape(.scrollWheel, .changed), .consumesRest)

        #expect(tracker.track(shape(.scrollWheel, [])) == .unphased)
        #expect(tracker.track(shape(.scrollWheel, .changed)) == .middle(.consumesRest))
    }

    @Test func keepOnly_dropsTheOtherTypesClaims() {
        var tracker = GestureBurstTracker()
        tracker.claim(shape(.magnify, .changed), .consumesRest)
        tracker.claim(shape(.rotate, .changed), .consumesRest)

        tracker.keepOnly(.rotate)

        #expect(tracker.isClaimed(.rotate))
        #expect(!tracker.isClaimed(.magnify))
    }

    @Test func reset_dropsEveryClaim() {
        var tracker = GestureBurstTracker()
        tracker.claim(shape(.magnify, .changed), .consumesRest)
        tracker.claim(shape(.scrollWheel, .changed), .ignoresRest)

        tracker.reset()

        #expect([NSEvent.EventType.magnify, .scrollWheel].map { tracker.track(shape($0, .changed)) } == [
            .middle(nil), .middle(nil),
        ])
    }
}
