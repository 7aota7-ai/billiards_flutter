import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/scoreboard_models.dart';

/// 端末に1件だけ保持する「あなた」プロフィール（ユーザIDは初回採番後ずっと同じ）
class StoredSelfProfile {
  const StoredSelfProfile({
    required this.id,
    required this.displayName,
    required this.rank,
  });

  final String id;
  final String displayName;
  final PlayerRank rank;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': displayName,
        'rank': rank.name,
      };

  static StoredSelfProfile? fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final rankName = j['rank'] as String? ?? PlayerRank.b.name;
    return StoredSelfProfile(
      id: j['id'] as String,
      displayName: j['name'] as String? ?? 'あなた',
      rank: PlayerRank.values.firstWhere(
        (e) => e.name == rankName,
        orElse: () => PlayerRank.b,
      ),
    );
  }
}

class SelfProfileRepository {
  SelfProfileRepository();

  static const _kSingle = 'self_profile_single_v2';
  static const _kLegacyList = 'self_players_json_v1';
  static const _kNextA = 'self_next_a_v1';
  static const _kNextB = 'self_next_b_v1';

  SharedPreferences? _prefs;

  Future<void> ensureLoaded() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded();
  }

  /// 旧「複数自分」リストがあれば先頭1件だけ新形式へ移す
  Future<void> _migrateLegacyIfNeeded() async {
    final p = _prefs!;
    if (p.getString(_kSingle) != null) return;
    final legacy = p.getString(_kLegacyList);
    if (legacy == null || legacy.isEmpty) return;
    try {
      final list = jsonDecode(legacy) as List<dynamic>;
      if (list.isEmpty) return;
      final first = list.first as Map<String, dynamic>;
      final id = first['id'] as String? ?? await _allocateNextId();
      final rankName = first['rank'] as String? ?? PlayerRank.b.name;
      final rank = PlayerRank.values.firstWhere(
        (e) => e.name == rankName,
        orElse: () => PlayerRank.b,
      );
      final name = first['name'] as String? ?? 'あなた';
      await _write(StoredSelfProfile(id: id, displayName: name, rank: rank));
      await p.remove(_kLegacyList);
    } catch (_) {}
  }

  StoredSelfProfile? load() {
    final raw = _prefs?.getString(_kSingle);
    return StoredSelfProfile.fromJsonString(raw);
  }

  Future<String> _allocateNextId() async {
    await ensureLoaded();
    var nextA = _prefs!.getInt(_kNextA) ?? 1;
    var nextB = _prefs!.getInt(_kNextB) ?? 1;
    if (nextA <= 9999) {
      final id = 'meA${nextA.toString().padLeft(4, '0')}';
      await _prefs!.setInt(_kNextA, nextA + 1);
      return id;
    }
    if (nextB <= 9999) {
      final id = 'meB${nextB.toString().padLeft(4, '0')}';
      await _prefs!.setInt(_kNextB, nextB + 1);
      return id;
    }
    return 'meX${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _write(StoredSelfProfile p) async {
    await ensureLoaded();
    await _prefs!.setString(_kSingle, jsonEncode(p.toJson()));
  }

  /// 「自分の情報を登録」: 初回は ID 採番。2回目以降は1件を上書き。級だけ変えたときは級のみ更新。
  Future<StoredSelfProfile> saveMyProfile({
    required String displayName,
    required PlayerRank rank,
  }) async {
    await ensureLoaded();
    final name = displayName.trim().isEmpty ? 'あなた' : displayName.trim();
    final existing = load();

    if (existing == null) {
      final id = await _allocateNextId();
      final p = StoredSelfProfile(id: id, displayName: name, rank: rank);
      await _write(p);
      return p;
    }

    final nameUnchanged = existing.displayName == name;
    if (nameUnchanged && existing.rank != rank) {
      final p = StoredSelfProfile(
        id: existing.id,
        displayName: existing.displayName,
        rank: rank,
      );
      await _write(p);
      return p;
    }

    final p = StoredSelfProfile(id: existing.id, displayName: name, rank: rank);
    await _write(p);
    return p;
  }

  /// 試合開始用: 保存済み ID があればそれを返す。なければフォーム内容で保存して ID を返す。
  Future<String> userKeyForMatch({
    required String displayName,
    required PlayerRank rank,
  }) async {
    await ensureLoaded();
    final existing = load();
    if (existing != null) return existing.id;
    final p = await saveMyProfile(displayName: displayName, rank: rank);
    return p.id;
  }
}
