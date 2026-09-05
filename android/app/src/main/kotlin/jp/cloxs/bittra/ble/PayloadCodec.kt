package jp.cloxs.bitra.ble

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.text.Normalizer

object PayloadCodec {

    private const val COMPACT_LOCAL_NAME_PREFIX = "~"
    private const val PACKED_LOCAL_NAME_PREFIX = "!"
    private const val COMPACT_ID_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    private const val PACKED_ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-:+=^!/*?&<>()[]{}@%$#"
    private const val PACKED_TEASER_BYTES = 16
    private const val PACKED_ENCODED_LENGTH = 20
    private const val COMPACT_SENDER_ID_MASK = 0xFFFFFFL
    private const val LEGACY_MAX_TEASER_UTF8_BYTES = 20

    fun normalizeTeaser(input: String): String {
        var s = input.trim()
        s = s.replace(Regex("\\p{Cntrl}"), "")
        s = s.replace("\uFE0E", "").replace("\uFE0F", "")
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

        // Preserve the existing wire format whenever it fits so older app
        // versions can still discover normal short titles. Only 21-24 byte
        // teasers need the compact format required for Japanese 7-8 characters.
        return if (teaserBytes.size <= LEGACY_MAX_TEASER_UTF8_BYTES) {
            encodeLegacyAdvert(teaserBytes, senderId)
        } else {
            encodeCompactAdvert(teaserBytes, senderId)
        }
    }

    private fun encodeLegacyAdvert(teaserBytes: ByteArray, senderId: Long): ByteArray {
        val teaserLength = teaserBytes.size
        val data = ByteArray(7 + teaserLength)

        data[0] = (GATTProfile.MAGIC and 0xFF).toByte()
        data[1] = ((GATTProfile.MAGIC shr 8) and 0xFF).toByte()
        data[2] = (senderId and 0xFF).toByte()
        data[3] = ((senderId shr 8) and 0xFF).toByte()
        data[4] = teaserLength.toByte()
        System.arraycopy(teaserBytes, 0, data, 5, teaserLength)
        data[5 + teaserLength] = ((senderId shr 16) and 0xFF).toByte()
        data[6 + teaserLength] = ((senderId shr 24) and 0xFF).toByte()

        return data
    }

    private fun encodeCompactAdvert(teaserBytes: ByteArray, senderId: Long): ByteArray {
        // A legacy BLE scan response has 27 bytes available for manufacturer
        // payload after the AD header and company identifier. A 24-bit stable
        // sender id plus 24 UTF-8 title bytes fits exactly.
        val compactSenderId = compactSenderId(senderId)
        val data = ByteArray(3 + teaserBytes.size)
        data[0] = (compactSenderId and 0xFF).toByte()
        data[1] = ((compactSenderId shr 8) and 0xFF).toByte()
        data[2] = ((compactSenderId shr 16) and 0xFF).toByte()
        System.arraycopy(teaserBytes, 0, data, 3, teaserBytes.size)
        return data
    }

    fun decodeLocalName(localName: String): AdvertResult? {
        return when {
            localName.startsWith(COMPACT_LOCAL_NAME_PREFIX) -> decodeDirectLocalName(localName)
            localName.startsWith(PACKED_LOCAL_NAME_PREFIX) -> decodePackedLocalName(localName)
            else -> null
        }
    }

    private fun decodeDirectLocalName(localName: String): AdvertResult? {
        val encoded = localName.drop(1)
        if (encoded.length < 3) return null

        val senderId = decodeSenderId(encoded.substring(0, 3)) ?: return null
        val teaser = normalizeTeaser(encoded.drop(3))
        return if (teaser.isEmpty()) null else AdvertResult(senderId, teaser)
    }

    private fun decodePackedLocalName(localName: String): AdvertResult? {
        val encoded = localName.drop(1)
        if (encoded.length != 3 + PACKED_ENCODED_LENGTH) return null

        val senderId = decodeSenderId(encoded.substring(0, 3)) ?: return null
        val teaser = decodePackedTeaser(encoded.drop(3)) ?: return null
        return AdvertResult(senderId, teaser)
    }

    private fun decodeSenderId(encodedId: String): Long? {
        if (encodedId.length != 3) return null
        val high = COMPACT_ID_ALPHABET.indexOf(encodedId[0])
        val middle = COMPACT_ID_ALPHABET.indexOf(encodedId[1])
        val low = COMPACT_ID_ALPHABET.indexOf(encodedId[2])
        if (high !in 0..15 || middle < 0 || low < 0) return null
        return ((high shl 12) or (middle shl 6) or low).toLong()
    }

    private fun decodePackedTeaser(encoded: String): String? {
        if (encoded.length != PACKED_ENCODED_LENGTH) return null

        val bytes = ByteArray(PACKED_TEASER_BYTES)
        var byteOffset = 0
        var encodedOffset = 0
        while (encodedOffset < PACKED_ENCODED_LENGTH) {
            var value = 0L
            for (i in 0 until 5) {
                val digit = PACKED_ALPHABET.indexOf(encoded[encodedOffset + i])
                if (digit < 0) return null
                value = value * 85L + digit
                if (value > 0xFFFFFFFFL) return null
            }

            bytes[byteOffset] = ((value shr 24) and 0xFF).toByte()
            bytes[byteOffset + 1] = ((value shr 16) and 0xFF).toByte()
            bytes[byteOffset + 2] = ((value shr 8) and 0xFF).toByte()
            bytes[byteOffset + 3] = (value and 0xFF).toByte()
            byteOffset += 4
            encodedOffset += 5
        }

        var end = bytes.size
        while (end >= 2 && bytes[end - 2] == 0.toByte() && bytes[end - 1] == 0.toByte()) {
            end -= 2
        }
        if (end == 0 || end % 2 != 0) return null

        val teaser = decodeUtf16BE(bytes.copyOfRange(0, end)) ?: return null
        if (teaser.isEmpty() || normalizeTeaser(teaser) != teaser) return null
        return teaser
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

        // Reserve the old magic prefix so decoders can distinguish compact
        // payloads from the legacy format without spending a version byte.
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

    private fun decodeUtf16BE(bytes: ByteArray): String? {
        return try {
            StandardCharsets.UTF_16BE.newDecoder()
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
