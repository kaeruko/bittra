package jp.cloxs.bittra

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import jp.cloxs.bittra.ble.BleCoordinator
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "bittra/ble"
    private val EVENT_CHANNEL = "bittra/ble_events"

    private var bleCoordinator: BleCoordinator? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        bleCoordinator = BleCoordinator(this)

        checkAndRequestPermissions()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            val ble = bleCoordinator
            if (ble == null) {
                result.error("UNAVAILABLE", "BLE Coordinator not initialized", null)
                return@setMethodCallHandler
            }

            when (call.method) {
                "startVenueMode" -> {
                    ble.startVenueMode()
                    result.success(null)
                }
                "stopVenueMode" -> {
                    ble.stopVenueMode()
                    result.success(null)
                }
                "setTeaser" -> {
                    val teaser = call.argument<String>("teaser")
                    if (teaser != null) {
                        ble.setMyTeaser(teaser)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENTS", "teaser is required", null)
                    }
                }
                "setBody" -> {
                    val body = call.argument<String>("body")
                    if (body != null) {
                        ble.setMyBody(body)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENTS", "body is required", null)
                    }
                }
                "requestBody" -> {
                    val peerId = call.argument<String>("peerId")
                    if (peerId != null) {
                        ble.requestBody(peerId)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENTS", "peerId is required", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    wireUpEvents()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    private fun wireUpEvents() {
        bleCoordinator?.onEncounterEvent = { eventMap ->
            eventSink?.success(eventMap)
        }
        bleCoordinator?.onStatusEvent = { eventMap ->
            eventSink?.success(eventMap)
        }
        bleCoordinator?.onBodyEvent = { eventMap ->
            eventSink?.success(eventMap)
        }
        bleCoordinator?.onLogEvent = { eventMap ->
            eventSink?.success(eventMap)
        }
    }

    private fun checkAndRequestPermissions() {
        val permissions = mutableListOf<String>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissions.add(Manifest.permission.BLUETOOTH_SCAN)
            permissions.add(Manifest.permission.BLUETOOTH_ADVERTISE)
            permissions.add(Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            permissions.add(Manifest.permission.ACCESS_FINE_LOCATION)
            permissions.add(Manifest.permission.ACCESS_COARSE_LOCATION)
            permissions.add(Manifest.permission.BLUETOOTH)
            permissions.add(Manifest.permission.BLUETOOTH_ADMIN)
        }

        val notGranted = permissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }

        if (notGranted.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, notGranted.toTypedArray(), 100)
        }
    }
}
