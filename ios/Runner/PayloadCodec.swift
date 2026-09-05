import Foundation

enum PayloadCodec {

  // iOS peripheral advertising uses a compact local name for the teaser.
  // Direct format: "~" + 3-char sender id + UTF-8 teaser.
  // Long titles use a packed format that keeps the full 8 UTF-16 code-unit
  // title inside the 25-byte local-name budget observed on real devices.
  private static let compactLocalNamePrefix = "~"
  private static let packedLocalNamePrefix = "!"
  private static let compactIdAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
  private static let packedAlphabet = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-:+=^!/*?&<>()[]{}@%$#")
  private static let packedTeaserBytes = 16
  private static let packedEncodedLength = 20

  static func normalizeTeaser(_ input: String) -> String {
    var s = input.trimmingCharacters(in: .whitespacesAndNewlines)

    s.removeAll { ch in
      ch.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    s = s.precomposedStringWithCanonicalMapping

    if s.count > 8 { s = String(s.prefix(8)) }

    s = clipUTF8ToMaxBytes(s, maxBytes: GATTProfile.maxTeaserUTF8Bytes)
    return s
  }

  static func encodeAdvert(teaser: String, nonce: UInt16) -> Data {
    let t = normalizeTeaser(teaser)
    let teaserBytes = Data(t.utf8)

    var data = Data()
    data.append(UInt8(GATTProfile.magic & 0xFF))
    data.append(UInt8((GATTProfile.magic >> 8) & 0xFF))
    data.append(UInt8(nonce & 0xFF))
    data.append(UInt8((nonce >> 8) & 0xFF))
    data.append(UInt8(min(255, teaserBytes.count)))
    data.append(teaserBytes)
    return data
  }

  static func encodeLocalName(teaser: String, senderId: UInt16) -> String {
    let normalizedTeaser = normalizeTeaser(teaser)
    precondition(!normalizedTeaser.isEmpty, "teaser must not be empty")

    let encodedId = encodeSenderId(senderId)
    let directLocalName = compactLocalNamePrefix + encodedId + normalizedTeaser
    if directLocalName.utf8.count <= GATTProfile.maxCompactLocalNameUTF8Bytes {
      return directLocalName
    }

    let packedTeaser = encodePackedTeaser(normalizedTeaser)
    let packedLocalName = packedLocalNamePrefix + encodedId + packedTeaser
    precondition(
      packedLocalName.utf8.count <= GATTProfile.maxCompactLocalNameUTF8Bytes,
      "packed local name exceeds \(GATTProfile.maxCompactLocalNameUTF8Bytes) UTF-8 bytes"
    )
    return packedLocalName
  }

  static func decodeLocalName(_ localName: String) -> (senderId: UInt32, teaser: String)? {
    if localName.hasPrefix(compactLocalNamePrefix) {
      let encoded = localName.dropFirst()
      guard encoded.count >= 3 else { return nil }
      guard let senderId = decodeSenderId(Array(encoded.prefix(3))) else { return nil }
      let teaser = normalizeTeaser(String(encoded.dropFirst(3)))
      return teaser.isEmpty ? nil : (senderId, teaser)
    }

    if localName.hasPrefix(packedLocalNamePrefix) {
      let encoded = localName.dropFirst()
      guard encoded.count == 3 + packedEncodedLength else { return nil }
      guard let senderId = decodeSenderId(Array(encoded.prefix(3))) else { return nil }
      guard let teaser = decodePackedTeaser(String(encoded.dropFirst(3))) else { return nil }
      return (senderId, teaser)
    }

    return nil
  }

  static func decodeAdvert(_ data: Data) -> (senderId: UInt32, teaser: String)? {
    if data.count >= 5 && hasLegacyMagic(data) {
      return decodeLegacyAdvert(data)
    }
    return decodeCompactAdvert(data)
  }

  private static func encodeSenderId(_ senderId: UInt16) -> String {
    String([
      compactIdAlphabet[Int((senderId >> 12) & 0x0F)],
      compactIdAlphabet[Int((senderId >> 6) & 0x3F)],
      compactIdAlphabet[Int(senderId & 0x3F)]
    ])
  }

  private static func decodeSenderId(_ idCharacters: [Character]) -> UInt32? {
    guard idCharacters.count == 3 else { return nil }
    guard
      let high = compactIdAlphabet.firstIndex(of: idCharacters[0]), high < 16,
      let middle = compactIdAlphabet.firstIndex(of: idCharacters[1]),
      let low = compactIdAlphabet.firstIndex(of: idCharacters[2])
    else { return nil }

    return UInt32((high << 12) | (middle << 6) | low)
  }

  private static func encodePackedTeaser(_ teaser: String) -> String {
    var bytes: [UInt8] = []
    bytes.reserveCapacity(packedTeaserBytes)
    for unit in teaser.utf16 {
      bytes.append(UInt8((unit >> 8) & 0xFF))
      bytes.append(UInt8(unit & 0xFF))
    }
    precondition(
      bytes.count <= packedTeaserBytes,
      "teaser exceeds 8 UTF-16 code units and cannot fit packed local name"
    )
    while bytes.count < packedTeaserBytes {
      bytes.append(0)
    }

    var output = ""
    output.reserveCapacity(packedEncodedLength)
    for offset in stride(from: 0, to: packedTeaserBytes, by: 4) {
      var value =
        (UInt32(bytes[offset]) << 24) |
        (UInt32(bytes[offset + 1]) << 16) |
        (UInt32(bytes[offset + 2]) << 8) |
        UInt32(bytes[offset + 3])
      var digits = Array(repeating: 0, count: 5)
      for index in stride(from: 4, through: 0, by: -1) {
        digits[index] = Int(value % 85)
        value /= 85
      }
      for digit in digits {
        output.append(packedAlphabet[digit])
      }
    }
    return output
  }

  private static func decodePackedTeaser(_ encoded: String) -> String? {
    let chars = Array(encoded)
    guard chars.count == packedEncodedLength else { return nil }

    var bytes: [UInt8] = []
    bytes.reserveCapacity(packedTeaserBytes)
    for offset in stride(from: 0, to: packedEncodedLength, by: 5) {
      var value: UInt64 = 0
      for index in offset..<(offset + 5) {
        guard let digit = packedAlphabet.firstIndex(of: chars[index]) else { return nil }
        value = value * 85 + UInt64(digit)
        guard value <= UInt64(UInt32.max) else { return nil }
      }
      let block = UInt32(value)
      bytes.append(UInt8((block >> 24) & 0xFF))
      bytes.append(UInt8((block >> 16) & 0xFF))
      bytes.append(UInt8((block >> 8) & 0xFF))
      bytes.append(UInt8(block & 0xFF))
    }

    while bytes.count >= 2 && bytes[bytes.count - 2] == 0 && bytes[bytes.count - 1] == 0 {
      bytes.removeLast(2)
    }
    guard !bytes.isEmpty, bytes.count.isMultiple(of: 2) else { return nil }
    guard let teaser = String(data: Data(bytes), encoding: .utf16BigEndian), !teaser.isEmpty else {
      return nil
    }
    guard normalizeTeaser(teaser) == teaser else { return nil }
    return teaser
  }

  private static func decodeCompactAdvert(_ data: Data) -> (senderId: UInt32, teaser: String)? {
    guard data.count >= 4 else { return nil }

    let senderId = UInt32(data[0]) | (UInt32(data[1]) << 8) | (UInt32(data[2]) << 16)
    guard senderId != 0 else { return nil }

    let teaserBytes = data.subdata(in: 3..<data.count)
    guard let teaser = String(data: teaserBytes, encoding: .utf8), !teaser.isEmpty else {
      return nil
    }
    return (senderId, teaser)
  }

  private static func decodeLegacyAdvert(_ data: Data) -> (senderId: UInt32, teaser: String)? {
    let n0 = UInt16(data[2])
    let n1 = UInt16(data[3]) << 8
    let senderIdLow = n0 | n1

    let len = Int(data[4])
    guard data.count >= 5 + len else { return nil }

    let teaserBytes = data.subdata(in: 5..<(5 + len))
    guard let teaser = String(data: teaserBytes, encoding: .utf8), !teaser.isEmpty else {
      return nil
    }

    let highOffset = 5 + len
    let senderIdHigh: UInt32
    if data.count >= highOffset + 2 {
      senderIdHigh = UInt32(data[highOffset]) | (UInt32(data[highOffset + 1]) << 8)
    } else {
      senderIdHigh = 0
    }
    let senderId = UInt32(senderIdLow) | (senderIdHigh << 16)
    return (senderId, teaser)
  }

  private static func hasLegacyMagic(_ data: Data) -> Bool {
    let m0 = UInt16(data[0])
    let m1 = UInt16(data[1]) << 8
    return (m0 | m1) == GATTProfile.magic
  }

  private static func clipUTF8ToMaxBytes(_ s: String, maxBytes: Int) -> String {
    var out = ""
    var used = 0
    for ch in s {
      let b = String(ch).utf8.count
      if used + b > maxBytes { break }
      out.append(ch)
      used += b
    }
    return out
  }
}
