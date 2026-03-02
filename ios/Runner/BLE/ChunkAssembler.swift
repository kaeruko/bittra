import Foundation

final class ChunkAssembler {
  private var chunks: [UInt16: Data] = [:]
  private var receivedBytes: Int = 0
  private var lastSeq: UInt16?
  private let previewTarget: Int

  init(previewTarget: Int = GATTProfile.previewBytes) {
    self.previewTarget = previewTarget
  }

  func reset() {
    chunks.removeAll()
    receivedBytes = 0
    lastSeq = nil
  }

  // returns: (previewReady, completed, fullData)
  func addChunk(seq: UInt16, flags: UInt8, payload: Data) -> (Bool, Bool, Data?) {
    if chunks[seq] == nil {
      chunks[seq] = payload
      receivedBytes += payload.count
    }
    if (flags & 0x01) != 0 {
      lastSeq = seq
    }

    let previewReady = receivedBytes >= previewTarget

    // 完了判定：0..lastSeqが全部揃ってる
    if let last = lastSeq {
      for i in 0...last {
        if chunks[i] == nil { return (previewReady, false, nil) }
      }
      var data = Data()
      for i in 0...last { data.append(chunks[i]!) }
      return (previewReady, true, data)
    }
    return (previewReady, false, nil)
  }
}
