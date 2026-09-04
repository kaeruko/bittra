package jp.cloxs.bitra.ble

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import java.security.SecureRandom
import java.util.UUID

@SuppressLint("MissingPermission")
class BlePeripheral(
    private val context: Context,
    private val log: (String, String) -> Unit,
    private val onDeliveryReceipt: (String, Int) -> Unit
) {

    companion object {
        private const val INITIAL_HIGH_PERFORMANCE_MS = 15_000L
    }

    private val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val adapter: BluetoothAdapter? = bluetoothManager.adapter
    private val advertiser = adapter?.bluetoothLeAdvertiser

    private var gattServer: BluetoothGattServer? = null
    private var isAdvertising = false
    private var isGattServiceReady = false
    private var startAdvertisingWhenReady = false
    private var currentAdvertiseMode: Int? = null
    private var advertiseDowngradeRunnable: Runnable? = null

    private var myNoticeId: String = ""
    private var myTeaser: String = ""
    private var myBody: String = ""

    private val pendingNotifyPackets = mutableListOf<ByteArray>()
    private var isNotifying = false
    private var subscribedDevice: BluetoothDevice? = null

    private val pendingNoticeByDevice = mutableMapOf<String, String>()
    private val acknowledgedDevicesByNotice = mutableMapOf<String, MutableSet<String>>()

    private val mainHandler = Handler(Looper.getMainLooper())

    private val senderId: Long by lazy {
        val prefs = context.getSharedPreferences("bittra_ble", Context.MODE_PRIVATE)
        if (prefs.contains("sender_id")) {
            prefs.getLong("sender_id", 1L)
        } else {
            var generated = SecureRandom().nextInt().toLong() and 0xFFFFFFFFL
            if (generated == 0L) generated = 1L
            prefs.edit().putLong("sender_id", generated).apply()
            generated
        }
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            isAdvertising = true
            val mode = currentAdvertiseMode
            log("ADV", "startAdvertising success mode=${advertiseModeName(mode)}")
            if (mode == AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY) {
                scheduleAdvertiseDowngrade()
            }
        }

        override fun onStartFailure(errorCode: Int) {
            cancelAdvertiseDowngrade()
            log("ADV", "startAdvertising fail: $errorCode")
            isAdvertising = false
            currentAdvertiseMode = null
        }
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onServiceAdded(status: Int, service: BluetoothGattService) {
            if (service.uuid != GATTProfile.SERVICE_UUID) return
            isGattServiceReady = status == BluetoothGatt.GATT_SUCCESS
            log("PERIPH", "GATT service ready status=$status")
            if (isGattServiceReady && startAdvertisingWhenReady) {
                startAdvertisingWhenReady = false
                startAdvertising(initialBoost = true)
            }
        }

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            log("PERIPH", "connectionStateChange ${device.address} status=$status newState=$newState")
            if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                pendingNoticeByDevice.remove(device.address)
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            when (characteristic.uuid) {
                GATTProfile.REQ_CHAR_UUID -> {
                    if (!value.contentEquals(byteArrayOf(0x01))) {
                        log("GATT", "invalid REQ payload bytes=${value.size}")
                        if (responseNeeded) {
                            gattServer?.sendResponse(
                                device,
                                requestId,
                                BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED,
                                offset,
                                null
                            )
                        }
                        return
                    }
                    check(myNoticeId.isNotBlank()) { "REQ received without active noticeId" }
                    pendingNoticeByDevice[device.address] = myNoticeId
                    log("GATT", "REQ received from central noticeId=$myNoticeId")

                    if (responseNeeded) {
                        gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
                    }
                    sendBodyPreviewThenRest(device)
                }

                GATTProfile.ACK_CHAR_UUID -> {
                    if (!value.contentEquals(byteArrayOf(0x02))) {
                        log("GATT", "invalid ACK payload bytes=${value.size}")
                        if (responseNeeded) {
                            gattServer?.sendResponse(
                                device,
                                requestId,
                                BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED,
                                offset,
                                null
                            )
                        }
                        return
                    }

                    val noticeId = pendingNoticeByDevice.remove(device.address)
                    if (noticeId == null) {
                        log("GATT", "ACK without pending body device=${device.address}")
                        if (responseNeeded) {
                            gattServer?.sendResponse(
                                device,
                                requestId,
                                BluetoothGatt.GATT_FAILURE,
                                offset,
                                null
                            )
                        }
                        return
                    }

                    val acknowledgedDevices = acknowledgedDevicesByNotice.getOrPut(noticeId) {
                        mutableSetOf()
                    }
                    val added = acknowledgedDevices.add(device.address)
                    if (responseNeeded) {
                        gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
                    }
                    if (added) {
                        log("GATT", "delivery ACK noticeId=$noticeId count=${acknowledgedDevices.size}")
                        onDeliveryReceipt(noticeId, acknowledgedDevices.size)
                    }
                }

                else -> {
                    if (responseNeeded) {
                        gattServer?.sendResponse(
                            device,
                            requestId,
                            BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED,
                            offset,
                            null
                        )
                    }
                }
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            if (BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE.contentEquals(value)) {
                subscribedDevice = device
            }
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
            }
        }

        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            super.onNotificationSent(device, status)
            if (status == BluetoothGatt.GATT_SUCCESS) {
                isNotifying = false
                flushNotifyQueue(device)
            } else {
                log("GATT", "onNotificationSent error $status")
                isNotifying = false
            }
        }
    }

    fun setContent(noticeId: String, teaser: String, body: String) {
        require(noticeId.isNotBlank()) { "noticeId must not be blank" }
        myNoticeId = noticeId
        myTeaser = teaser
        myBody = body
    }

    fun start() {
        check(myNoticeId.isNotBlank()) { "Cannot start advertising without noticeId" }
        if (PayloadCodec.normalizeTeaser(myTeaser).isEmpty()) {
            stop()
            log("PERIPH", "skip empty teaser advertisement")
            return
        }
        if (adapter == null || !adapter.isEnabled) {
            log("PERIPH", "Bluetooth not poweredOn yet")
            return
        }

        cancelAdvertiseDowngrade()
        if (isAdvertising) {
            advertiser?.stopAdvertising(advertiseCallback)
            isAdvertising = false
            currentAdvertiseMode = null
        }

        setupGATTIfNeeded()
        if (isGattServiceReady) {
            startAdvertising(initialBoost = true)
        } else {
            startAdvertisingWhenReady = true
        }
    }

    fun stop() {
        cancelAdvertiseDowngrade()
        startAdvertisingWhenReady = false
        if (isAdvertising) {
            advertiser?.stopAdvertising(advertiseCallback)
            isAdvertising = false
            log("PERIPH", "stopAdvertising")
        }
        currentAdvertiseMode = null
        pendingNotifyPackets.clear()
        pendingNoticeByDevice.clear()
        isNotifying = false
        subscribedDevice = null
        gattServer?.clearServices()
        gattServer?.close()
        gattServer = null
        isGattServiceReady = false
    }

    private fun setupGATTIfNeeded() {
        if (gattServer != null) return

        gattServer = bluetoothManager.openGattServer(context, gattServerCallback)
        isGattServiceReady = false

        val service = BluetoothGattService(GATTProfile.SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)

        val reqChar = BluetoothGattCharacteristic(
            GATTProfile.REQ_CHAR_UUID,
            BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE or BluetoothGattCharacteristic.PROPERTY_WRITE,
            BluetoothGattCharacteristic.PERMISSION_WRITE
        )

        val chunkChar = BluetoothGattCharacteristic(
            GATTProfile.CHUNK_CHAR_UUID,
            BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ
        )

        val ackChar = BluetoothGattCharacteristic(
            GATTProfile.ACK_CHAR_UUID,
            BluetoothGattCharacteristic.PROPERTY_WRITE,
            BluetoothGattCharacteristic.PERMISSION_WRITE
        )

        val cccDescriptor = BluetoothGattDescriptor(
            UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"),
            BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
        )
        chunkChar.addDescriptor(cccDescriptor)

        service.addCharacteristic(reqChar)
        service.addCharacteristic(chunkChar)
        service.addCharacteristic(ackChar)

        gattServer?.addService(service)
        log("PERIPH", "GATT service added")
    }

    private fun startAdvertising(initialBoost: Boolean) {
        val advertiseMode = if (initialBoost) {
            AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY
        } else {
            AdvertiseSettings.ADVERTISE_MODE_BALANCED
        }
        startAdvertisingWithMode(advertiseMode)
    }

    private fun startAdvertisingWithMode(advertiseMode: Int) {
        if (advertiser == null) return

        cancelAdvertiseDowngrade()
        currentAdvertiseMode = advertiseMode

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(advertiseMode)
            .setConnectable(true)
            .setTimeout(0)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .build()

        val payload = PayloadCodec.encodeAdvert(myTeaser, senderId)

        val advertiseData = AdvertiseData.Builder()
            .addServiceUuid(ParcelUuid(GATTProfile.SERVICE_UUID))
            .setIncludeDeviceName(false)
            .build()

        val scanResponse = AdvertiseData.Builder()
            .addManufacturerData(GATTProfile.MANUFACTURER_ID, payload)
            .setIncludeDeviceName(false)
            .build()

        advertiser.startAdvertising(settings, advertiseData, scanResponse, advertiseCallback)
        log(
            "ADV",
            "startAdvertising requested mode=${advertiseModeName(advertiseMode)} teaser=${PayloadCodec.normalizeTeaser(myTeaser)} bytes=${payload.size}"
        )
    }

    private fun scheduleAdvertiseDowngrade() {
        cancelAdvertiseDowngrade()
        val runnable = Runnable {
            advertiseDowngradeRunnable = null
            if (!isAdvertising || currentAdvertiseMode != AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY) {
                return@Runnable
            }

            advertiser?.stopAdvertising(advertiseCallback)
            isAdvertising = false
            currentAdvertiseMode = null
            log("ADV", "initial 15s boost complete; switching to BALANCED")
            startAdvertisingWithMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
        }
        advertiseDowngradeRunnable = runnable
        mainHandler.postDelayed(runnable, INITIAL_HIGH_PERFORMANCE_MS)
    }

    private fun cancelAdvertiseDowngrade() {
        advertiseDowngradeRunnable?.let { mainHandler.removeCallbacks(it) }
        advertiseDowngradeRunnable = null
    }

    private fun advertiseModeName(advertiseMode: Int?): String = when (advertiseMode) {
        AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY -> "LOW_LATENCY"
        AdvertiseSettings.ADVERTISE_MODE_BALANCED -> "BALANCED"
        AdvertiseSettings.ADVERTISE_MODE_LOW_POWER -> "LOW_POWER"
        else -> "UNKNOWN"
    }

    private fun sendBodyPreviewThenRest(device: BluetoothDevice) {
        pendingNotifyPackets.clear()
        isNotifying = false

        val bytes = myBody.toByteArray(Charsets.UTF_8)
        val preview = if (bytes.size > GATTProfile.PREVIEW_BYTES) bytes.copyOfRange(0, GATTProfile.PREVIEW_BYTES) else bytes
        val rest = if (bytes.size > GATTProfile.PREVIEW_BYTES) bytes.copyOfRange(GATTProfile.PREVIEW_BYTES, bytes.size) else ByteArray(0)

        val chunkPayloadSize = 17
        var seq = 0

        fun enqueueChunks(data: ByteArray) {
            var offset = 0
            while (offset < data.size) {
                val end = Math.min(data.size, offset + chunkPayloadSize)
                val slice = data.copyOfRange(offset, end)
                offset = end

                val packet = ByteArray(3 + slice.size)
                packet[0] = (seq and 0xFF).toByte()
                packet[1] = ((seq shr 8) and 0xFF).toByte()
                packet[2] = 0

                System.arraycopy(slice, 0, packet, 3, slice.size)
                pendingNotifyPackets.add(packet)
                seq++
            }
        }

        enqueueChunks(preview)
        enqueueChunks(rest)

        if (pendingNotifyPackets.isEmpty()) {
            pendingNotifyPackets.add(byteArrayOf(0x00, 0x00, 0x01))
        }

        val lastIndex = pendingNotifyPackets.size - 1
        val lastPacket = pendingNotifyPackets[lastIndex]
        lastPacket[2] = 0x01
        pendingNotifyPackets[lastIndex] = lastPacket

        log("GATT", "enqueue notify packets=${pendingNotifyPackets.size} bodyBytes=${bytes.size}")
        flushNotifyQueue(device)
    }

    private fun flushNotifyQueue(device: BluetoothDevice) {
        if (isNotifying || pendingNotifyPackets.isEmpty()) return

        isNotifying = true
        val packet = pendingNotifyPackets.removeAt(0)

        val service = gattServer?.getService(GATTProfile.SERVICE_UUID)
        val char = service?.getCharacteristic(GATTProfile.CHUNK_CHAR_UUID)

        if (char != null) {
            char.value = packet
            val success = gattServer?.notifyCharacteristicChanged(device, char, false) ?: false
            if (!success) {
                log("GATT", "notifyCharacteristicChanged failed, buffer might be full")
                pendingNotifyPackets.add(0, packet)
                isNotifying = false
                mainHandler.postDelayed({ flushNotifyQueue(device) }, 50)
            }
        } else {
            isNotifying = false
        }
    }
}
