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

@Test func invisibleColonQueriesPreserveTheHostEscape() {
  for text in [":", ":r", ":zz"] {
    let trigger = ColonTrigger(search: { query in
      query == "ro" ? [Emoji(e: "<rose>", n: "rose")] : []
    })
    for character in text { _ = trigger.handle(.text(character)) }
    #expect(trigger.query != nil)
    #expect(!trigger.visible)
    #expect(trigger.handle(.escape) == .pass)
    #expect(trigger.query == nil)
    #expect(trigger.handle(.enter) == .pass)
  }

  let visible = ColonTrigger(search: { _ in [Emoji(e: "<rose>", n: "rose")] })
  for character in ":ro" { _ = visible.handle(.text(character)) }
  #expect(visible.visible)
  #expect(visible.handle(.escape) == .consume)
  #expect(visible.query == nil)
}
