package com.tange.ai.tirtc.example

import com.tange.ai.tirtc.TiRtcAudioInputMode
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class ExampleRobotVoiceEffectTest {
    @Test
    fun splitChunksKeepTheSameEightyHertzPhaseAsOneContinuousChunk() {
        val input = pcmWithConstantSample(sample = 12000, sampleCount = 321)
        val continuous = ExampleRobotVoiceEffect(16000).process(input)
        val splitEffect = ExampleRobotVoiceEffect(16000)
        val split = splitEffect.process(input.copyOfRange(0, 242)) + splitEffect.process(input.copyOfRange(242, input.size))

        assertArrayEquals(continuous, split)
    }

    @Test
    fun resetStartsTheCarrierAtTheSamePhaseForEachRun() {
        val input = pcmWithConstantSample(sample = 16000, sampleCount = 160)
        val effect = ExampleRobotVoiceEffect(8000)
        val first = effect.process(input)
        effect.process(input)
        effect.reset()

        assertArrayEquals(first, effect.process(input))
    }

    @Test
    fun preservesLengthAndSilenceWithoutMutatingTheInput() {
        val input = ByteArray(640)
        val original = input.copyOf()

        val output = ExampleRobotVoiceEffect(16000).process(input)

        assertEquals(input.size, output.size)
        assertArrayEquals(original, input)
        assertArrayEquals(ByteArray(input.size), output)
    }

    @Test
    fun changesARepresentativeNonZeroSignal() {
        val input = pcmWithConstantSample(sample = 12000, sampleCount = 320)

        val output = ExampleRobotVoiceEffect(16000).process(input)

        assertFalse(input.contentEquals(output))
    }

    @Test
    fun settingsSelectCustomCaptureOnlyWhenRobotVoiceIsEnabled() {
        val normal = ExampleSettings().localAudioOptions()
        val robot = ExampleSettings(localAudioRobotVoiceEnabled = true).localAudioOptions()

        assertEquals(TiRtcAudioInputMode.BUILT_IN, normal.mode)
        assertEquals(TiRtcAudioInputMode.CUSTOM, robot.mode)
        assertEquals(true, robot.captureEnabled)
    }

    private fun pcmWithConstantSample(
        sample: Int,
        sampleCount: Int,
    ): ByteArray =
        ByteArray(sampleCount * 2).also { pcm ->
            repeat(sampleCount) { index ->
                pcm[index * 2] = sample.toByte()
                pcm[index * 2 + 1] = (sample shr 8).toByte()
            }
        }
}
