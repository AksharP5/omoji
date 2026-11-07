import Foundation
import Testing
@testable import OmojiCore

private let root = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func source(_ path: String) -> String {
  try! String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

private final class Fixture {
  let directory: URL
  var configURL: URL { directory.appendingPathComponent("config/omoji/config.json") }
  var historyURL: URL { directory.appendingPathComponent("state/omoji/history.json") }
  var copied: [String] = []
  var pastes = 0
  var copyWorks = true
  var pasteWorks = true
  var visible = false
  private(set) var picker: Picker!

  init(directory: URL? = nil, config: String? = nil, history: String? = nil, catalog: String = source("emojis.json")) throws {
    self.directory = directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("omoji-test-" + UUID().uuidString)
    for (url, text) in [(configURL, config), (historyURL, history)] {
      guard let text else { continue }
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try text.write(to: url, atomically: true, encoding: .utf8)
    }
    let engine = try EmojiEngine(script: source("EmojiSearch.js"))
    picker = Picker(
      engine: engine,
      catalog: catalog,
      history: HistoryStore(url: historyURL, engine: engine),
      preferences: PreferencesStore(url: configURL),
      strings: Strings(json: Data(source("i18n/en.json").utf8)),
      copy: { [unowned self] emoji in
        guard self.copyWorks else { return false }
        self.copied.append(emoji)
        return true
      },
      paste: { [unowned self] done in
        self.pastes += 1
        done(self.pasteWorks)
      })
    picker.onVisibilityChange = { [unowned self] shown in self.visible = shown }
  }

  func reopen() throws -> Fixture { try Fixture(directory: directory) }

  func open(_ query: String = "") -> Picker {
    picker.open()
    picker.query = query
    return picker
  }

  func index(of name: String) -> Int {
    picker.results.firstIndex { $0.n == name } ?? -1
  }

  func mode(_ url: URL) throws -> Int {
    (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue
  }
}

@Test func catalogLoadsEveryBundledEmoji() throws {
  let catalog = try JSONSerialization.jsonObject(with: Data(source("emojis.json").utf8)) as! [[String: String]]
  let picker = try Fixture().open()
  #expect(!picker.results.isEmpty)
  #expect(picker.emptyText == nil)
  for item in [catalog.first!, catalog.last!] {
    picker.query = item["n"]!
    #expect(picker.results.first?.e == item["e"])
  }
}

@Test func choiceComesFirstForTheSameNormalizedSearch() throws {
  let fixture = try Fixture()
  let picker = fixture.open("flower")
  #expect(picker.results.first?.n != "rose")
  picker.activate(fixture.index(of: "rose"))
  #expect(fixture.copied == ["🌹"])
  #expect(fixture.pastes == 1)
  #expect(!fixture.visible)
  picker.open()
  picker.query = " FLOWER  "
  #expect(picker.results.first?.n == "rose")
}

@Test func learningSurvivesRestartWithPrivateFiles() throws {
  let fixture = try Fixture()
  fixture.open("flower").activate(fixture.index(of: "rose"))
  let restarted = try fixture.reopen()
  #expect(restarted.open("flower").results.first?.n == "rose")
  #expect(try fixture.mode(fixture.historyURL) == 0o600)
  #expect(try fixture.mode(fixture.historyURL.deletingLastPathComponent()) == 0o700)
  #expect(try fixture.mode(fixture.configURL) == 0o600)
  #expect(try fixture.mode(fixture.configURL.deletingLastPathComponent()) == 0o700)
}

@Test func emptySearchShowsRecentPicks() throws {
  let fixture = try Fixture()
  fixture.open("tulip").activate(fixture.index(of: "tulip"))
  #expect(fixture.open("").results.first?.n == "tulip")
}

@Test func pasteIsTheInitialDefaultAndControlEnterCopies() throws {
  let fixture = try Fixture()
  let picker = fixture.open("flower")
  #expect(picker.defaultAction == .paste)
  #expect(try String(contentsOf: fixture.configURL, encoding: .utf8) == "{\"version\":1,\"defaultAction\":\"paste\"}\n")
  #expect(picker.actionHint == "↵  Paste")
  #expect(picker.handle(.enter, [.control]))
  #expect(fixture.copied.count == 1)
  #expect(fixture.pastes == 0)
  #expect(!picker.opened)
  #expect(picker.defaultAction == .paste)
}

@Test func copyDefaultCopiesAndControlEnterPastes() throws {
  let fixture = try Fixture(config: "{\"version\":1,\"defaultAction\":\"copy\"}")
  let picker = fixture.open("flower")
  #expect(picker.defaultAction == .copy)
  #expect(picker.actionHint == "↵  Copy")
  #expect(picker.handle(.enter, []))
  #expect(fixture.copied.count == 1)
  #expect(fixture.pastes == 0)
  picker.open()
  picker.query = "flower"
  #expect(picker.handle(.enter, [.control]))
  #expect(fixture.pastes == 1)
}

@Test func settingsShortcutSavesTheChoiceAndReturnsToTheSearch() throws {
  let fixture = try Fixture()
  let picker = fixture.open("flower")
  #expect(picker.handle(.down, []))
  #expect(picker.handle(.down, []))
  #expect(picker.handle(.character("?"), [.shift]))
  #expect(picker.settingsOpen)
  #expect(picker.handle(.enter, [.control]))
  #expect(fixture.copied.isEmpty)
  #expect(picker.handle(.character("c"), []))
  #expect(!picker.settingsOpen)
  #expect(picker.opened)
  #expect(picker.query == "flower")
  #expect(picker.selectedIndex == 2)
  #expect(picker.defaultAction == .copy)
  #expect(try String(contentsOf: fixture.configURL, encoding: .utf8) == "{\"version\":1,\"defaultAction\":\"copy\"}\n")
  #expect(try fixture.reopen().open().defaultAction == .copy)
}

@Test func settingsKeyboardChoosesTheHighlightedAction() throws {
  let fixture = try Fixture()
  let picker = fixture.open("heart")
  #expect(picker.handle(.character(","), [.command]))
  #expect(picker.settingsOpen)
  #expect(picker.settingsHighlight == .paste)
  #expect(picker.handle(.down, []))
  #expect(picker.settingsHighlight == .copy)
  #expect(picker.handle(.tab, []))
  #expect(picker.settingsHighlight == .paste)
  #expect(picker.handle(.up, []))
  #expect(picker.handle(.space, []))
  #expect(!picker.settingsOpen)
  #expect(picker.defaultAction == .copy)
  #expect(picker.handle(.character(","), [.control]))
  #expect(picker.handle(.character("p"), []))
  #expect(picker.defaultAction == .paste)
  #expect(fixture.copied.isEmpty)
}

@Test func escapeLeavesSettingsThenClearsThenCloses() throws {
  let fixture = try Fixture()
  let picker = fixture.open("flower")
  #expect(fixture.visible)
  #expect(picker.handle(.character("?"), [.shift]))
  #expect(picker.handle(.escape, []))
  #expect(!picker.settingsOpen)
  #expect(picker.query == "flower")
  #expect(picker.defaultAction == .paste)
  #expect(picker.handle(.escape, []))
  #expect(picker.query == "")
  #expect(picker.opened)
  #expect(picker.handle(.escape, []))
  #expect(!picker.opened)
  #expect(!fixture.visible)
}

@Test func selectionMovesAndWraps() throws {
  let picker = try Fixture().open("flower")
  let count = picker.results.count
  #expect(picker.selectedIndex == 0)
  #expect(picker.handle(.up, []))
  #expect(picker.selectedIndex == count - 1)
  #expect(picker.handle(.down, []))
  #expect(picker.selectedIndex == 0)
  #expect(picker.handle(.character("n"), [.control]))
  #expect(picker.selectedIndex == 1)
  #expect(picker.handle(.character("p"), [.control]))
  #expect(picker.selectedIndex == 0)
  picker.pageSize = 3
  #expect(picker.handle(.pageDown, []))
  #expect(picker.selectedIndex == 3)
  #expect(picker.handle(.pageUp, []))
  #expect(picker.selectedIndex == 0)
  #expect(!picker.handle(.character("x"), []))
}

@Test func overLongSearchesKeepTheirTextButSelectNothing() throws {
  let fixture = try Fixture()
  let picker = fixture.open("flower" + String(repeating: " ", count: 155))
  #expect(picker.queryTooLong)
  #expect(picker.results.isEmpty)
  #expect(picker.emptyText == "Use up to 160 characters to search.")
  #expect(picker.handle(.enter, []))
  #expect(fixture.copied.isEmpty)
  picker.query = "flower" + String(repeating: " ", count: 154)
  #expect(!picker.queryTooLong)
  #expect(!picker.results.isEmpty)
}

@Test func failedCopyShowsAnErrorAndLearnsNothing() throws {
  let fixture = try Fixture()
  fixture.copyWorks = false
  let picker = fixture.open("flower")
  picker.activate(fixture.index(of: "rose"))
  #expect(picker.opened)
  #expect(picker.statusText == "Could not copy. Try again.")
  #expect(fixture.pastes == 0)
  #expect(try fixture.reopen().open("flower").results.first?.n != "rose")
}

@Test func failedPasteReturnsWithTheEmojiCopied() throws {
  let fixture = try Fixture()
  fixture.pasteWorks = false
  let picker = fixture.open("flower")
  picker.activate(fixture.index(of: "rose"))
  #expect(fixture.copied == ["🌹"])
  #expect(picker.opened)
  #expect(fixture.visible)
  #expect(picker.statusText == "Could not paste. Emoji copied to clipboard.")
  #expect(try fixture.reopen().open("flower").results.first?.n != "rose")
}

@Test func unreadableHistoryIsPreservedAndDisablesOnlyLearning() throws {
  let fixture = try Fixture(history: "{invalid")
  let picker = fixture.open("flower")
  #expect(picker.statusText == "Learning unavailable")
  picker.activate(fixture.index(of: "rose"), .copy)
  #expect(fixture.copied == ["🌹"])
  #expect(try String(contentsOf: fixture.historyURL, encoding: .utf8) == "{invalid")
}

@Test func invalidPreferencesFallBackToCopyWithoutRewriting() throws {
  let config = "{\"version\":1,\"defaultAction\":\"execute\"}"
  let fixture = try Fixture(config: config)
  let picker = fixture.open("flower")
  #expect(picker.defaultAction == .copy)
  #expect(picker.statusText == "Preferences unavailable. Enter copies.")
  #expect(picker.handle(.character("?"), [.shift]))
  #expect(picker.handle(.character("p"), []))
  #expect(picker.defaultAction == .copy)
  #expect(try String(contentsOf: fixture.configURL, encoding: .utf8) == config)
}

@Test func editedPreferencesApplyWhenThePickerOpens() throws {
  let fixture = try Fixture()
  #expect(fixture.open().defaultAction == .paste)
  try "{\"version\":1,\"defaultAction\":\"copy\"}".write(to: fixture.configURL, atomically: true, encoding: .utf8)
  #expect(fixture.open().defaultAction == .copy)
}

@Test func catalogFailureStaysVisibleWhileSearchingAndReopening() throws {
  let fixture = try Fixture(catalog: "{invalid")
  let picker = fixture.open("flower")
  #expect(picker.results.isEmpty)
  #expect(picker.emptyText == "Could not load emoji")
  picker.dismiss()
  picker.open()
  #expect(picker.emptyText == "Could not load emoji")
}

@Test func emptyResultsExplainThemselves() throws {
  let picker = try Fixture().open("no-such-emoji-name")
  #expect(picker.results.isEmpty)
  #expect(picker.emptyText == "No emoji found")
  #expect(picker.handle(.enter, []))
}
