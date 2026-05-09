import 'dart:convert';

import 'scoreboard_models.dart';

/// 対戦相手ごとの試合結果集計（自分視点）
class MatchupStatsRecord {
  const MatchupStatsRecord({
    required this.opponentId,
    required this.matches,
    required this.wins,
    required this.myFouls,
    required this.opponentFouls,
    required this.updatedAtMs,
    required this.timerModeCounts,
    this.lastTimerTab,
    this.lastATotalMinutes,
    this.lastAShotSeconds,
    this.lastBShotSeconds,
    this.matchHistory = const [],
  });

  final String opponentId;
  final int matches;
  final int wins;
  final int myFouls;
  final int opponentFouls;
  final int updatedAtMs;
  final Map<String, int> timerModeCounts;
  final TimerTabKind? lastTimerTab;
  final int? lastATotalMinutes;
  final int? lastAShotSeconds;
  final int? lastBShotSeconds;
  final List<MatchHistoryEntry> matchHistory;

  int get losses => matches > wins ? matches - wins : 0;

  double get winRate => matches == 0 ? 0 : wins / matches;

  double get foulRate {
    final total = myFouls + opponentFouls;
    if (total == 0) return 0;
    return myFouls / total;
  }

  Map<String, dynamic> toJson() => {
        'opponentId': opponentId,
        'matches': matches,
        'wins': wins,
        'myFouls': myFouls,
        'opponentFouls': opponentFouls,
        'updatedAtMs': updatedAtMs,
        'timerModeCounts': timerModeCounts,
        'lastTimerTab': lastTimerTab?.name,
        'lastATotalMinutes': lastATotalMinutes,
        'lastAShotSeconds': lastAShotSeconds,
        'lastBShotSeconds': lastBShotSeconds,
        'matchHistory': matchHistory.map((e) => e.toJson()).toList(),
      };

  static MatchupStatsRecord fromJson(Map<String, dynamic> j) {
    return MatchupStatsRecord(
      opponentId: j['opponentId'] as String? ?? '',
      matches: (j['matches'] as num?)?.toInt() ?? 0,
      wins: (j['wins'] as num?)?.toInt() ?? 0,
      myFouls: (j['myFouls'] as num?)?.toInt() ?? 0,
      opponentFouls: (j['opponentFouls'] as num?)?.toInt() ?? 0,
      updatedAtMs: (j['updatedAtMs'] as num?)?.toInt() ?? 0,
      timerModeCounts: ((j['timerModeCounts'] as Map?) ?? const {})
          .map((k, v) => MapEntry('$k', (v as num).toInt())),
      lastTimerTab: _timerTabOrNull(j['lastTimerTab'] as String?),
      lastATotalMinutes: (j['lastATotalMinutes'] as num?)?.toInt(),
      lastAShotSeconds: (j['lastAShotSeconds'] as num?)?.toInt(),
      lastBShotSeconds: (j['lastBShotSeconds'] as num?)?.toInt(),
      matchHistory: ((j['matchHistory'] as List?) ?? const [])
          .map((e) => MatchHistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  static Map<String, MatchupStatsRecord> mapFromJson(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    final obj = jsonDecode(raw) as Map<String, dynamic>;
    return obj.map(
      (k, v) => MapEntry(
        k,
        MatchupStatsRecord.fromJson(Map<String, dynamic>.from(v as Map)),
      ),
    );
  }

  static String mapToJson(Map<String, MatchupStatsRecord> map) {
    final out = <String, dynamic>{};
    for (final e in map.entries) {
      out[e.key] = e.value.toJson();
    }
    return jsonEncode(out);
  }

  static TimerTabKind? _timerTabOrNull(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final v in TimerTabKind.values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

class MatchHistoryEntry {
  const MatchHistoryEntry({
    required this.atMs,
    required this.myWin,
    this.setUsedSeconds = const [],
  });

  final int atMs;
  final bool myWin;
  final List<List<int>> setUsedSeconds;

  Map<String, dynamic> toJson() => {
        'atMs': atMs,
        'myWin': myWin,
        'setUsedSeconds': setUsedSeconds,
      };

  static MatchHistoryEntry fromJson(Map<String, dynamic> j) {
    return MatchHistoryEntry(
      atMs: (j['atMs'] as num?)?.toInt() ?? 0,
      myWin: j['myWin'] as bool? ?? false,
      setUsedSeconds: ((j['setUsedSeconds'] as List?) ?? const [])
          .whereType<List>()
          .where((e) => e.length >= 2)
          .map((e) => <int>[
                (e[0] as num).toInt(),
                (e[1] as num).toInt(),
              ])
          .toList(),
    );
  }
}
