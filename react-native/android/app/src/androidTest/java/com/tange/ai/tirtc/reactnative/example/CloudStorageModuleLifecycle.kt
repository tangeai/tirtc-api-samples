package com.tange.ai.tirtc.reactnative.example

import android.content.Context
import androidx.test.platform.app.InstrumentationRegistry
import com.facebook.react.ReactApplication
import com.tange.ai.tirtc.TiCloudStorage
import com.tange.ai.tirtc.TiCloudStorageCallbackThread
import com.tange.ai.tirtc.TiCloudStorageErrorCode
import com.tange.ai.tirtc.TiCloudStorageVideoOutput
import com.tange.ai.tirtc.TiCloudStorageReplayErrorListener
import com.tange.ai.tirtc.reactnative.TiRtcModule
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue

/** Checks module teardown against actual SDK resources while a Native observer is active. */
internal object CloudStorageModuleLifecycle {
  fun verify(context: Context) {
    val application = context.applicationContext as ReactApplication
    val reactContext = requireNotNull(application.reactHost?.currentReactContext)
    val module = requireNotNull(reactContext.getNativeModule(TiRtcModule::class.java))
    assertEquals(0, TiCloudStorage.init(context, "app", "https://example.invalid", false))
    val cloud = TiCloudStorage("token")
    val replay = cloud.createReplay(TiCloudStorageCallbackThread.BACKGROUND)
    val output = TiCloudStorageVideoOutput()
    val entered = CountDownLatch(1)
    val release = CountDownLatch(1)
    val exited = CountDownLatch(1)
    // Register real public SDK objects after the JS case has released its objects.
    // This isolates module cleanup from the separately tested acknowledgement route.
    val registryField = TiRtcModule::class.java.getDeclaredField("registry").apply { isAccessible = true }
    val registry = registryField.get(module)
    val add = registry.javaClass.getMethod("add", Any::class.java)
    listOf(cloud, replay, output).forEach { add.invoke(registry, it) }
    replay.onError = TiCloudStorageReplayErrorListener {
      entered.countDown()
      release.await(5, TimeUnit.SECONDS)
      exited.countDown()
    }
    try {
      assertEquals(0, output.attach(replay, 0))
      assertEquals(0, replay.play(1, 2))
      assertTrue("Native error observer did not enter", entered.await(5, TimeUnit.SECONDS))
      assertEquals(TiCloudStorageErrorCode.IN_USE, replay.stop())
      module.invalidate()
      // The first cleanup attempt must run while the callback is still entered.
      InstrumentationRegistry.getInstrumentation().runOnMainSync {}
      assertEquals(TiCloudStorageErrorCode.IN_USE, replay.stop())
      release.countDown()
      assertTrue(exited.await(2, TimeUnit.SECONDS))
      val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
      var released = false
      while (System.nanoTime() < deadline) {
        if (replay.seek(1) == TiCloudStorageErrorCode.NOT_INITIALIZED &&
            cloud.updateToken("token") == TiCloudStorageErrorCode.NOT_INITIALIZED) {
          released = true
          break
        }
        Thread.sleep(10)
      }
      assertTrue("module dropped owners before Native destruction succeeded", released)
      assertEquals(TiCloudStorageErrorCode.NOT_INITIALIZED, output.attach(replay, 0))
      module.invalidate()
    } finally {
      release.countDown()
      exited.await(2, TimeUnit.SECONDS)
      replay.stop()
      output.detach()
      output.detachView()
      output.dispose()
      replay.dispose()
      cloud.dispose()
      TiCloudStorage.shutdown()
    }
  }
}
