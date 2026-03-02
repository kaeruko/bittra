package com.kaeruko.bittora.ble

import java.util.UUID

object GATTProfile {
    // 互換性のためiOSと揃える
    val SERVICE_UUID: UUID = UUID.fromString("9E2A0001-4B5A-4F5E-9A9D-1B7A00000001")
    val REQ_CHAR_UUID: UUID = UUID.fromString("9E2A0002-4B5A-4F5E-9A9D-1B7A00000002")
    val CHUNK_CHAR_UUID: UUID = UUID.fromString("9E2A0003-4B5A-4F5E-9A9D-1B7A00000003")

    const val MAGIC: Int = 0x6274 // "bt"
    const val MAX_TEASER_UTF8_BYTES = 18
    const val PREVIEW_BYTES = 120
}
