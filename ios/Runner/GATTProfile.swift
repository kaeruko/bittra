import Foundation
import CoreBluetooth

enum GATTProfile {
  static let serviceUUID = CBUUID(string: "9E2A0001-4B5A-4F5E-9A9D-1B7A00000001")
  static let reqCharUUID = CBUUID(string: "9E2A0002-4B5A-4F5E-9A9D-1B7A00000002")
  static let chunkCharUUID = CBUUID(string: "9E2A0003-4B5A-4F5E-9A9D-1B7A00000003")
  static let ackCharUUID = CBUUID(string: "9E2A0004-4B5A-4F5E-9A9D-1B7A00000004")

  static let magic: UInt16 = 0x6274 // "bt"
  static let maxTeaserUTF8Bytes: Int = 24
  static let maxCompactLocalNameUTF8Bytes: Int = 28
  static let previewBytes: Int = 120
}
