import Foundation
import JavaScriptCore

public struct Emoji: Equatable {
  public let e: String
  public let n: String
}

public struct EngineError: Error, CustomStringConvertible {
  public let description: String
}

/// Runs the shared EmojiSearch.js, so macOS search and learning match Omarchy exactly.
public final class EmojiEngine {
  public static let queryLimit = 160
  private let context = JSContext()!

  public init(script: String) throws {
    context.evaluateScript(script)
    if let exception = context.exception { throw EngineError(description: exception.toString()) }
  }

  func call(_ name: String, _ arguments: [Any]) throws -> JSValue {
    context.exception = nil
    let result = context.objectForKeyedSubscript(name).call(withArguments: arguments)
    if let exception = context.exception {
      context.exception = nil
      throw EngineError(description: exception.toString())
    }
    return result!
  }

  func search(_ catalog: JSValue, _ query: String, _ choices: JSValue) -> [Emoji] {
    let matches = (try? call("search", [catalog, query, choices]).toArray()) ?? []
    return matches.compactMap { match in
      guard let match = match as? [String: Any], let e = match["e"] as? String, let n = match["n"] as? String else { return nil }
      return Emoji(e: e, n: n)
    }
  }

  func emptyList() -> JSValue { JSValue(newArrayIn: context) }

  func historyText(_ choices: JSValue) -> String {
    let history = JSValue(newObjectIn: context)!
    history.setValue(1, forProperty: "version")
    history.setValue(choices, forProperty: "choices")
    return context.objectForKeyedSubscript("JSON").invokeMethod("stringify", withArguments: [history]).toString() + "\n"
  }
}
