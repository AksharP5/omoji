import Testing
@testable import OmojiCore

@Test func colonCancellationCannotEditThePreviousOrNextDocument() {
  for reset in [true, false] {
    let trigger = ColonTrigger(search: { _ in [Emoji(e: "<rose>", n: "rose")] })
    #expect(":RO".map { trigger.handle(.text($0)) } == [.pass, .pass, .pass])
    #expect(trigger.visible)
    if reset {
      trigger.reset()
    } else {
      #expect(trigger.handle(.escape) == .consume)
    }
    #expect(!trigger.visible)
    #expect(trigger.query == nil)
    #expect(trigger.handle(.enter) == .pass)
    #expect(trigger.handle(.deleteWord) == .pass)
  }
}
