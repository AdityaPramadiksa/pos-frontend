package com.example.pos_babi_guling

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Membuka halaman Bluetooth Android untuk pairing printer baru dari aplikasi
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pos_babi_guling/settings")
            .setMethodCallHandler { call, result ->
                if (call.method == "openBluetoothSettings") {
                    try {
                        startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
