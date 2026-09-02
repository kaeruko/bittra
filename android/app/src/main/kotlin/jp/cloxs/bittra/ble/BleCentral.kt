package jp.cloxs.bitra.ble

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import java.util.UUID

enum class RequestStatus(val rawValue: String) {
    IDLE("idle"),
    CONNECTING("connecting"),
    DISCOVERING("discovering"),
    SUBSCRIBING("subscribing"),
    REQUESTING("requesting"),
    RECEIVING_PREVIEW("receivingPreview"),
    COMPLETED("completed"),
    TIMEOUT("timeout"),
    FAILED("failed")
}

@SuppressLint("MissingPermission")
class BleCentral(private val context: Context, private val log: (String, String) -> Unit) {

    private val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val adapter: BluetoothAdapter? = bluetoothManager.adapter
    private val scanner = adapter?.bluetoothLeScanner

    var onEncounter: ((BluetoothDevice, Long, String, Int) -> Unit)? = null
    var onStatus: ((RequestStatus, String?) -> Unit)? = null
    var onPreview: ((String) -> Unit)? = null
    var onBody: ((String) -> Unit)? = null

    private var currentGatt: BluetoothGatt? = null
    private var reqChar: BluetoothGattCharacteristic? = null
    private var chunkChar: BluetoothGattCharacteristic? = null
    private var ackChar: BluetoothGattCharacteristic? = null

    private val assembler = ChunkAssembler()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var timeoutRunnable: Runnable? = null
    private var ackTimeoutRunnable: Runnable? = null
    private var pendingCompletedBody: String? = null
    private var retryLeft = 1
    private var targetDevice: BluetoothDevice? = null
    private var isScanning = false
    private var resumeScanAfterRequest = false

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val record = result.scanRecord ?: return

            val mfgData = record.getManufacturerSpecificData(GATTProfile.MANUFACTURER_ID)
            val srvData = record.serviceData[ParcelUuid(GATTProfile.SERVICE_UUID)]

            android.util.Log.d("BleCentral", "ScanResult for ${result.device.address}: name=${record.deviceName}, mfgData=${mfgData?.size}, srvData=${srvData?.size}, srvUuids=${record.serviceUuids}")

            val decoded = if (mfgData != null && mfgData.isNotEmpty()) {
                PayloadCodec.decodeAdvert(mfgData)
            } else if (srvData != null && srvData.isNotEmpty()) {
                PayloadCodec.decodeAdvert(srvData)
            } else {
                val localName = record.deviceName
                if (localName != null) {
                    val compactResult = PayloadCodec.decodeLocalName(localName)
                    if (compactResult != null) {
                        compactResult
                    } else {
                        var legacyResult: PayloadCodec.AdvertResult? = null
                        var tempName: String = localName
                        for (i in 0 until 4) {
                            if (tempName.isEmpty()) break
                            try {
                                val padded = tempName.padEnd(tempName.length + (4 - tempName.length % 4) % 4, '=')
                                val decodedData = android.util.Base64.decode(padded, android.util.Base64.DEFAULT)
                                legacyResult = PayloadCodec.decodeAdvert(decodedData)
                                if (legacyResult != null) break
                            } catch (_: IllegalArgumentException) {
                            }
                            tempName = tempName.dropLast(1)
                        }
                        legacyResult
                    }
                } else {
                    null
                }
            }

