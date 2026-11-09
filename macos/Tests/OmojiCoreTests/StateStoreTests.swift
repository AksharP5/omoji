import Foundation
import Testing
@testable import OmojiCore

@Test func savingPreferencesKeepsTheManagedConfigSymlink() throws {
  let files = FileManager.default
  let directory = files.temporaryDirectory.appendingPathComponent("omoji-state-test-" + UUID().uuidString)
  defer { try? files.removeItem(at: directory) }
  let managed = directory.appendingPathComponent("managed/config.json")
  let config = directory.appendingPathComponent("omoji/config.json")
  for parent in [managed.deletingLastPathComponent(), config.deletingLastPathComponent()] {
    try files.createDirectory(at: parent, withIntermediateDirectories: true)
  }
  try "{\"version\":1,\"defaultAction\":\"paste\",\"card\":\"compact\"}"
    .write(to: managed, atomically: true, encoding: .utf8)
  try files.createSymbolicLink(atPath: config.path, withDestinationPath: "../managed/config.json")

  let preferences = PreferencesStore(url: config)
  #expect(preferences.error == nil)
  #expect(preferences.choose(.copy))
  #expect((try? files.destinationOfSymbolicLink(atPath: config.path)) == "../managed/config.json")
  let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: managed)) as! NSDictionary
  #expect(saved == ["version": 1, "defaultAction": "copy", "card": "compact"])
}
