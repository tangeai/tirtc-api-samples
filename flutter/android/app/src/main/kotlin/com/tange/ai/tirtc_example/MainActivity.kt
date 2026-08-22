package com.tange.ai.tirtc_example

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val preferences = getSharedPreferences(PREFERENCES_FILE_NAME, Context.MODE_PRIVATE)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PREFERENCES_CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "putPreferencesInt" -> putPreferencesInt(call, result, preferences)
                "getPreferencesInt" -> getPreferencesInt(call, result, preferences)
                "putPreferencesString" -> putPreferencesString(call, result, preferences)
                "getPreferencesString" -> getPreferencesString(call, result, preferences)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PERMISSIONS_CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkMicrophonePermission" -> result.success(permissionGranted(Manifest.permission.RECORD_AUDIO))
                "requestMicrophonePermission" -> requestPermission(Manifest.permission.RECORD_AUDIO, result)
                "requestGalleryWritePermission" -> {
                    if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P) {
                        requestPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE, result)
                    } else {
                        result.success(true)
                    }
                }
                "requestLocalNetworkPermission" -> result.success(true)
                else -> result.notImplemented()
            }
        }
    }

    private fun putPreferencesInt(
        call: MethodCall,
        result: MethodChannel.Result,
        preferences: android.content.SharedPreferences,
    ) {
        val key = call.argument<String>("key")
        val value = call.argument<Int>("value")
        if (key == null || value == null) {
            result.error("INVALID_ARGUMENT", "key and value are required", null)
            return
        }
        preferences.edit().putInt(key, value).apply()
        result.success(null)
    }

    private fun getPreferencesInt(
        call: MethodCall,
        result: MethodChannel.Result,
        preferences: android.content.SharedPreferences,
    ) {
        val key = call.argument<String>("key")
        val defaultValue = call.argument<Int>("defaultValue")
        if (key == null || defaultValue == null) {
            result.error("INVALID_ARGUMENT", "key and defaultValue are required", null)
            return
        }
        result.success(preferences.getInt(key, defaultValue))
    }

    private fun putPreferencesString(
        call: MethodCall,
        result: MethodChannel.Result,
        preferences: android.content.SharedPreferences,
    ) {
        val key = call.argument<String>("key")
        val value = call.argument<String>("value")
        if (key == null || value == null) {
            result.error("INVALID_ARGUMENT", "key and value are required", null)
            return
        }
        preferences.edit().putString(key, value).apply()
        result.success(null)
    }

    private fun getPreferencesString(
        call: MethodCall,
        result: MethodChannel.Result,
        preferences: android.content.SharedPreferences,
    ) {
        val key = call.argument<String>("key")
        val defaultValue = call.argument<String>("defaultValue")
        if (key == null || defaultValue == null) {
            result.error("INVALID_ARGUMENT", "key and defaultValue are required", null)
            return
        }
        result.success(preferences.getString(key, defaultValue) ?: defaultValue)
    }

    private fun requestPermission(permission: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("PERMISSION_REQUEST_IN_PROGRESS", "permission request already in progress", null)
            return
        }

        if (permissionGranted(permission)) {
            result.success(true)
            return
        }

        pendingPermissionResult = result
        requestPermissions(arrayOf(permission), CAPTURE_PERMISSION_REQUEST_CODE)
    }

    private fun permissionGranted(permission: String): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode == CAPTURE_PERMISSION_REQUEST_CODE) {
            val result = pendingPermissionResult
            pendingPermissionResult = null
            result?.success(
                grantResults.isNotEmpty() &&
                    grantResults.all { it == PackageManager.PERMISSION_GRANTED },
            )
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    companion object {
        private const val PREFERENCES_CHANNEL_NAME = "tirtc_example/preferences"
        private const val PERMISSIONS_CHANNEL_NAME = "tirtc_example/permissions"
        private const val PREFERENCES_FILE_NAME = "tirtc_example_preferences"
        private const val CAPTURE_PERMISSION_REQUEST_CODE = 7610
    }
}