            if (decoded == null || decoded.teaser.isEmpty()) return
            onEncounter?.invoke(result.device, decoded.senderId, decoded.teaser, result.rssi)
        }

        override fun onScanFailed(errorCode: Int) {
            isScanning = false
            log("SCAN", "startScan failed: $errorCode")
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (gatt !== currentGatt) {
                gatt.close()
                return
            }

            if (newState == BluetoothProfile.STATE_CONNECTED) {
                log("CENTRAL", "didConnect")
                mainHandler.postDelayed({
                    if (gatt !== currentGatt) return@postDelayed
                    onStatus?.invoke(RequestStatus.DISCOVERING, null)
                    if (!gatt.discoverServices()) {
                        failOrRetry("discover_services_not_started")
                    }
                }, 300)
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                log("CENTRAL", "didDisconnect status=$status")
                if (status != BluetoothGatt.GATT_SUCCESS && currentGatt === gatt) {
                    mainHandler.post { failOrRetry("connect_failed_status_$status") }
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (gatt !== currentGatt) return
            if (status != BluetoothGatt.GATT_SUCCESS) {
                log("CENTRAL", "discoverServices error $status")
                mainHandler.post { failOrRetry("discover_services_$status") }
                return
            }

            val service = gatt.getService(GATTProfile.SERVICE_UUID)
            if (service == null) {
                mainHandler.post { failOrRetry("no_service") }
                return
            }

            reqChar = service.getCharacteristic(GATTProfile.REQ_CHAR_UUID)
            chunkChar = service.getCharacteristic(GATTProfile.CHUNK_CHAR_UUID)
            ackChar = service.getCharacteristic(GATTProfile.ACK_CHAR_UUID)

            if (reqChar == null || chunkChar == null) {
                mainHandler.post { failOrRetry("missing_char") }
                return
            }

            if (ackChar == null) {
                log("CENTRAL", "sender does not support delivery ACK")
            }

            mainHandler.post {
                onStatus?.invoke(RequestStatus.SUBSCRIBING, null)
                gatt.setCharacteristicNotification(chunkChar, true)

                val descriptor = chunkChar?.getDescriptor(UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"))
                if (descriptor != null) {
                    descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    gatt.writeDescriptor(descriptor)
                } else {
                    sendRequest()
                }
            }
        }

        override fun onDescriptorWrite(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            if (gatt !== currentGatt) return
            if (status == BluetoothGatt.GATT_SUCCESS) {
                mainHandler.post { sendRequest() }
            } else {
                mainHandler.post { failOrRetry("descriptor_write_fail_$status") }
            }
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int
        ) {
            if (gatt !== currentGatt || characteristic.uuid != GATTProfile.ACK_CHAR_UUID) return
            mainHandler.post {
                stopAckTimeout()
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    log("CENTRAL", "delivery ACK confirmed")
                } else {
                    log("CENTRAL", "delivery ACK failed status=$status")
                }
                completePendingBody()
            }
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray
        ) {
            handleCharacteristicChanged(characteristic, value)
        }

        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic
        ) {
            handleCharacteristicChanged(characteristic, characteristic.value ?: return)
        }
    }

    private fun handleCharacteristicChanged(characteristic: BluetoothGattCharacteristic, value: ByteArray) {
        if (characteristic.uuid != GATTProfile.CHUNK_CHAR_UUID || value.size < 3) return

        val seq = (value[0].toInt() and 0xFF) or ((value[1].toInt() and 0xFF) shl 8)
        val flags = value[2].toInt() and 0xFF
        val payload = value.copyOfRange(3, value.size)

        val (previewReady, completed, fullData) = assembler.addChunk(seq, flags, payload)

        mainHandler.post {
            if (previewReady) {
                onStatus?.invoke(RequestStatus.RECEIVING_PREVIEW, null)
            }

            if (completed && fullData != null) {
                stopTimeout()
                val body = String(fullData, Charsets.UTF_8)
                pendingCompletedBody = body
                sendDeliveryAckOrComplete()
            }
        }
    }

    private fun sendDeliveryAckOrComplete() {
        val characteristic = ackChar
        if (characteristic == null) {
            completePendingBody()
            return
        }

        characteristic.value = byteArrayOf(0x02)
        characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        if (currentGatt?.writeCharacteristic(characteristic) == true) {
            log("CENTRAL", "delivery ACK sent")
            startAckTimeout(2000)
        } else {
            log("CENTRAL", "delivery ACK write not started")
            completePendingBody()
        }
    }

    private fun completePendingBody() {
        stopAckTimeout()
        val body = pendingCompletedBody ?: return
        pendingCompletedBody = null
        val preview = if (body.length > 40) body.substring(0, 40) else body
        onBody?.invoke(body)
        onPreview?.invoke(preview)
        onStatus?.invoke(RequestStatus.COMPLETED, null)
        closeCurrentGatt()
        finishRequest()
    }

    private fun sendRequest() {
        onStatus?.invoke(RequestStatus.REQUESTING, null)
        val req = byteArrayOf(0x01)
        reqChar?.let {
            it.value = req
            it.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            if (currentGatt?.writeCharacteristic(it) == true) {
                log("CENTRAL", "REQ sent")
            } else {
                failOrRetry("request_write_not_started")
            }
        } ?: failOrRetry("no_req_char")
    }

    fun startScan() {
        if (adapter == null || !adapter.isEnabled || scanner == null) {
            log("CENTRAL", "Bluetooth not poweredOn yet")
            return
        }

        if (isScanning) {
            log("SCAN", "already scanning")
            return
        }

        val filters = listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(GATTProfile.SERVICE_UUID)).build())
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        scanner.startScan(filters, settings, scanCallback)
        isScanning = true
        log("SCAN", "startScan")
    }

    fun stopScan() {
        if (isScanning) {
            scanner?.stopScan(scanCallback)
            isScanning = false
        }
        log("SCAN", "stopScan")
    }

    fun requestBody(device: BluetoothDevice) {
        log("CENTRAL", "requestBody called for peerId=${device.address}")
        retryLeft = 1
        targetDevice = device
        resumeScanAfterRequest = isScanning
        if (isScanning) stopScan()
        connect(device)
    }

    private fun connect(device: BluetoothDevice) {
        resetRequestState()
        onStatus?.invoke(RequestStatus.CONNECTING, null)
        currentGatt = device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        startTimeout(10000)
        log("CENTRAL", "connect start ${device.address}")
    }

    private fun resetRequestState() {
        stopTimeout()
        stopAckTimeout()
        assembler.reset()
        pendingCompletedBody = null
        reqChar = null
        chunkChar = null
        ackChar = null
        closeCurrentGatt()
    }

    private fun closeCurrentGatt() {
        val oldGatt = currentGatt
        currentGatt = null
        oldGatt?.disconnect()
        oldGatt?.close()
    }

    private fun finishRequest() {
        targetDevice = null
        if (resumeScanAfterRequest) {
            resumeScanAfterRequest = false
            startScan()
        }
    }

    private fun startTimeout(ms: Long) {
        stopTimeout()
        val r = Runnable {
            log("CENTRAL", "timeout")
            onStatus?.invoke(RequestStatus.TIMEOUT, null)
            failOrRetry("timeout")
        }
        mainHandler.postDelayed(r, ms)
        timeoutRunnable = r
    }

    private fun stopTimeout() {
        timeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        timeoutRunnable = null
    }

    private fun startAckTimeout(ms: Long) {
        stopAckTimeout()
        val r = Runnable {
            log("CENTRAL", "delivery ACK timeout")
            completePendingBody()
        }
        mainHandler.postDelayed(r, ms)
        ackTimeoutRunnable = r
    }

    private fun stopAckTimeout() {
        ackTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        ackTimeoutRunnable = null
    }

    private fun failOrRetry(reason: String) {
        stopTimeout()
        stopAckTimeout()
        if (retryLeft > 0 && targetDevice != null) {
            retryLeft -= 1
            log("CENTRAL", "retry $retryLeft reason=$reason")
            val p = targetDevice!!
            closeCurrentGatt()
            mainHandler.postDelayed({ connect(p) }, 200)
        } else {
            onStatus?.invoke(RequestStatus.FAILED, reason)
            closeCurrentGatt()
            finishRequest()
        }
    }
}
