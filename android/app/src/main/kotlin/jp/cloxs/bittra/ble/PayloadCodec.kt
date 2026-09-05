package jp.cloxs.bitra.ble

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.text.Normalizer

object PayloadCodec {

    private const val COMPACT_LOCAL_NAME_PREFIX = "~"
    private const val COMPACT_ID_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    private const val COMPACT_SENDER_ID_MASK = 0xFFFFFFL

    fun normalizeTeaser(input: String): String {
        var s = input.trim()
        s = s.replace(Regex("\\p{Cntrl}"), "")
        s = Normalizer.normalize(s, Normalizer.Form.NFC)

        if (s.length > 8) {
            s = s.substring(0, 8)
        }

        return clipUTF8ToMaxBytes(s, GATTProfile.MAX_TEASER_UTF8_BYTES)
    }

    fun encodeAdvert(teaser: String, senderId: Long): ByteArray {
        val t = normalizeTeaser(teaser)
        val teaserBytes = t.toByteArray(StandardCharsets.UTF_8)
        require(teaserBytes.isNotEmpty()) { "teaser must not be empty" }
        require(teaserBytes.size <= GATTProfile.MAX_TEASER_UTF8_BYTES) {
            "teaser exceeds ${GATTProfile.MAX_TEASER_UTF8_BYTES} UTF-8 bytes"
        }

        // Legacy BLE scan responses have 27 bytes available for manufacturer
        // payload after the AD header and company identifier. Store a 24-bit
        // stable sender id followed by up to 24 UTF-8 teaser bytes so Japanese
        // titles can use the documented full 8 characters.
        val compactSenderId = compactSenderId(senderId)
        val data = ByteArray(3 + teaserBytes.size)
        data[0] = (compactSenderId and 0xFF).toByte()
        data[1] = ((compactSenderId shr 8) and 0xFF).toByte()
        data[2] = ((compactSenderId shr 16) and 0xFF).toByte()
        System.arraycopy(teaserBytes, 0, data, 3, teaserBytes.size)
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
        if (data.size >= 5 && hasLegacyMagic(data)) {
            return decodeLegacyAdvert(data)
        }
        return decodeCompactAdvert(data)
    }

    private fun decodeCompactAdvert(data: ByteArray): AdvertResult? {
        if (data.size < 4) return null

        val senderId =
            (data[0].toLong() and 0xFF) or
                ((data[1].toLong() and 0xFF) shl 8) or
                ((data[2].toLong() and 0xFF) shl 16)
        if (senderId == 0L) return null

        val teaserBytes = data.copyOfRange(3, data.size)
        val teaser = decodeUtf8(teaserBytes) ?: return null
        if (teaser.isEmpty()) return null
        return AdvertResult(senderId, teaser)
    }

    private fun decodeLegacyAdvert(data: ByteArray): AdvertResult? {
        val n0 = data[2].toInt() and 0xFF
        val n1 = (data[3].toInt() and 0xFF) shl 8
        val senderIdLow = n0 or n1

        val len = data[4].toInt() and 0xFF
        if (data.size < 5 + len) return null
        val teaserBytes = data.copyOfRange(5, 5 + len)
        val teaser = decodeUtf8(teaserBytes) ?: return null
        if (teaser.isEmpty()) return null

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

    private fun hasLegacyMagic(data: ByteArray): Boolean {
        val m0 = data[0].toInt() and 0xFF
        val m1 = (data[1].toInt() and 0xFF) shl 8
        return (m0 or m1) == GATTProfile.MAGIC
    }

    private fun compactSenderId(senderId: Long): Long {
        var compact = senderId and COMPACT_SENDER_ID_MASK
        if (compact == 0L) compact = 1L

        // Reserve the old magic prefix so decoders can distinguish the new
        // compact payload from the legacy format without spending a version byte.
        if ((compact and 0xFFFFL) == GATTProfile.MAGIC.toLong()) {
            compact = compact xor 0x000001L
        }
        return compact
    }

    private fun decodeUtf8(bytes: ByteArray): String? {
        return try {
            StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes))
                .toString()
        } catch (_: CharacterCodingException) {
            null
        }
    }

    private fun clipUTF8ToMaxBytes(s: String, maxBytes: Int): String {
        val out = StringBuilder()
        var used = 0
        var index = 0
        while (index < s.length) {
            val codePoint = s.codePointAt(index)
            val text = String(Character.toChars(codePoint))
            val bytes = text.toByteArray(StandardCharsets.UTF_8).size
            if (used + bytes > maxBytes) {
                break
            }
            out.append(text)
            used += bytes
            index += Character.charCount(codePoint)
        }
        return out.toString()
    }
}
