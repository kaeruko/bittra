package jp.cloxs.bitra.ble

import android.bluetooth.BluetoothDevice
import android.content.Context
import android.os.Handler
import android.os.Looper

class BleCoordinator(private val context: Context) {

    // Event callbacks to Flutter
    var onEncounterEvent: ((Map<String, Any>) -> Unit)? = null
    var onStatusEvent: ((Map<String, Any>) -> Unit)? = null
    var onBodyEvent: ((Map<String, Any>) -> Unit)? = null
    var onLogEvent: ((Map<String, Any>) -> Unit)? = null

    private var myTeaser: String = ""
    private var myBody: String = ""

    private val peripheral by lazy { BlePeripheral(context, this::addLog) }
    private val central by lazy { BleCentral(context, this::addLog) }

    // Use MAC address as peerId for Android
    private val peripheralCache = mutableMapOf<String, BluetoothDevice>()

    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        central.onEncounter = { device, senderId, teaser, rssi ->
            if (teaser.isNotEmpty()) {
                mainHandler.post {
                    peripheralCache[device.address] = device
                    onEncounterEvent?.invoke(
                        mapOf(
                            "type" to "encounter",
                            "peerId" to device.address,
                            "senderId" to senderId,
                            "teaser" to teaser,
                            "rssi" to rssi
                        )
                    )
                }
            }
        }
    }

    fun setMyTeaser(teaser: String) {
        myTeaser = PayloadCodec.normalizeTeaser(teaser)
        peripheral.setContent(myTeaser, myBody)
        addLog("APP", "set teaser=$myTeaser")
    }

    fun setMyBody(body: String) {
        myBody = body
        peripheral.setContent(myTeaser, myBody)
        addLog("APP", "set body bytes=${body.toByteArray(Charsets.UTF_8).size}")
    }

    fun startVenueMode() {
        if (myTeaser.isEmpty()) {
            startReceiveOnly()
            return
        }
        peripheral.setContent(myTeaser, myBody)
        peripheral.start()
        central.startScan()
        addLog("APP", "venue ON")
    }

    fun startReceiveOnly() {
        peripheral.stop()
        central.startScan()
        addLog("APP", "receive-only ON")
    }

    fun stopVenueMode() {
        central.stopScan()
        peripheral.stop()
        addLog("APP", "venue OFF")
    }

    fun requestBody(peerId: String) {
        val p = peripheralCache[peerId]
        if (p == null) {
            addLog("APP", "no cached peripheral (wait a bit and try again)")
            onStatusEvent?.invoke(
                mapOf(
                    "type" to "status",
                    "peerId" to peerId,
                    "status" to RequestStatus.FAILED.rawValue,
                    "error" to "Peripheral not cached yet."
                )
            )
            return
        }

        addLog("APP", "requestBody peerId=${p.address}")

        val handler = Handler(Looper.getMainLooper())

        central.onStatus = { st, err ->
            handler.post {
                onStatusEvent?.invoke(
                    mapOf(
                        "type" to "status",
                        "peerId" to peerId,
                        "status" to st.rawValue,
                        "error" to (err ?: "")
                    )
                )
            }
        }

        central.onPreview = { preview ->
            // In Flutter MVP, preview is optional to display progressively
            handler.post {
                onBodyEvent?.invoke(
                    mapOf(
                        "type" to "body",
                        "peerId" to peerId,
                        "preview" to preview
                    )
                )
            }
        }

        central.onBody = { body ->
            handler.post {
                onBodyEvent?.invoke(
                    mapOf(
                        "type" to "body",
                        "peerId" to peerId,
                        "preview" to if (body.length > 80) body.substring(0, 80) else body,
                        "body" to body
                    )
                )
            }
        }

        central.requestBody(p)
    }

    private fun addLog(tag: String, msg: String) {
        android.util.Log.d("BittraBLE", "[$tag] $msg")
        Handler(Looper.getMainLooper()).post {
            onLogEvent?.invoke(
                mapOf(
                    "type" to "log",
                    "tag" to tag,
                    "message" to msg
                )
            )
        }
    }
}
