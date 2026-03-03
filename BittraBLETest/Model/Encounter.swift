import Foundation

struct Encounter: Identifiable, Hashable {
  let id: UUID
  let peerId: UUID
  let teaser: String
  var rssi: Int
  var firstSeen: Date
  var lastSeen: Date
  var count: Int

  var dedupeKey: String { "\(peerId.uuidString)|\(teaser)" }
}
