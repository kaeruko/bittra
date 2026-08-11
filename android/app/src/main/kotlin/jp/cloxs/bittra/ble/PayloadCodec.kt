package jp.cloxs.bitra.ble

import java.nio.charset.StandardCharsets
import java.text.Normalizer

object PayloadCodec {
    
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

    fun encodeAdvert(teaser: String, nonce: Int): ByteArray {
        val t = normalizeTeaser(teaser)
        val teaserBytes = t.toByteArray(StandardCharsets.UTF_8)
        
        val data = ByteArray(5 + Math.min(255, teaserBytes.size))
        
        // magic (2B) little endian
        data[0] = (GATTProfile.MAGIC and 0xFF).toByte()
        data[1] = ((GATTProfile.MAGIC shr 8) and 0xFF).toByte()
        
        // nonce (2B) little endian
        data[2] = (nonce and 0xFF).toByte()
        data[3] = ((nonce shr 8) and 0xFF).toByte()
        
        // len (1B)
        data[4] = Math.min(255, teaserBytes.size).toByte()
        
        // teaser
        System.arraycopy(teaserBytes, 0, data, 5, Math.min(255, teaserBytes.size))
        
        return data
    }
    
    data class AdvertResult(val nonce: Int, val teaser: String)
    
    fun decodeAdvert(data: ByteArray): AdvertResult? {
        if (data.size < 5) return null
        
        val m0 = data[0].toInt() and 0xFF
        val m1 = (data[1].toInt() and 0xFF) shl 8
        val magic = m0 or m1
        
        if (magic != GATTProfile.MAGIC) return null
        
        val n0 = data[2].toInt() and 0xFF
        val n1 = (data[3].toInt() and 0xFF) shl 8
        val nonce = n0 or n1
        
        val len = data[4].toInt() and 0xFF
        val actualLen = Math.min(len, data.size - 5)
        val teaser = String(data, 5, actualLen, StandardCharsets.UTF_8)
        
        return AdvertResult(nonce, teaser)
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
