import java.nio.charset.StandardCharsets

object Test {
    @JvmStatic
    fun main(args: Array<String>) {
        val input = "dGIr6w/jgYLjgYTjgbvjgpPjga"
        println("Input length: \${input.length}")
        
        // Pad to multiple of 4
        val padded = input.padEnd(input.length + (4 - input.length % 4) % 4, '=')
        println("Padded: \$padded, length: \${padded.length}")
        
        // Android base64 uses standard java lib underneath, or we can use java.util.Base64 for pure CLI testing
        try {
            val decoded = java.util.Base64.getDecoder().decode(padded)
            println("Decoded size: \${decoded.size}")
            
            // Try to decode internal bytes (like PayloadCodec)
            // magic: 2, nonce: 2, len: 1, text: len
            if (decoded.size >= 5) {
                val magic = (decoded[0].toInt() and 0xFF) or ((decoded[1].toInt() and 0xFF) shl 8)
                val nonce = (decoded[2].toInt() and 0xFF) or ((decoded[3].toInt() and 0xFF) shl 8)
                val len = decoded[4].toInt() and 0xFF
                
                println(String.format("Magic: %04X, Nonce: %04X, Len: %d", magic, nonce, len))
                
                if (decoded.size >= 5 + len) {
                    val teaser = String(decoded, 5, len, StandardCharsets.UTF_8)
                    println("Teaser: \$teaser")
                } else {
                    println("ERR: Decoded size \${decoded.size} is smaller than 5 + len \${5+len}")
                }
            } else {
                println("ERR: Decoded size \${decoded.size} too small for header")
            }
        } catch (e: Exception) {
            println("Exception: \${e.message}")
            e.printStackTrace()
        }
    }
}
