package com.kaeruko.bittora.ble

import java.nio.ByteBuffer

class ChunkAssembler(private val previewTarget: Int = GATTProfile.PREVIEW_BYTES) {
    private val chunks = mutableMapOf<Int, ByteArray>()
    private var receivedBytes = 0
    private var lastSeq: Int? = null

    fun reset() {
        chunks.clear()
        receivedBytes = 0
        lastSeq = null
    }

    data class AssembleResult(
        val previewReady: Boolean,
        val completed: Boolean,
        val fullData: ByteArray?
    )

    fun addChunk(seq: Int, flags: Int, payload: ByteArray): AssembleResult {
        if (!chunks.containsKey(seq)) {
            chunks[seq] = payload
            receivedBytes += payload.size
        }
        
        if ((flags and 0x01) != 0) {
            lastSeq = seq
        }

        val previewReady = receivedBytes >= previewTarget

        val last = lastSeq
        if (last != null) {
            // Check if we have 0..last
            for (i in 0..last) {
                if (!chunks.containsKey(i)) {
                    return AssembleResult(previewReady, false, null)
                }
            }
            
            // Reassemble
            var totalSize = 0
            for (i in 0..last) {
                totalSize += chunks[i]!!.size
            }
            
            val buffer = ByteBuffer.allocate(totalSize)
            for (i in 0..last) {
                buffer.put(chunks[i]!!)
            }
            
            return AssembleResult(previewReady, true, buffer.array())
        }
        
        return AssembleResult(previewReady, false, null)
    }
}
