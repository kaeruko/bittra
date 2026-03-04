import Foundation

enum PayloadCodec {

  static func normalizeTeaser(_ input: String) -> String {
    // 1) trim
    var s = input.trimmingCharacters(in: .whitespacesAndNewlines)

    // 2) 制御文字を除去
    s.removeAll { ch in
      ch.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    // 3) NFC
    s = s.precomposedStringWithCanonicalMapping

    // 4) UI的に8文字固定
    if s.count > 8 { s = String(s.prefix(8)) }

    // 5) UTF-8バイトで安全に切る（最大18B）
    s = clipUTF8ToMaxBytes(s, maxBytes: GATTProfile.maxTeaserUTF8Bytes)
    return s
  }

  static func encodeAdvert(teaser: String, nonce: UInt16) -> Data {
    let t = normalizeTeaser(teaser)
    let teaserBytes = Data(t.utf8)

    var data = Data()
    // magic (2B) little-endian
    data.append(UInt8(GATTProfile.magic & 0xFF))
    data.append(UInt8((GATTProfile.magic >> 8) & 0xFF))
    // nonce (2B) little-endian
    data.append(UInt8(nonce & 0xFF))
    data.append(UInt8((nonce >> 8) & 0xFF))
    // len (1B)
    data.append(UInt8(min(255, teaserBytes.count)))
    // teaser
    data.append(teaserBytes)
    return data
  }

  static func decodeAdvert(_ data: Data) -> (nonce: UInt16, teaser: String)? {
    if data.count < 5 { return nil }
    let m0 = UInt16(data[0])
    let m1 = UInt16(data[1]) << 8
    let magic = m0 | m1
    guard magic == GATTProfile.magic else { return nil }

    let n0 = UInt16(data[2])
    let n1 = UInt16(data[3]) << 8
    let nonce = n0 | n1

    let len = Int(data[4])
    guard data.count >= 5 + len else { return nil }

    let teaserBytes = data.subdata(in: 5..<(5 + len))
    let teaser = String(data: teaserBytes, encoding: .utf8) ?? ""
    return (nonce, teaser)
  }

  // UTF-8を壊さず maxBytes 以内に切る
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
