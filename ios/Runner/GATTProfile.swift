import Foundation
import CoreBluetooth

enum GATTProfile {
  // 適当に生成したUUIDに置換してOK（iOS/Androidで揃える）
  static let serviceUUID = CBUUID(string: "9E2A0001-4B5A-4F5E-9A9D-1B7A00000001")
  static let reqCharUUID = CBUUID(string: "9E2A0002-4B5A-4F5E-9A9D-1B7A00000002")
  static let chunkCharUUID = CBUUID(string: "9E2A0003-4B5A-4F5E-9A9D-1B7A00000003")

  static let magic: UInt16 = 0x6274 // "bt"
  // iOS compact local name is one marker byte, a three-character sender ID,
  // and at most 16 teaser bytes.
  // This leaves enough room for the 128-bit service UUID across the foreground
  // advertisement and local-name scan-response allowance.
  static let maxTeaserUTF8Bytes: Int = 16
  static let previewBytes: Int = 120
}
