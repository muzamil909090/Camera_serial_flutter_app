package com.example.camera

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "usb_uvc_native"
    private val eventChannelName = "usb_uvc_events"
    private val permissionAction = "com.example.camera.USB_PERMISSION"

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingPermissionDevice: UsbDevice? = null
    private var lastUsbEvent: String = "No USB events yet."
    private var eventSink: EventChannel.EventSink? = null

    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                    val dev = intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE)
                    lastUsbEvent = "USB device attached: ${dev?.deviceName ?: "unknown"}"
                    Log.i("USB_NATIVE", lastUsbEvent)
                    eventSink?.success(
                        mapOf(
                            "type" to "ATTACHED",
                            "deviceName" to (dev?.deviceName ?: "unknown"),
                            "message" to lastUsbEvent
                        )
                    )
                }
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    val dev = intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE)
                    lastUsbEvent = "USB device detached: ${dev?.deviceName ?: "unknown"}"
                    Log.i("USB_NATIVE", lastUsbEvent)
                    eventSink?.success(
                        mapOf(
                            "type" to "DETACHED",
                            "deviceName" to (dev?.deviceName ?: "unknown"),
                            "message" to lastUsbEvent
                        )
                    )
                }
                permissionAction -> {
                    val device = intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE)
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    val result = pendingPermissionResult
                    pendingPermissionResult = null
                    pendingPermissionDevice = null
                    if (result != null) {
                        if (granted) {
                            result.success(mapOf("ok" to true, "reason" to "PERMISSION_GRANTED"))
                            eventSink?.success(
                                mapOf(
                                    "type" to "PERMISSION_GRANTED",
                                    "deviceName" to (device?.deviceName ?: "unknown"),
                                    "message" to "USB permission granted"
                                )
                            )
                        } else {
                            val name = device?.deviceName ?: "unknown"
                            result.success(mapOf("ok" to false, "reason" to "PERMISSION_DENIED", "device" to name))
                            eventSink?.success(
                                mapOf(
                                    "type" to "PERMISSION_DENIED",
                                    "deviceName" to name,
                                    "message" to "USB permission denied"
                                )
                            )
                        }
                    }
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val filter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            addAction(permissionAction)
        }
        registerReceiver(usbReceiver, filter)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getUsbSummary" -> result.success(getUsbSummary())
                    "getLastUsbEvent" -> result.success(lastUsbEvent)
                    "requestUsbPermission" -> requestUsbPermission(result)
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                    eventSink?.success(mapOf("type" to "READY", "message" to lastUsbEvent))
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(usbReceiver)
        } catch (_: Exception) {
        }
        super.onDestroy()
    }

    private fun getUsbManager(): UsbManager {
        return getSystemService(Context.USB_SERVICE) as UsbManager
    }

    private fun isUvcDevice(device: UsbDevice): Boolean {
        if (device.deviceClass == 14 || device.deviceClass == 239 || device.deviceClass == 255) {
            return true
        }
        val count = device.interfaceCount
        for (i in 0 until count) {
            val iface = device.getInterface(i)
            if (iface.interfaceClass == 14) {
                return true
            }
        }
        return false
    }

    private fun getUsbSummary(): Map<String, Any> {
        val usbManager = getUsbManager()
        val devices = usbManager.deviceList.values
        val list = ArrayList<Map<String, Any>>()
        for (dev in devices) {
            if (!isUvcDevice(dev)) continue
            list.add(
                mapOf(
                    "deviceName" to dev.deviceName,
                    "vendorId" to dev.vendorId,
                    "productId" to dev.productId,
                    "hasPermission" to usbManager.hasPermission(dev)
                )
            )
        }
        return mapOf(
            "count" to list.size,
            "devices" to list
        )
    }

    private fun requestUsbPermission(result: MethodChannel.Result) {
        if (pendingPermissionResult != null) {
            result.success(mapOf("ok" to false, "reason" to "REQUEST_IN_PROGRESS"))
            return
        }
        val usbManager = getUsbManager()
        val devices = usbManager.deviceList.values
        val target = devices.firstOrNull { isUvcDevice(it) }
        if (target == null) {
            result.success(mapOf("ok" to false, "reason" to "NO_UVC_DEVICE"))
            return
        }
        if (usbManager.hasPermission(target)) {
            result.success(mapOf("ok" to true, "reason" to "ALREADY_GRANTED"))
            return
        }

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else {
            0
        }
        val pi = PendingIntent.getBroadcast(this, 0, Intent(permissionAction), flags)
        pendingPermissionResult = result
        pendingPermissionDevice = target
        usbManager.requestPermission(target, pi)
    }
}
