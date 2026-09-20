package com.tange.ai.tirtc.reactnative.example

import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.WritableMap
import java.util.concurrent.Executors
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue

/** Exercises the shipped bridge on Android; JS routing is covered by the SDK case. */
internal object CloudStorageCallbackLifecycle {
  fun verify() {
    val ready = Semaphore(0)
    val returned = Semaphore(0)
    val wakes = AtomicInteger()
    val worker = Executors.newSingleThreadExecutor()
    // Kotlin internal visibility prevents test consumers from importing the bridge.
    val type = Class.forName("com.tange.ai.tirtc.reactnative.TiRtcReactNativeCloudStorageCallbacks")
    val wake: () -> Unit = { wakes.incrementAndGet(); ready.release() }
    val callback = type.constructors.single().newInstance(wake)
    val deliver = type.getMethod("deliver", WritableMap::class.java)
    val take = type.getMethod("take")
    val acknowledge = type.getMethod("acknowledge", Double::class.javaPrimitiveType)
    val close = type.getMethod("close")
    fun enqueue(value: Int) = worker.submit {
      deliver.invoke(callback, Arguments.createMap().apply { putInt("value", value) })
      returned.release()
    }
    fun waitFor(semaphore: Semaphore) = assertTrue(semaphore.tryAcquire(2, TimeUnit.SECONDS))
    fun stillBlocked() = assertFalse(returned.tryAcquire(20, TimeUnit.MILLISECONDS))
    try {
      val firstDelivery = enqueue(1)
      val secondDelivery = enqueue(2)
      waitFor(ready)
      stillBlocked()
      val first = take.invoke(callback) as WritableMap
      val firstId = first.getDouble("deliveryId")
      assertEquals(1, first.getMap("event")!!.getInt("value"))
      assertNull(take.invoke(callback))
      acknowledge.invoke(callback, firstId + 1)
      stillBlocked()
      assertFalse(ready.tryAcquire(20, TimeUnit.MILLISECONDS))
      acknowledge.invoke(callback, firstId)
      waitFor(returned)
      waitFor(ready)
      val second = take.invoke(callback) as WritableMap
      assertEquals(2, second.getMap("event")!!.getInt("value"))
      acknowledge.invoke(callback, firstId)
      stillBlocked()
      close.invoke(callback)
      waitFor(returned)
      assertNull(take.invoke(callback))
      val drained = enqueue(3)
      waitFor(returned)
      firstDelivery.get(2, TimeUnit.SECONDS)
      secondDelivery.get(2, TimeUnit.SECONDS)
      drained.get(2, TimeUnit.SECONDS)
      assertEquals(2, wakes.get())
    } finally {
      close.invoke(callback)
      worker.shutdownNow()
      assertTrue(worker.awaitTermination(2, TimeUnit.SECONDS))
    }
  }
}
