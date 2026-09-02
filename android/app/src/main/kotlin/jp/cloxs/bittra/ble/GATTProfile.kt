package jp.cloxs.bitra.ble

import java.util.UUID

object GATTProfile {
    val SERVICE_UUID: UUID = UUID.fromString("9E2A0001-4B5A-4F5E-9A9D-1B7A00000001")
    val REQ_CHAR_UUID: UUID = UUID.fromString("9E2A0002-4B5A-4F5E-9A9D-1B7A00000002")
    val CHUNK_CHAR_UUID: UUID = UUID.fromString("9E2A0003-4B5A-4F5E-9A9D-1B7A00000003")
    val ACK_CHAR_UUID: UUID = UUID.fromString("9E2A0004-4B5A-4F5E-9A9D-1B7A00000004")

    const val MAGIC: Int = 0x6274 // "bt"
    const val MAX_TEASER_UTF8_BYTES = 20
    const val MANUFACTURER_ID = 0x0118
    const val PREVIEW_BYTES = 120
}
