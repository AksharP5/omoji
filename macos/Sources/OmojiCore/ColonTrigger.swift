import Foundation

public enum ColonKey: Equatable {
  case text(Character), backspace, up, down, enter, tab, escape, other
}

public enum ColonAction: Equatable {
  case pass, consume
  /// Delete `deleting` typed characters, then type `emoji`; learn it for `query`.
  case insert(emoji: String, deleting: Int, query: String)
}

/// Follows typing in other apps for ":name" and keeps only the current query.
public final class ColonTrigger {
  public static let queryLimit = 32

  public private(set) var query: String?
  public private(set) var results: [Emoji] = []
  public private(set) var selectedIndex = 0
  private var atBoundary = true
  private let search: (String) -> [Emoji]

  public init(search: @escaping (String) -> [Emoji]) {
    self.search = search
  }

  public var visible: Bool { (query?.count ?? 0) >= 2 && !results.isEmpty }
  public var searchText: String { (query ?? "").replacingOccurrences(of: "_", with: " ") }

  public func reset() {
    cancel(boundary: true)
  }

  public func handle(_ key: ColonKey) -> ColonAction {
    if visible {
      switch key {
      case .up, .down:
        selectedIndex = (selectedIndex + (key == .up ? -1 : 1) + results.count) % results.count
        return .consume
      case .enter, .tab:
        return insert(results[selectedIndex])
      case .text(":"):
        return insert(results[0])
      case .escape:
        cancel(boundary: false)
        return .consume
      default: break
      }
    }
    switch key {
    case .text(let character):
      guard let query else {
        if character == ":" && atBoundary { update("") } else { atBoundary = Self.isBoundary(character) }
        return .pass
      }
      if Self.isQuery(character) && query.count < Self.queryLimit {
        update(query + character.lowercased())
      } else {
        cancel(boundary: Self.isBoundary(character))
      }
    case .backspace:
      guard let query else {
        atBoundary = false
        return .pass
      }
      if query.isEmpty { cancel(boundary: true) } else { update(String(query.dropLast())) }
    default: cancel(boundary: true)
    }
    return .pass
  }

  private func insert(_ emoji: Emoji) -> ColonAction {
    let action = ColonAction.insert(emoji: emoji.e, deleting: (query ?? "").count + 1, query: searchText)
    cancel(boundary: false)
    return action
  }

  private func update(_ query: String) {
    self.query = query
    results = query.count >= 2 ? search(searchText) : []
    selectedIndex = 0
  }

  private func cancel(boundary: Bool) {
    query = nil
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
