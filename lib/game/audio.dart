import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

enum WaveShape { sine, square, saw, triangle }

/// Sound service contract so widgets can be tested without platform channels.
abstract class AudioService {
  bool get enabled;
  set enabled(bool value);

  Future<void> playShot();

  Future<void> playHit();

  Future<void> playEnemyDeath();

  Future<void> playWraithDeath();

  Future<void> playPlayerHit();

  Future<void> playPickup();

  Future<void> playPower(String power);

  Future<void> playRealm();

  Future<void> playGameOver();

  Future<void> playMenu();

  Future<void> startDrone();

  Future<void> stopDrone();

  Future<void> dispose();
}

/// Synthesises short tones as PCM WAV data and plays them through a native
/// Android `SoundPool` (see `MainActivity.kt`). No audio assets are needed —
/// every sound is generated — and each buffer is decoded by the platform
/// exactly once, so firing a sound never re-prepares media.
///
/// The original implementation pushed each WAV through `audioplayers`, which
/// re-prepares a `MediaPlayer` for every `play(BytesSource)` call. That
/// preparation runs on the platform thread and awaiting it stalls the UI —
/// most visibly when passing a realm, where three tones fire back to back.
class SynthAudioService implements AudioService {
  SynthAudioService();

  static const MethodChannel _channel =
      MethodChannel('kaalchakra/sound_effects');

  /// sound id per sound key; ids come from the native SoundPool.
  final Map<String, int> _soundIds = <String, int>{};

  bool _enabled = true;
  static const double _volume = 0.6;
  bool _droneRunning = false;
  int? _droneSoundId;
  int? _droneStreamId;

