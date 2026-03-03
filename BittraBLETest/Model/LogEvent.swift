import Foundation

struct LogEvent: Identifiable {
  let id = UUID()
  let ts: Date
  let tag: String
  let msg: String
}
