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
  var pasteResult = PasteResult.pasted
  var delaysPaste = false
  var pendingPastes: [() -> Void] = []
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
      paste: { [unowned self] isCurrent, done in
        let finish = { [unowned self] in
          guard isCurrent() else { done(.failed); return }
          self.pastes += 1
          done(self.pasteResult)
        }
        if self.delaysPaste { self.pendingPastes.append(finish) } else { finish() }
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
  fixture.pasteResult = .failed
  let picker = fixture.open("flower")
  picker.activate(fixture.index(of: "rose"))
  #expect(fixture.copied == ["🌹"])
  #expect(picker.opened)
  #expect(fixture.visible)
  #expect(picker.statusText == "Could not paste. Emoji copied to clipboard.")
  #expect(try fixture.reopen().open("flower").results.first?.n != "rose")
  fixture.pasteResult = .needsAccess
  fixture.open("flower").activate(fixture.index(of: "rose"))
  #expect(picker.statusText?.hasPrefix("Allow omoji in System Settings") == true)
}

@Test func reopeningAndDismissingCancelsPendingPaste() throws {
  let fixture = try Fixture()
  fixture.delaysPaste = true
  let picker = fixture.open("flower")
  picker.activate(fixture.index(of: "rose"))
  #expect(fixture.pendingPastes.count == 1)
  fixture.open("heart").dismiss()
  fixture.pendingPastes.removeFirst()()
  #expect(fixture.pastes == 0)
  #expect(!picker.opened)
  #expect(try fixture.reopen().open("flower").results.first?.n != "rose")
}

@Test func oldPasteCannotDuplicateTheNextSelection() throws {
  let fixture = try Fixture()
  fixture.delaysPaste = true
  let picker = fixture.open("flower")
  picker.activate(fixture.index(of: "rose"))
  fixture.open("tulip").activate(fixture.index(of: "tulip"))
  #expect(fixture.pendingPastes.count == 2)
  fixture.pendingPastes.removeFirst()()
  #expect(fixture.pastes == 0)
  fixture.pendingPastes.removeFirst()()
  #expect(fixture.pastes == 1)
  #expect(!picker.opened)
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

@Test func cardIsFullUnlessCompactAndNeverInvalidatesPreferences() throws {
  for (card, expected) in [("", Card.full), (",\"card\":\"compact\"", .compact), (",\"card\":\"huge\"", .full), (",\"card\":7", .full)] {
    let picker = try Fixture(config: "{\"version\":1,\"defaultAction\":\"copy\"\(card)}").open()
    #expect(picker.card == expected)
    #expect(picker.statusText == nil)
    #expect(picker.defaultAction == .copy)
  }
}

@Test func savingOneKeyKeepsTheOthers() throws {
  let fixture = try Fixture(config: "{\"version\":1,\"defaultAction\":\"paste\",\"card\":\"compact\",\"future\":[1]}")
  let picker = fixture.open()
  #expect(picker.handle(.character("?"), [.shift]))
  #expect(picker.handle(.character("c"), []))
  let saved = { try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.configURL)) as! NSDictionary }
  #expect(try saved() == ["version": 1, "defaultAction": "copy", "card": "compact", "future": [1]])
  #expect(try String(contentsOf: fixture.configURL, encoding: .utf8).hasSuffix("}\n"))
  #expect(picker.toggleCard())
  #expect(picker.card == .full)
  #expect(try saved() == ["version": 1, "defaultAction": "copy", "card": "full", "future": [1]])
  #expect(try fixture.reopen().open().card == .full)
}

@Test func cardCannotOverwriteInvalidPreferences() throws {
  let config = "{\"version\":2,\"defaultAction\":\"paste\"}"
  let fixture = try Fixture(config: config)
  #expect(!fixture.open().toggleCard())
  #expect(try String(contentsOf: fixture.configURL, encoding: .utf8) == config)
}

private func colon(_ names: [String] = ["rose", "rosette"], before: String? = nil) -> ColonTrigger {
  ColonTrigger(search: { query in names.filter { $0.contains(query) }.map { Emoji(e: "<\($0)>", n: $0) } },
               textBeforeCaret: { before })
}

private func type(_ trigger: ColonTrigger, _ text: String) -> [ColonAction] {
  text.map { trigger.handle(.text($0)) }
}

private let mark = ColonAction.replace(deleting: 0, text: ColonTrigger.mark, replay: false)

@Test func colonStartsOnlyAfterABoundaryAndShowsALookAlikeColon() throws {
  for text in [":ro", " :ro", "\n:ro", "(:ro", "[:ro", "{:ro", "\":ro", "':ro"] {
    let trigger = colon()
    #expect(type(trigger, text).suffix(3) == [mark, .pass, .pass], "\(text)")
    #expect(trigger.visible, "\(text)")
  }
  for text in ["12:30", "http://", "a:ro", "::ro"] {
    let trigger = colon()
    _ = type(trigger, text)
    #expect(!trigger.visible, "\(text)")
  }
}