  /// The drone loop is generated once for the lifetime of the app.
  static final Uint8List _droneWav = _droneBuffer();

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool value) {
    _enabled = value;
    if (!value) {
      _stopDroneStream();
    }
  }

  @override
  Future<void> playShot() =>
      _play('shot', freq: 720, seconds: 0.06, shape: WaveShape.square, volume: 0.25);

  @override
  Future<void> playHit() =>
      _play('hit', freq: 320, seconds: 0.05, shape: WaveShape.triangle, volume: 0.3);

  @override
  Future<void> playEnemyDeath() => _play(
        'enemyDeath',
        freq: 180,
        endFreq: 70,
        seconds: 0.22,
        shape: WaveShape.saw,
        volume: 0.35,
      );

  @override
  Future<void> playWraithDeath() => _play(
        'wraithDeath',
        freq: 220,
        endFreq: 45,
        seconds: 0.45,
        shape: WaveShape.saw,
        volume: 0.45,
      );

  @override
  Future<void> playPlayerHit() => _play(
        'playerHit',
        freq: 150,
        endFreq: 60,
        seconds: 0.35,
        shape: WaveShape.square,
        volume: 0.45,
      );

  @override
  Future<void> playPickup() => _play(
        'pickup',
        freq: 520,
        endFreq: 900,
        seconds: 0.16,
        shape: WaveShape.sine,
        volume: 0.35,
      );

  @override
  Future<void> playPower(String power) {
    switch (power) {
      case 'freeze':
        return _play('freeze', freq: 300, endFreq: 900, seconds: 0.4, volume: 0.4);
      case 'rewind':
        return _play('rewind', freq: 900, endFreq: 220, seconds: 0.4, volume: 0.4);
      default:
        return _play('fast', freq: 220, endFreq: 1000, seconds: 0.3, volume: 0.4);
    }
  }

  @override
  Future<void> playRealm() async {
    // The three chime notes keep their arpeggio rhythm but are scheduled
    // independently so nothing here can gate the frame that advanced the
    // realm.
    unawaited(_play('realm0', freq: 440, seconds: 0.35, volume: 0.35));
    unawaited(Future<void>.delayed(const Duration(milliseconds: 160),
        () => _play('realm1', freq: 550, seconds: 0.35, volume: 0.35)));
    unawaited(Future<void>.delayed(const Duration(milliseconds: 320),
        () => _play('realm2', freq: 660, seconds: 0.35, volume: 0.35)));
  }

  @override
  Future<void> playGameOver() async {
    await _play('over1', freq: 200, endFreq: 120, seconds: 0.45, volume: 0.4);
    await Future<void>.delayed(const Duration(milliseconds: 240));
    await _play('over2', freq: 140, endFreq: 60, seconds: 0.7, volume: 0.4);
  }

  @override
  Future<void> playMenu() =>
      _play('menu', freq: 600, seconds: 0.05, shape: WaveShape.sine, volume: 0.25);

  @override
  Future<void> startDrone() async {
    if (!_enabled || _droneRunning) return;
    try {
      if (_droneSoundId == null || _droneSoundId! <= 0) {
        _droneSoundId = await _loadBytes('drone', _droneWav);
      }
      final id = _droneSoundId;
      if (id != null && id > 0) {
        _droneStreamId = await _invoke<int>('play', <String, Object?>{
          'soundId': id,
          'volume': 0.2 * _volume,
          'loop': true,
        });
        _droneRunning = true;
      }
    } catch (_) {
      _droneRunning = false;
    }
  }

  void _stopDroneStream() {
    _droneRunning = false;
    final stream = _droneStreamId;
    if (stream != null) {
      _droneStreamId = null;
      _invoke<void>('stop', <String, Object?>{'streamId': stream})
          .catchError((_) {});
    }
  }

  @override
  Future<void> stopDrone() async => _stopDroneStream();

  @override
  Future<void> dispose() async {
    try {
      await _invoke<void>('release', <String, Object?>{});
    } catch (_) {
      // The engine may already be gone.
    }
    _soundIds.clear();
  }

  Future<T?> _invoke<T>(String method, Map<String, Object?> args) =>
      _channel.invokeMethod<T>(method, args);

  /// Loads [bytes] as [key] and returns its sound id (0 on failure).
  Future<int> _loadBytes(String key, Uint8List bytes) async {
    final id = await _invoke<int>(
      'load',
      <String, Object?>{'key': key, 'bytes': bytes},
    );
    return id ?? 0;
  }

  Future<void> _play(
    String id, {
    required double freq,
    double? endFreq,
    double seconds = 0.2,
    WaveShape shape = WaveShape.sine,
    double volume = 0.3,
  }) async {
    if (!_enabled) return;
    try {
      var soundId = _soundIds[id];
      if (soundId == null) {
        soundId = await _loadBytes(id, _tone(
          freq: freq,
          endFreq: endFreq,
          seconds: seconds,
          shape: shape,
          volume: volume,
        ));
        if (soundId > 0) _soundIds[id] = soundId;
      }
      if (soundId > 0) {
        await _invoke<void>('play', <String, Object?>{
          'soundId': soundId,
          'volume': volume * _volume,
        });
      }
    } catch (_) {
      // Audio is a nice-to-have; never break gameplay because of it.
    }
  }

  /// Builds a mono 22.05 kHz 16-bit PCM WAV tone with a soft envelope.
  static Uint8List _tone({
    required double freq,
    double? endFreq,
    required double seconds,
    WaveShape shape = WaveShape.sine,
    double volume = 0.3,
  }) {
    const int sampleRate = 22050;
    final samples = (seconds * sampleRate).round().clamp(64, sampleRate ~/ 2);
    final target = endFreq ?? freq;

    final data = Uint8List(samples * 2);
    final view = ByteData.sublistView(data);
    var phase = 0.0;
    for (var i = 0; i < samples; i++) {
      final t = i / samples;
      final current = freq + (target - freq) * t;
      phase += 2 * math.pi * current / sampleRate;
      if (phase > 2 * math.pi) phase -= 2 * math.pi;

      final double raw;
      if (shape == WaveShape.sine) {
        raw = math.sin(phase);
      } else if (shape == WaveShape.square) {
        raw = math.sin(phase) >= 0 ? 1 : -1;
      } else if (shape == WaveShape.saw) {
        raw = 2 * (phase / (2 * math.pi)) - 1;
      } else {
        final x = phase / (2 * math.pi);
        raw = 2 * (2 * (x - x.floor()) - 1).abs() - 1;
      }

      // Attack / decay envelope keeps the tones from clicking.
      final envelope = math.min(1.0, i / 300) * math.pow(1 - t, 1.6).toDouble();
      final value = (raw * envelope * volume * 32000).clamp(-32767.0, 32767.0);
      view.setInt16(i * 2, value.round(), Endian.little);
    }

    return _wrapWav(data, sampleRate);
  }

  /// Two second seamless ambient drone (integer cycle counts so it loops clean).
  static Uint8List _droneBuffer() {
    const int sampleRate = 22050;
    const int seconds = 2;
    const int samples = sampleRate * seconds;
    final data = Uint8List(samples * 2);
    final view = ByteData.sublistView(data);
    for (var i = 0; i < samples; i++) {
      final t = i / sampleRate;
      final value = (math.sin(2 * math.pi * 55 * t) * 0.6 +
              math.sin(2 * math.pi * 82.5 * t) * 0.25 +
              math.sin(2 * math.pi * 110 * t) * 0.15) *
          0.5;
      view.setInt16(
        i * 2,
        (value * 32000).round().clamp(-32767, 32767).toInt(),
        Endian.little,
      );
    }
    return _wrapWav(data, sampleRate);
  }

  static Uint8List _wrapWav(Uint8List pcm, int sampleRate) {
    final header = BytesBuilder();
    void writeString(String value) => header.add(value.codeUnits);

    void writeInt32(int value) {
      final bytes = ByteData(4)..setUint32(0, value, Endian.little);
      header.add(bytes.buffer.asUint8List());
    }

    void writeInt16(int value) {
      final bytes = ByteData(2)..setInt16(0, value, Endian.little);
      header.add(bytes.buffer.asUint8List());
    }

    writeString('RIFF');
    writeInt32(36 + pcm.length);
    writeString('WAVE');
    writeString('fmt ');
    writeInt32(16);
    writeInt16(1); // PCM
    writeInt16(1); // mono
    writeInt32(sampleRate);
    writeInt32(sampleRate * 2);
    writeInt16(2);
    writeInt16(16);
    writeString('data');
    writeInt32(pcm.length);

    final out = Uint8List(header.length + pcm.length);
    out.setRange(0, header.length, header.toBytes());
    out.setRange(header.length, out.length, pcm);
    return out;
  }
}

/// Silent implementation used by tests and when sound is disabled.
class SilentAudioService implements AudioService {
  bool _enabled = false;

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool value) => _enabled = value;

  @override
  Future<void> playShot() async {}

  @override
  Future<void> playHit() async {}

  @override
  Future<void> playEnemyDeath() async {}

  @override
  Future<void> playWraithDeath() async {}

  @override
  Future<void> playPlayerHit() async {}

  @override
  Future<void> playPickup() async {}

  @override
  Future<void> playPower(String power) async {}

  @override
  Future<void> playRealm() async {}

  @override
  Future<void> playGameOver() async {}

  @override
  Future<void> playMenu() async {}

  @override
  Future<void> startDrone() async {}

  @override
  Future<void> stopDrone() async {}

  @override
  Future<void> dispose() async {}
}
