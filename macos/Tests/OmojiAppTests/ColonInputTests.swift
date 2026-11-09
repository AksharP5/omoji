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

@Test func repeatedTextPreservesHostInputAndCancelsColonTracking() throws {
  let event = try #require(CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState),
                                  virtualKey: CGKeyCode(kVK_ANSI_1), keyDown: true))
  let units = Array("1".utf16)
  event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
  #expect(AppDelegate.colonKey(event) == .text("1"))
  event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
  let key = AppDelegate.colonKey(event)
  #expect(key == .other)
  for text in [":r", ":ro"] {
    let trigger = ColonTrigger(search: { _ in [Emoji(e: "<rose>", n: "rose")] })
    for character in text { _ = trigger.handle(.text(character)) }
    #expect(trigger.handle(key) == .pass)
    #expect(trigger.query == nil)
    #expect(trigger.handle(.enter) == .pass)
  }
  for (code, expected, action, query) in [
    (kVK_DownArrow, ColonKey.down, ColonAction.consume, "ro"),
    (kVK_Delete, .backspace, .pass, "r")
  ] {
    let repeated = try #require(CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState),
                                       virtualKey: CGKeyCode(code), keyDown: true))
    repeated.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
    let key = AppDelegate.colonKey(repeated)
    #expect(key == expected)
    let trigger = ColonTrigger(search: { _ in [Emoji(e: "<rose>", n: "rose")] })
    for character in ":ro" { _ = trigger.handle(.text(character)) }
    #expect(trigger.handle(key) == action)
    #expect(trigger.query == query)
  }
}