@Test func colonAsksTheAppWhatIsBeforeTheCaretAfterADeleteOrMove() throws {
  for (before, starts) in [("a", false), ("1", false), (" ", true), ("🌹", true), ("❤️", true), ("☀️", true), ("", true), (nil, true)] as [(String?, Bool)] {
    for key in [ColonKey.backspace, .other, .escape] {
      let trigger = colon(before: before)
      _ = type(trigger, "ab:ro")
      _ = trigger.handle(.escape)
      _ = trigger.handle(key)
      _ = type(trigger, ":ro")
      #expect(trigger.visible == starts, "\(String(describing: before)) \(key)")
    }
  }
  let picked = colon(before: "a")
  _ = type(picked, " :ro")
  #expect(picked.handle(.enter) == .insert(emoji: "<rose>", deleting: 3, query: "ro"))
  for delete in [[ColonKey.backspace, .backspace, .backspace], [.deleteWord]] {
    _ = type(picked, ":ro")
    for key in delete { _ = picked.handle(key) }
    _ = type(picked, ":ro")
    #expect(picked.visible, "\(delete)")
    _ = picked.handle(.enter)
  }
  let trigger = colon(before: "a")
  _ = type(trigger, ":ro")
  _ = trigger.handle(.backspace)
  _ = trigger.handle(.backspace)
  _ = trigger.handle(.backspace)
  _ = trigger.handle(.backspace)
  _ = type(trigger, " :ro")
  #expect(trigger.visible)
}

@Test func colonCardNeedsTwoCharactersAndAResult() throws {
  let trigger = colon()
  _ = type(trigger, ":R")
  #expect(trigger.query == "r")
  #expect(!trigger.visible)
  _ = type(trigger, "O")
  #expect(trigger.results.count == 2)
  _ = type(trigger, "x")
  #expect(!trigger.visible)
  #expect(trigger.handle(.enter) == .replace(deleting: 4, text: ":ROx", replay: true))
  #expect(trigger.query == nil)
}

@Test func colonPicksWithKeysAndLearnsTheSpacedQuery() throws {
  let trigger = colon(["red rose", "red heart"])
  _ = type(trigger, ":red_")
  #expect(trigger.searchText == "red ")
  #expect(trigger.handle(.down) == .consume)
  #expect(trigger.handle(.down) == .consume)
  #expect(trigger.handle(.up) == .consume)
  #expect(trigger.selectedIndex == 1)
  #expect(trigger.handle(.tab) == .insert(emoji: "<red heart>", deleting: 5, query: "red "))
  #expect(!trigger.visible)
  _ = type(trigger, " :re")
  #expect(trigger.handle(.enter) == .insert(emoji: "<red rose>", deleting: 3, query: "re"))
  _ = type(trigger, ":re")
  #expect(trigger.handle(.text(":")) == .insert(emoji: "<red rose>", deleting: 3, query: "re"))
  _ = type(trigger, ":re")
  _ = trigger.handle(.down)
  #expect(trigger.handle(.text(":")) == .insert(emoji: "<red heart>", deleting: 3, query: "re"))
}

@Test func colonPutsTheRealColonBackOnOtherInput() throws {
  for key in [ColonKey.text("."), .text("é"), .text(" "), .other, .up, .enter] {
    let trigger = colon()
    _ = type(trigger, ":r")
    #expect(trigger.handle(key) == .replace(deleting: 2, text: ":r", replay: true), "\(key)")
    #expect(trigger.query == nil)
  }
  let trigger = colon()
  _ = type(trigger, ":D")
  #expect(trigger.handle(.text(")")) == .replace(deleting: 2, text: ":D", replay: true))
  _ = type(trigger, " :ro")
  #expect(trigger.handle(.escape) == .replace(deleting: 3, text: ":ro", replay: false))
  #expect(!trigger.visible)
  #expect(trigger.handle(.text("d")) == .pass)
  #expect(!trigger.visible)
  _ = type(trigger, " :ro")
  trigger.reset()
  #expect(!trigger.visible)
  _ = type(trigger, ":ro")
  #expect(trigger.visible)
}

@Test func colonBackspaceAndLengthLimit() throws {
  let trigger = colon()
  _ = type(trigger, ":ros")
  #expect(trigger.handle(.backspace) == .pass)
  #expect(trigger.query == "ro")
  _ = trigger.handle(.backspace)
  _ = trigger.handle(.backspace)
  #expect(trigger.query == "")
  #expect(trigger.handle(.backspace) == .pass)
  #expect(trigger.query == nil)
  _ = type(trigger, ":ros")
  #expect(trigger.handle(.deleteWord) == .replace(deleting: 4, text: "", replay: false))
  #expect(trigger.query == nil)
  _ = type(trigger, ":ros")
  #expect(trigger.visible)
  let long = String(repeating: "a", count: ColonTrigger.queryLimit)
  _ = type(trigger, " :" + long)
  #expect(trigger.query == long)
  #expect(trigger.handle(.text("a")) == .replace(deleting: long.count + 1, text: ":" + long, replay: true))
  #expect(trigger.query == nil)
}
