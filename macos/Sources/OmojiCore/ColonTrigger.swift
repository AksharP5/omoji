import Foundation

public enum ColonKey: Equatable {
  case text(Character), backspace, up, down, enter, tab, escape, other
}

public enum ColonAction: Equatable {
  case pass, consume
  /// Delete `deleting` characters before the caret and type `emoji`; learn it for `query`.
  case insert(emoji: String, deleting: Int, query: String)
  /// Delete `deleting` characters before the caret, type `text`, then let the current key through when `replay` is true.
  case replace(deleting: Int, text: String, replay: Bool)
}

/// Follows ":name" typing in other apps. The app gets a look-alike colon while the name is typed, so its own ":" emoji popup never opens.
public final class ColonTrigger {
  public static let queryLimit = 32
  public static let mark = "\u{2236}"

  public private(set) var query: String?
  public private(set) var results: [Emoji] = []
  public private(set) var selectedIndex = 0
  /// What the user typed, with the real colon.
  private var typed = ""
  private var atBoundary = true
  private let search: (String) -> [Emoji]

  public init(search: @escaping (String) -> [Emoji]) {
    self.search = search
  }

  public var visible: Bool { (query?.count ?? 0) >= 2 && !results.isEmpty }
  public var searchText: String { (query ?? "").replacingOccurrences(of: "_", with: " ") }

  public func reset() {
    finish(boundary: true)
  }

  public func handle(_ key: ColonKey) -> ColonAction {
    guard let query else {
      switch key {
      case .text(":") where atBoundary:
        update("", typed: ":")
        return .replace(deleting: 0, text: Self.mark, replay: false)
      case .text(let character): atBoundary = Self.isBoundary(character)
      case .backspace: atBoundary = false
      default: atBoundary = true
      }
      return .pass
    }
    if visible {
      switch key {
      case .up, .down:
        selectedIndex = (selectedIndex + (key == .up ? -1 : 1) + results.count) % results.count
        return .consume
      case .enter, .tab: return insert(results[selectedIndex])
      case .text(":"): return insert(results[0])
      default: break
      }
    }
    switch key {
    case .backspace:
      if query.isEmpty { finish(boundary: true) } else { update(String(query.dropLast()), typed: String(typed.dropLast())) }
      return .pass
    case .text(let character) where Self.isQuery(character) && query.count < Self.queryLimit:
      update(query + character.lowercased(), typed: typed + String(character))
      return .pass
    case .escape:
      let action = ColonAction.replace(deleting: typed.count, text: typed, replay: false)
      finish(boundary: false)
      return action
    default:
      let action = ColonAction.replace(deleting: typed.count, text: typed, replay: true)
      if case .text(let character) = key { finish(boundary: Self.isBoundary(character)) } else { finish(boundary: true) }
      return action
    }
  }

  private func insert(_ emoji: Emoji) -> ColonAction {
    let action = ColonAction.insert(emoji: emoji.e, deleting: typed.count, query: searchText)
    finish(boundary: false)
    return action
  }

  private func update(_ query: String, typed: String) {
    self.query = query
    self.typed = typed
    results = query.count >= 2 ? search(searchText) : []
    selectedIndex = 0
  }

  private func finish(boundary: Bool) {
    query = nil
    typed = ""
    results = []
    selectedIndex = 0
    atBoundary = boundary
  }

  static func isBoundary(_ character: Character) -> Bool {
    character.isWhitespace || "([{\"'".contains(character)
  }

  static func isQuery(_ character: Character) -> Bool {
    character.isASCII && (character.isLetter || character.isNumber || "_+-".contains(character))
  }
}
