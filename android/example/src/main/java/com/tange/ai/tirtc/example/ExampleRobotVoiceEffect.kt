package com.tange.ai.tirtc.example

import kotlin.math.PI
import kotlin.math.roundToInt
import kotlin.math.sin

/** Stateful 80 Hz ring modulation used only by the public Example talkback switch. */
internal class ExampleRobotVoiceEffect(
    sampleRateHz: Int,
) {
    private val phaseStep = 2.0 * PI * FREQUENCY_HZ / sampleRateHz.toDouble()
    private var phase = 0.0

    init {
        require(sampleRateHz == 8000 || sampleRateHz == 16000)
    }

    @Synchronized
    fun process(pcm: ByteArray): ByteArray {
        require(pcm.isNotEmpty() && pcm.size % 2 == 0)
        val output = ByteArray(pcm.size)
        var offset = 0
        while (offset < pcm.size) {
            val sample =
                (
                    ((pcm[offset + 1].toInt() and 0xff) shl 8) or
                        (pcm[offset].toInt() and 0xff)
                ).toShort().toInt()
            val modulated =
                (sample * sin(phase)).roundToInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
            output[offset] = modulated.toByte()
            output[offset + 1] = (modulated shr 8).toByte()
            phase += phaseStep
            if (phase >= 2.0 * PI) phase -= 2.0 * PI
            offset += 2
        }
        return output
    }

    @Synchronized
    fun reset() {
        phase = 0.0
    }

    private companion object {
        const val FREQUENCY_HZ = 80.0
    }
}
