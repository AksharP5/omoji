import Foundation

public enum ColonKey: Equatable {
  case text(Character), backspace, deleteWord, up, down, enter, tab, escape, other
}

public enum ColonAction: Equatable {
  case pass, consume
  /// Delete `deleting` characters before the caret and type `emoji`; learn it for `query`.
  case insert(emoji: String, deleting: Int, query: String)
  case delete(characters: Int)
}

/// Follows literal ":name" typing without changing the app's text until an emoji is selected or the word is deleted.
public final class ColonTrigger {
  public static let queryLimit = 32

  public private(set) var query: String?
  public private(set) var results: [Emoji] = []
  public private(set) var selectedIndex = 0
  /// Whether the text before the caret ends a word; nil after a delete, click or arrow key, when only the app knows.
  private var atBoundary: Bool?
  private let search: (String) -> [Emoji]
  private let textBeforeCaret: () -> String?

  /// `textBeforeCaret` gives the character before the caret, "" at the start of a field, or nil when the app does not say.
  public init(search: @escaping (String) -> [Emoji], textBeforeCaret: @escaping () -> String? = { nil }) {
    self.search = search
    self.textBeforeCaret = textBeforeCaret
  }

  public var visible: Bool { (query?.count ?? 0) >= 2 && !results.isEmpty }
  public var searchText: String { (query ?? "").replacingOccurrences(of: "_", with: " ") }

  public func reset() {
    finish(boundary: nil)
  }

  public func handle(_ key: ColonKey) -> ColonAction {
    guard let query else {
      switch key {
      case .text(":") where atBoundary ?? textBeforeCaret().map { $0.last.map(Self.isBoundary) ?? true } ?? true:
        update("")
      case .text(let character): atBoundary = Self.isBoundary(character)
      default: atBoundary = nil
      }
      return .pass
    }
    if visible {
      switch key {
      case .up, .down:
        selectedIndex = (selectedIndex + (key == .up ? -1 : 1) + results.count) % results.count
        return .consume
      case .enter, .tab, .text(":"):
        let action = ColonAction.insert(emoji: results[selectedIndex].e, deleting: query.count + 1, query: searchText)
        finish(boundary: true)
        return action
      default: break
      }
    }
    switch key {
    case .backspace:
      // The query only started after a word end, so that is still what is before the caret.
      if query.isEmpty { finish(boundary: true) } else { update(String(query.dropLast())) }
      return .pass
    case .text(let character) where Self.isQuery(character) && query.count < Self.queryLimit:
      update(query + character.lowercased())
      return .pass
    case .deleteWord:
      let action = ColonAction.delete(characters: query.count + 1)
      finish(boundary: true)
      return action
    case .escape:
      finish(boundary: false)
      return .consume
    default:
      if case .text(let character) = key { finish(boundary: Self.isBoundary(character)) } else { finish(boundary: nil) }
      return .pass
    }
  }

  private func update(_ query: String) {
    self.query = query
    results = query.count >= 2 ? search(searchText) : []
    selectedIndex = 0
  }

  private func finish(boundary: Bool?) {
    query = nil
    results = []
    selectedIndex = 0
    atBoundary = boundary
  }

  static func isBoundary(_ character: Character) -> Bool {
    character.isWhitespace || "([{\"'".contains(character) || character.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
  }

  static func isQuery(_ character: Character) -> Bool {
    character.isASCII && (character.isLetter || character.isNumber || "_+-".contains(character))
  }
}
