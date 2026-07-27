package com.tange.ai.tirtc_example

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
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
                "requestLocalNetworkPermission" -> result.success(true)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PERFORMANCE_CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialPerformanceLaunchConfig" -> result.success(initialPerformanceLaunchConfig())
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

    private fun initialPerformanceLaunchConfig(): Map<String, Any?>? {
        val extras = intent?.extras ?: return null
        val keys =
            extras.keySet()
                .filter { key -> key.startsWith(PERFORMANCE_EXTRA_PREFIX) }
                .sorted()
        if (keys.isEmpty()) {
            return null
        }
        val config = mutableMapOf<String, Any?>()
        for (key in keys) {
            config[key.removePrefix(PERFORMANCE_EXTRA_PREFIX)] = supportedPerformanceExtraValue(extras, key)
        }
        return config
    }

    private fun supportedPerformanceExtraValue(extras: Bundle, key: String): Any? {
        return when (val value = extras.get(key)) {
            is String -> value
            is Int -> value
            is Boolean -> value
            null -> null
            else -> null
        }
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
        private const val PERFORMANCE_CHANNEL_NAME = "tirtc_example/performance"
        private const val PERFORMANCE_EXTRA_PREFIX = "tirtc_perf_"
        private const val PREFERENCES_FILE_NAME = "tirtc_example_preferences"
        private const val CAPTURE_PERMISSION_REQUEST_CODE = 7610
    }
}
