import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class BowlardRecord {
  const BowlardRecord({
    required this.playedOnIso,
    required this.totalScore,
    required this.gradeLabel,
    required this.createdAtMs,
  });

  final String playedOnIso;
  final int totalScore;
  final String gradeLabel;
  final int createdAtMs;

  Map<String, dynamic> toJson() => {
        'playedOnIso': playedOnIso,
        'totalScore': totalScore,
        'gradeLabel': gradeLabel,
        'createdAtMs': createdAtMs,
      };

  static BowlardRecord? fromJson(Map<String, dynamic> json) {
    final playedOnIso = json['playedOnIso'] as String?;
    final totalScore = json['totalScore'] as int?;
    final gradeLabel = json['gradeLabel'] as String?;
    final createdAtMs = json['createdAtMs'] as int?;
    if (playedOnIso == null ||
        totalScore == null ||
        gradeLabel == null ||
        createdAtMs == null) {
      return null;
    }
    return BowlardRecord(
      playedOnIso: playedOnIso,
      totalScore: totalScore,
      gradeLabel: gradeLabel,
      createdAtMs: createdAtMs,
    );
  }
}

class BowlardRecordRepository {
  static const _kRecords = 'bowlard_records_v1';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _instance() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<List<BowlardRecord>> loadAll() async {
    final prefs = await _instance();
    final raw = prefs.getString(_kRecords);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final records = list
          .map((item) => BowlardRecord.fromJson(item as Map<String, dynamic>))
          .whereType<BowlardRecord>()
          .toList();
      records.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
      return records;
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(BowlardRecord record) async {
    final existing = await loadAll();
    final next = [record, ...existing];
    final payload = jsonEncode(next.map((e) => e.toJson()).toList());
    final prefs = await _instance();
    await prefs.setString(_kRecords, payload);
  }
}
