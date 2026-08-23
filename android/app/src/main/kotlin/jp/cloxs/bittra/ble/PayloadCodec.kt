package jp.cloxs.bitra.ble

import java.nio.charset.StandardCharsets
import java.text.Normalizer

object PayloadCodec {

    private const val COMPACT_LOCAL_NAME_PREFIX = "~"
    private const val COMPACT_ID_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    
    fun normalizeTeaser(input: String): String {
        // 1) trim
        var s = input.trim()

        // 2) 制御文字を除去
        s = s.replace(Regex("\\p{Cntrl}"), "")

        // 3) NFC
        s = Normalizer.normalize(s, Normalizer.Form.NFC)

        // 4) 8文字固定
        if (s.length > 8) {
            s = s.substring(0, 8)
        }

        // 5) UTF-8最大18Bで切る
        return clipUTF8ToMaxBytes(s, GATTProfile.MAX_TEASER_UTF8_BYTES)
    }

    fun encodeAdvert(teaser: String, senderId: Long): ByteArray {
        val t = normalizeTeaser(teaser)
        val teaserBytes = t.toByteArray(StandardCharsets.UTF_8)
        
        val teaserLength = Math.min(255, teaserBytes.size)
        val data = ByteArray(7 + teaserLength)
        
        // magic (2B) little endian
        data[0] = (GATTProfile.MAGIC and 0xFF).toByte()
        data[1] = ((GATTProfile.MAGIC shr 8) and 0xFF).toByte()
        
        // Low 16 bits stay in the old nonce position for compatibility.
        data[2] = (senderId and 0xFF).toByte()
        data[3] = ((senderId shr 8) and 0xFF).toByte()
        
        // len (1B)
        data[4] = teaserLength.toByte()
        
        // teaser
        System.arraycopy(teaserBytes, 0, data, 5, teaserLength)

        // New receivers combine these optional trailing bytes with the old
        // nonce field. Old receivers safely ignore them.
        data[5 + teaserLength] = ((senderId shr 16) and 0xFF).toByte()
        data[6 + teaserLength] = ((senderId shr 24) and 0xFF).toByte()
        
        return data
    }

    fun decodeLocalName(localName: String): AdvertResult? {
        if (!localName.startsWith(COMPACT_LOCAL_NAME_PREFIX)) return null
        val encoded = localName.drop(1)
        if (encoded.length < 3) return null

        val high = COMPACT_ID_ALPHABET.indexOf(encoded[0])
        val middle = COMPACT_ID_ALPHABET.indexOf(encoded[1])
        val low = COMPACT_ID_ALPHABET.indexOf(encoded[2])
        if (high !in 0..15 || middle < 0 || low < 0) return null

        val senderId = ((high shl 12) or (middle shl 6) or low).toLong()
        val teaser = normalizeTeaser(encoded.drop(3))
        return if (teaser.isEmpty()) null else AdvertResult(senderId, teaser)
    }
    
    data class AdvertResult(val senderId: Long, val teaser: String)
    
    fun decodeAdvert(data: ByteArray): AdvertResult? {
        if (data.size < 5) return null
        
        val m0 = data[0].toInt() and 0xFF
        val m1 = (data[1].toInt() and 0xFF) shl 8
        val magic = m0 or m1
        
        if (magic != GATTProfile.MAGIC) return null
        
        val n0 = data[2].toInt() and 0xFF
        val n1 = (data[3].toInt() and 0xFF) shl 8
        val senderIdLow = n0 or n1
        
        val len = data[4].toInt() and 0xFF
        val actualLen = Math.min(len, data.size - 5)
        val teaser = String(data, 5, actualLen, StandardCharsets.UTF_8)

        val highOffset = 5 + len
        val senderIdHigh = if (data.size >= highOffset + 2) {
            (data[highOffset].toLong() and 0xFF) or
                ((data[highOffset + 1].toLong() and 0xFF) shl 8)
        } else {
            0L
        }
        val senderId = (senderIdLow.toLong() and 0xFFFF) or (senderIdHigh shl 16)
        
        return AdvertResult(senderId, teaser)
    }

    private fun clipUTF8ToMaxBytes(s: String, maxBytes: Int): String {
        var out = StringBuilder()
        var used = 0
        for (i in 0 until s.length) {
            val ch = s[i]
            // Surrogate pairs handling simplified for MVP (if needed use codePoints)
            val b = ch.toString().toByteArray(StandardCharsets.UTF_8).size
            if (used + b > maxBytes) {
                break
            }
            out.append(ch)
            used += b
        }
        return out.toString()
    }
}
