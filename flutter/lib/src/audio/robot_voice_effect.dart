import 'dart:math' as math;
import 'dart:typed_data';

/// Stateful 80 Hz ring modulation used only by the public Example.
final class DemoRobotVoiceEffect {
  DemoRobotVoiceEffect({required int sampleRate}) : _phaseStep = 2 * math.pi * 80 / sampleRate {
    if (sampleRate != 8000 && sampleRate != 16000) {
      throw ArgumentError.value(sampleRate, 'sampleRate');
    }
  }

  static const double _twoPi = 2 * math.pi;

  final double _phaseStep;
  double _phase = 0;

  Uint8List process(Uint8List pcm) {
    if (pcm.isEmpty || !pcm.lengthInBytes.isEven) {
      throw ArgumentError.value(pcm.lengthInBytes, 'pcm.lengthInBytes');
    }
    final Uint8List output = Uint8List(pcm.lengthInBytes);
    final ByteData inputData = ByteData.sublistView(pcm);
    final ByteData outputData = ByteData.sublistView(output);
    for (int offset = 0; offset < pcm.lengthInBytes; offset += 2) {
      final int sample = inputData.getInt16(offset, Endian.little);
      final int modulated = (sample * math.sin(_phase)).round().clamp(-32768, 32767);
      outputData.setInt16(offset, modulated, Endian.little);
      _phase += _phaseStep;
      if (_phase >= _twoPi) {
        _phase -= _twoPi;
      }
    }
    return output;
  }

  void reset() {
    _phase = 0;
  }
}
