import 'dart:convert';

import 'scoreboard_models.dart';

/// 登録済み対戦相手（ユーザID と表示情報）
class OpponentRecord {
  const OpponentRecord({
    required this.id,
    required this.displayName,
    required this.rank,
    required this.createdAtMs,
    this.matchCount = 0,
    this.lastPlayedAtMs = 0,
  });

  final String id;
  final String displayName;
  final PlayerRank rank;
  final int createdAtMs;

  /// 試合開始した回数（よく対戦する相手の並びに使用）
  final int matchCount;

  /// 直近の試合開始時刻（ms）
  final int lastPlayedAtMs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': displayName,
        'rank': rank.name,
        'createdAtMs': createdAtMs,
        'matchCount': matchCount,
        'lastPlayedAtMs': lastPlayedAtMs,
      };

  static OpponentRecord fromJson(Map<String, dynamic> j) {
    final rankName = j['rank'] as String? ?? PlayerRank.b.name;
    return OpponentRecord(
      id: j['id'] as String,
      displayName: j['name'] as String? ?? '',
      rank: PlayerRank.values.firstWhere(
        (e) => e.name == rankName,
        orElse: () => PlayerRank.b,
      ),
      createdAtMs: j['createdAtMs'] as int? ?? 0,
      matchCount: j['matchCount'] as int? ?? 0,
      lastPlayedAtMs: j['lastPlayedAtMs'] as int? ?? 0,
    );
  }

  static List<OpponentRecord> listFromJson(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => OpponentRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static String listToJson(List<OpponentRecord> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());
}
