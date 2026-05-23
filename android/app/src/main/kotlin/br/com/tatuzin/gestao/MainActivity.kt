package br.com.tatuzin.gestao

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingBluetoothResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PRINTER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listBluetoothPrinters" -> listBluetoothPrinters(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun listBluetoothPrinters(result: MethodChannel.Result) {
        val adapter = bluetoothAdapter()
        if (adapter == null) {
            result.success(printerResponse("unsupported"))
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingBluetoothResult != null) {
                result.success(printerResponse("failed"))
                return
            }
            pendingBluetoothResult = result
            requestPermissions(
                arrayOf(Manifest.permission.BLUETOOTH_CONNECT),
                REQUEST_BLUETOOTH_CONNECT,
            )
            return
        }

        respondWithBondedPrinters(adapter, result)
    }

    private fun respondWithBondedPrinters(
        adapter: BluetoothAdapter,
        result: MethodChannel.Result,
    ) {
        if (!adapter.isEnabled) {
            result.success(printerResponse("bluetoothOff"))
            return
        }

        try {
            val devices = adapter.bondedDevices
                .map { device ->
                    mapOf(
                        "name" to (device.name ?: "Impressora Bluetooth"),
                        "address" to device.address,
                    )
                }
                .sortedBy { it["name"] }
            result.success(printerResponse("available", devices))
        } catch (_: SecurityException) {
            result.success(printerResponse("permissionDenied"))
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_BLUETOOTH_CONNECT) {
            return
        }

        val result = pendingBluetoothResult ?: return
        pendingBluetoothResult = null
        val granted = grantResults.isNotEmpty() &&
            grantResults.first() == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            result.success(printerResponse("permissionDenied"))
            return
        }

        val adapter = bluetoothAdapter()
        if (adapter == null) {
            result.success(printerResponse("unsupported"))
            return
        }
        respondWithBondedPrinters(adapter, result)
    }

    private fun bluetoothAdapter(): BluetoothAdapter? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
            val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            manager?.adapter
        } else {
            @Suppress("DEPRECATION")
            BluetoothAdapter.getDefaultAdapter()
        }
    }

    private fun printerResponse(
        status: String,
        devices: List<Map<String, String>> = emptyList(),
    ): Map<String, Any> {
        return mapOf("status" to status, "devices" to devices)
    }

    private companion object {
        const val PRINTER_CHANNEL = "tatuzin/printers"
        const val REQUEST_BLUETOOTH_CONNECT = 4001
    }
}
