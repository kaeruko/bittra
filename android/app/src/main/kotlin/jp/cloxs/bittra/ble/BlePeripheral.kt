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
import android.util.Log
import java.security.SecureRandom
import java.util.UUID

@SuppressLint("MissingPermission")
class BlePeripheral(private val context: Context, private val log: (String, String) -> Unit) {

    private val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val adapter: BluetoothAdapter? = bluetoothManager.adapter
    private val advertiser = adapter?.bluetoothLeAdvertiser

    private var gattServer: BluetoothGattServer? = null
    private var isAdvertising = false
    private var isGattServiceReady = false
    private var startAdvertisingWhenReady = false

    private var myTeaser: String = ""
    private var myBody: String = ""

    private val pendingNotifyPackets = mutableListOf<ByteArray>()
    private var isNotifying = false
    private var subscribedDevice: BluetoothDevice? = null

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
            log("ADV", "startAdvertising success")
            isAdvertising = true
        }

        override fun onStartFailure(errorCode: Int) {
            log("ADV", "startAdvertising fail: $errorCode")
            isAdvertising = false
        }
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onServiceAdded(status: Int, service: BluetoothGattService) {
            if (service.uuid != GATTProfile.SERVICE_UUID) return
            isGattServiceReady = status == BluetoothGatt.GATT_SUCCESS
            log("PERIPH", "GATT service ready status=$status")
            if (isGattServiceReady && startAdvertisingWhenReady) {
                startAdvertisingWhenReady = false
                startAdvertising()
            }
        }

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            log("PERIPH", "connectionStateChange ${device.address} status=$status newState=$newState")
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
            if (characteristic.uuid == GATTProfile.REQ_CHAR_UUID) {
                log("GATT", "REQ received from central")
                
                // Write without response
                if (responseNeeded) {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
                }
                
                sendBodyPreviewThenRest(device)
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

    fun setContent(teaser: String, body: String) {
        this.myTeaser = teaser
        this.myBody = body
    }

    fun start() {
        if (PayloadCodec.normalizeTeaser(myTeaser).isEmpty()) {
            stop()
            log("PERIPH", "skip empty teaser advertisement")
            return
        }
        if (adapter == null || !adapter.isEnabled) {
            log("PERIPH", "Bluetooth not poweredOn yet")
            return
        }

        // Stop existing advertisement before restarting with new content
        if (isAdvertising) {
            advertiser?.stopAdvertising(advertiseCallback)
            isAdvertising = false
        }

        setupGATTIfNeeded()
        if (isGattServiceReady) {
            startAdvertising()
        } else {
            startAdvertisingWhenReady = true
        }
    }

    fun stop() {
        startAdvertisingWhenReady = false
        if (isAdvertising) {
            advertiser?.stopAdvertising(advertiseCallback)
            isAdvertising = false
            log("PERIPH", "stopAdvertising")
        }
        pendingNotifyPackets.clear()
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

        val cccDescriptor = BluetoothGattDescriptor(
            UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"),
            BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
        )
        chunkChar.addDescriptor(cccDescriptor)

        service.addCharacteristic(reqChar)
        service.addCharacteristic(chunkChar)

        gattServer?.addService(service)
        log("PERIPH", "GATT service added")
    }

    private fun startAdvertising() {
        if (advertiser == null) return

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTimeout(0)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .build()

        val payload = PayloadCodec.encodeAdvert(myTeaser, senderId)

        // Main packet: service UUID only (for iOS scan filter)
        val advertiseData = AdvertiseData.Builder()
            .addServiceUuid(ParcelUuid(GATTProfile.SERVICE_UUID))
            .setIncludeDeviceName(false)
            .build()

        // Scan response: teaser payload in manufacturer data (4 bytes overhead vs 18 for service data)
        val scanResponse = AdvertiseData.Builder()
            .addManufacturerData(GATTProfile.MANUFACTURER_ID, payload)
            .setIncludeDeviceName(false)
            .build()

        advertiser.startAdvertising(settings, advertiseData, scanResponse, advertiseCallback)
        log("ADV", "startAdvertising teaser=${PayloadCodec.normalizeTeaser(myTeaser)} bytes=${payload.size}")
    }

    private fun sendBodyPreviewThenRest(device: BluetoothDevice) {
        pendingNotifyPackets.clear()
        isNotifying = false

        val bytes = myBody.toByteArray(Charsets.UTF_8)
        val preview = if (bytes.size > GATTProfile.PREVIEW_BYTES) bytes.copyOfRange(0, GATTProfile.PREVIEW_BYTES) else bytes
        val rest = if (bytes.size > GATTProfile.PREVIEW_BYTES) bytes.copyOfRange(GATTProfile.PREVIEW_BYTES, bytes.size) else ByteArray(0)

        // MTU usually 23 bytes minimum, meaning 20 bytes payload. We use slightly larger if MTU is negotiated, but stick to 20 for safety on Android.
        // The packet header also consumes 3 bytes. Keep the complete ATT value
        // within the 20-byte minimum notification payload.
        val chunkPayloadSize = 17
        var seq = 0

        fun enqueueChunks(data: ByteArray, isLastBlockPotentially: Boolean) {
            var offset = 0
            while (offset < data.size) {
                val end = Math.min(data.size, offset + chunkPayloadSize)
                val slice = data.copyOfRange(offset, end)
                offset = end

                val packet = ByteArray(3 + slice.size)
                packet[0] = (seq and 0xFF).toByte()
                packet[1] = ((seq shr 8) and 0xFF).toByte()
                packet[2] = 0 // flags

                System.arraycopy(slice, 0, packet, 3, slice.size)
                pendingNotifyPackets.add(packet)
                seq++
            }
        }

        enqueueChunks(preview, rest.isEmpty())
        enqueueChunks(rest, true)

        // Even an empty body needs a terminal packet, otherwise the receiver
        // can never know that the transfer completed.
        if (pendingNotifyPackets.isEmpty()) {
            pendingNotifyPackets.add(byteArrayOf(0x00, 0x00, 0x01))
        }

        if (pendingNotifyPackets.isNotEmpty()) {
            val lastIndex = pendingNotifyPackets.size - 1
            val lastPacket = pendingNotifyPackets[lastIndex]
            lastPacket[2] = 0x01
            pendingNotifyPackets[lastIndex] = lastPacket
        }

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
                // On Android, if it returns false we should ideally retry after a short delay
                pendingNotifyPackets.add(0, packet) // put it back
                isNotifying = false
                mainHandler.postDelayed({ flushNotifyQueue(device) }, 50)
            }
        } else {
            isNotifying = false
        }
    }
}
