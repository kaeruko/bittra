import Foundation
import CoreBluetooth

enum GATTProfile {
  // 適当に生成したUUIDに置換してOK（iOS/Androidで揃える）
  static let serviceUUID = CBUUID(string: "9E2A0001-4B5A-4F5E-9A9D-1B7A00000001")
  static let reqCharUUID = CBUUID(string: "9E2A0002-4B5A-4F5E-9A9D-1B7A00000002")
  static let chunkCharUUID = CBUUID(string: "9E2A0003-4B5A-4F5E-9A9D-1B7A00000003")

  static let magic: UInt16 = 0x6274 // "bt"
  // LocalName field: 31 bytes - 1 len - 1 type = 29 for base64 string
  // base64(5 header + N teaser) <= 29 → N <= 16
  static let maxTeaserUTF8Bytes: Int = 16
  static let previewBytes: Int = 120
}
