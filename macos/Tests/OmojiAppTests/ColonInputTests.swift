import AppKit
import Carbon.HIToolbox
import Testing
@testable import OmojiCore
@testable import omoji

@Test func modifiedEscapeKeepsTheHostAppShortcut() throws {
  let event = try #require(CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState),
                                  virtualKey: CGKeyCode(kVK_Escape), keyDown: true))
  for flags in [CGEventFlags.maskAlternate, .maskCommand, .maskControl, [.maskAlternate, .maskCommand], .maskShift] {
    event.flags = flags
    let key = AppDelegate.colonKey(event)
    #expect(key == .other)
    let trigger = ColonTrigger(search: { _ in [Emoji(e: "<rose>", n: "rose")] })
    for character in ":ro" { _ = trigger.handle(.text(character)) }
    #expect(trigger.visible)
    #expect(trigger.handle(key) == .pass)
    #expect(trigger.query == nil)
  }
  event.flags = []
  #expect(AppDelegate.colonKey(event) == .escape)
}

@Test func colonTrackingObservesMiddleMouseCancellation() {
  let middleMouseDown = CGEventMask(1) << CGEventType.otherMouseDown.rawValue
  #expect(AppDelegate.colonEventsMask & middleMouseDown != 0)
  let trigger = ColonTrigger(search: { _ in [Emoji(e: "<rose>", n: "rose")] })
  for character in ":ro" { _ = trigger.handle(.text(character)) }
  #expect(trigger.visible)
  #expect(trigger.handle(.other) == .pass)
  #expect(trigger.query == nil)
  #expect(trigger.handle(.enter) == .pass)
}
