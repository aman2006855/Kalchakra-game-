import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Everything the game remembers between runs.
class SaveData {
  const SaveData({
    this.highScores = const <int>[],
    this.bestScore = 0,
    this.bestCombo = 1,
    this.unlockedRealm = 0,
    this.totalRuns = 0,
    this.totalKills = 0,
    this.soundEnabled = true,
    this.hapticsEnabled = true,
  });

  final List<int> highScores;
  final int bestScore;
  final int bestCombo;

  /// Highest realm index the player has reached (0 based).
  final int unlockedRealm;
  final int totalRuns;
  final int totalKills;
  final bool soundEnabled;
  final bool hapticsEnabled;

  SaveData copyWith({
    List<int>? highScores,
    int? bestScore,
    int? bestCombo,
    int? unlockedRealm,
    int? totalRuns,
    int? totalKills,
    bool? soundEnabled,
    bool? hapticsEnabled,
  }) {
    return SaveData(
      highScores: highScores ?? this.highScores,
      bestScore: bestScore ?? this.bestScore,
      bestCombo: bestCombo ?? this.bestCombo,
      unlockedRealm: unlockedRealm ?? this.unlockedRealm,
      totalRuns: totalRuns ?? this.totalRuns,
      totalKills: totalKills ?? this.totalKills,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    );
  }
}

/// Storage abstraction so the game can be tested without platform channels.
abstract class SaveStore {
  SaveData read();

  Future<void> write(SaveData data);

  Future<void> clear();
}

/// `shared_preferences` backed store used by the real app.
class PrefsSaveStore implements SaveStore {
  PrefsSaveStore(this._prefs);

  static const String _key = 'kalchakra_save_v1';

  final SharedPreferences _prefs;

  static Future<PrefsSaveStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    return PrefsSaveStore(prefs);
  }

  @override
  SaveData read() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const SaveData();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const SaveData();
      final scores = (decoded['highScores'] as List<dynamic>? ?? <dynamic>[])
          .whereType<num>()
          .map((num value) => value.toInt())
          .toList();
      return SaveData(
        highScores: scores,
        bestScore: (decoded['bestScore'] as num?)?.toInt() ?? 0,
        bestCombo: (decoded['bestCombo'] as num?)?.toInt() ?? 1,
        unlockedRealm: (decoded['unlockedRealm'] as num?)?.toInt() ?? 0,
        totalRuns: (decoded['totalRuns'] as num?)?.toInt() ?? 0,
        totalKills: (decoded['totalKills'] as num?)?.toInt() ?? 0,
        soundEnabled: decoded['soundEnabled'] as bool? ?? true,
        hapticsEnabled: decoded['hapticsEnabled'] as bool? ?? true,
      );
    } on FormatException {
      return const SaveData();
    }
  }

  @override
  Future<void> write(SaveData data) async {
    await _prefs.setString(
      _key,
      jsonEncode(<String, Object?>{
        'highScores': data.highScores,
        'bestScore': data.bestScore,
        'bestCombo': data.bestCombo,
        'unlockedRealm': data.unlockedRealm,
        'totalRuns': data.totalRuns,
        'totalKills': data.totalKills,
        'soundEnabled': data.soundEnabled,
        'hapticsEnabled': data.hapticsEnabled,
      }),
    );
  }

  @override
  Future<void> clear() async {
    await _prefs.remove(_key);
  }
}

/// In-memory store used by tests.
class MemorySaveStore implements SaveStore {
  MemorySaveStore([this._data = const SaveData()]);

  SaveData _data;

  @override
  SaveData read() => _data;

  @override
  Future<void> write(SaveData data) async {
    _data = data;
  }

  @override
  Future<void> clear() async {
    _data = const SaveData();
  }
}

/// Folds a finished run into the persistent save data.
SaveData recordRun(
  SaveData current, {
  required int score,
  required int maxCombo,
  required int realmReached,
  required int kills,
  required bool completed,
}) {
  final scores = <int>[...current.highScores, score]..sort((a, b) => b.compareTo(a));
  final trimmed = scores.take(10).toList(growable: false);
  final unlocked = (completed || realmReached > current.unlockedRealm)
      ? realmReached
      : current.unlockedRealm;
  return current.copyWith(
    highScores: trimmed,
    bestScore: score > current.bestScore ? score : current.bestScore,
    bestCombo: maxCombo > current.bestCombo ? maxCombo : current.bestCombo,
    unlockedRealm: unlocked,
    totalRuns: current.totalRuns + 1,
    totalKills: current.totalKills + kills,
  );
}
