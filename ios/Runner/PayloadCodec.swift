import Foundation

enum PayloadCodec {

  // iOS only lets peripheral apps advertise service UUIDs and a local name.
  // Keep the iOS local-name representation compact enough to coexist with the
  // 128-bit Bittra service UUID. The binary format remains in use for Android
  // manufacturer data and for decoding older senders.
  private static let compactLocalNamePrefix = "~"
  private static let compactIdAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

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
    let encodedId = String([
      compactIdAlphabet[Int((senderId >> 12) & 0x0F)],
      compactIdAlphabet[Int((senderId >> 6) & 0x3F)],
      compactIdAlphabet[Int(senderId & 0x3F)]
    ])
    return compactLocalNamePrefix + encodedId + normalizeTeaser(teaser)
  }

  static func decodeLocalName(_ localName: String) -> (senderId: UInt32, teaser: String)? {
    guard localName.hasPrefix(compactLocalNamePrefix) else { return nil }
    let encoded = localName.dropFirst()
    guard encoded.count >= 3 else { return nil }

    let idCharacters = Array(encoded.prefix(3))
    guard
      let high = compactIdAlphabet.firstIndex(of: idCharacters[0]), high < 16,
      let middle = compactIdAlphabet.firstIndex(of: idCharacters[1]),
      let low = compactIdAlphabet.firstIndex(of: idCharacters[2])
    else { return nil }

    let senderId = UInt32((high << 12) | (middle << 6) | low)
    let teaser = normalizeTeaser(String(encoded.dropFirst(3)))
    return teaser.isEmpty ? nil : (senderId, teaser)
  }

  static func decodeAdvert(_ data: Data) -> (senderId: UInt32, teaser: String)? {
    if data.count >= 5 && hasLegacyMagic(data) {
      return decodeLegacyAdvert(data)
    }
    return decodeCompactAdvert(data)
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
