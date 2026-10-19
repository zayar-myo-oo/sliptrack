import Foundation
import CryptoKit
import Security

// Shared only by the explicitly invoked Share extension and the containing app.
// No unencrypted receipt image is written to disk.
enum ShareInbox {
  static var group: String { Bundle.main.object(forInfoDictionaryKey: "SlipTrackAppGroup") as? String ?? "group.app.sliptrack.sliptrack" }
  static func directory() throws -> URL {
    guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { throw InboxError.unavailable }
    var folder = root.appendingPathComponent("ReceiptInbox", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var values = URLResourceValues(); values.isExcludedFromBackup = true; try folder.setResourceValues(values)
    return folder
  }
  static func key() throws -> SymmetricKey {
    guard let accessGroup = Bundle.main.object(forInfoDictionaryKey: "SlipTrackKeychainGroup") as? String else { throw InboxError.unavailable }
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.sliptrack.share.key.v1",
      kSecAttrAccount as String: "inbox", kSecAttrAccessGroup as String: accessGroup]
    var search = query; search[kSecReturnData as String] = true; search[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(search as CFDictionary, &item)
    if status == errSecSuccess, let data = item as? Data { return SymmetricKey(data: data) }
    guard status == errSecItemNotFound else { throw InboxError.unavailable }
    let newKey = SymmetricKey(size: .bits256)
    var insertion = query; insertion[kSecValueData as String] = newKey.withUnsafeBytes { Data($0) }
    insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let added = SecItemAdd(insertion as CFDictionary, nil)
    if added == errSecDuplicateItem { return try key() }
    guard added == errSecSuccess else { throw InboxError.unavailable }
    return newKey
  }
  static func store(_ data: Data) throws {
    let id = UUID().uuidString
    let box = try AES.GCM.seal(data, using: key(), authenticating: Data(id.utf8))
    guard let combined = box.combined else { throw InboxError.unavailable }
    try combined.write(to: directory().appendingPathComponent(id + ".slipshare"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
  static func sources() throws -> [String] {
    try FileManager.default.contentsOfDirectory(at: directory(), includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "slipshare" }.map { "shared:" + $0.deletingPathExtension().lastPathComponent }.sorted()
  }
  static func file(_ source: String) throws -> (String, URL) {
    let id = String(source.dropFirst("shared:".count))
    guard source.hasPrefix("shared:"), UUID(uuidString: id) != nil else { throw InboxError.unavailable }
    return (id, try directory().appendingPathComponent(id + ".slipshare"))
  }
  static func read(_ source: String) throws -> Data {
    let (id, url) = try file(source)
    return try AES.GCM.open(AES.GCM.SealedBox(combined: Data(contentsOf: url)), using: key(), authenticating: Data(id.utf8))
  }
  static func remove(_ source: String) throws { let (_, url) = try file(source); try FileManager.default.removeItem(at: url) }
  static func clear() throws { for source in try sources() { try remove(source) } }
  enum InboxError: Error { case unavailable }
}
