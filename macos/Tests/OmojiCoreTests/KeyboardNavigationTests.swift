import Foundation
import Testing
@testable import OmojiCore

@Test func modifiedNavigationKeepsTheSearchFieldsTextEditing() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("omoji-keyboard-" + UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let read = { (path: String) in try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
  let engine = try EmojiEngine(script: read("EmojiSearch.js"))
  let picker = Picker(engine: engine, catalog: try read("emojis.json"),
    history: HistoryStore(url: directory.appendingPathComponent("history.json"), engine: engine),
    preferences: PreferencesStore(url: directory.appendingPathComponent("config.json")),
    strings: Strings(json: Data()), copy: { _ in true }, paste: { _, done in done(.pasted) })
  picker.open()
  picker.query = "flower"
  picker.pageSize = 2
  try #require(picker.results.count > 3)

  for key in [Key.up, .down, .pageUp, .pageDown] {
    let modifiers: [Modifiers] = key == .up || key == .down
      ? [.shift, .command, .option, [.shift, .command], [.shift, .option]] : [.shift]
    for flags in modifiers {
      picker.select(1)
      #expect(!picker.handle(key, flags))
      #expect(picker.selectedIndex == 1)
    }
  }
  #expect(picker.query == "flower")

  picker.select(0)
  #expect(picker.handle(.down, []))
  #expect(picker.selectedIndex == 1)
  #expect(picker.handle(.character("n"), [.control]))
  #expect(picker.selectedIndex == 2)
  #expect(picker.handle(.character("p"), [.control]))
  #expect(picker.selectedIndex == 1)
  #expect(picker.handle(.up, []))
  #expect(picker.selectedIndex == 0)
  #expect(picker.handle(.pageDown, []))
  #expect(picker.selectedIndex == 2)
  #expect(picker.handle(.pageUp, []))
  #expect(picker.selectedIndex == 0)
}
