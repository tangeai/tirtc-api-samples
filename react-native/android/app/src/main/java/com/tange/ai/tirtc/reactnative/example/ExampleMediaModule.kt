package com.tange.ai.tirtc.reactnative.example

import android.content.ContentValues
import android.os.Build
import android.provider.MediaStore
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import java.io.File
import java.io.FileInputStream

class ExampleMediaModule(
  reactContext: ReactApplicationContext,
) : ReactContextBaseJavaModule(reactContext) {
  override fun getName(): String = "TiRtcExampleMedia"

  @ReactMethod
  fun cacheFilePath(extension: String, promise: Promise) {
    val safeExtension = extension.lowercase().filter { it.isLetterOrDigit() }.ifEmpty { "bin" }
    promise.resolve(File(reactApplicationContext.cacheDir, "tirtc-${System.currentTimeMillis()}.$safeExtension").absolutePath)
  }

  @ReactMethod
  fun saveImageToGallery(sourcePath: String, promise: Promise) {
    val source = File(sourcePath)
    if (!source.isFile) {
      promise.reject("snapshot_missing", "Snapshot file does not exist")
      return
    }
    val values = ContentValues().apply {
      put(MediaStore.Images.Media.DISPLAY_NAME, "TiRTC-${System.currentTimeMillis()}.jpg")
      put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/TiRTC")
        put(MediaStore.Images.Media.IS_PENDING, 1)
      }
    }
    val resolver = reactApplicationContext.contentResolver
    val target = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
    if (target == null) {
      promise.reject("gallery_insert_failed", "Unable to create gallery item")
      return
    }
    try {
      resolver.openOutputStream(target)?.use { output ->
        FileInputStream(source).use { input -> input.copyTo(output) }
      } ?: error("Unable to open gallery item")
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        values.clear()
        values.put(MediaStore.Images.Media.IS_PENDING, 0)
        resolver.update(target, values, null, null)
      }
      promise.resolve(target.toString())
    } catch (error: Throwable) {
      resolver.delete(target, null, null)
      promise.reject("gallery_write_failed", error)
    }
  }
}
