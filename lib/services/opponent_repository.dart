import 'package:shared_preferences/shared_preferences.dart';

import '../models/opponent_record.dart';
import '../models/scoreboard_models.dart';

/// 端末内の `opponent_key` 採番（billA0001〜billA9999 → billB〜）と相手一覧
class OpponentRepository {
  OpponentRepository();

  static const _kOpponents = 'opponents_json_v1';
  static const _kNextA = 'opponent_next_a_v1';
  static const _kNextB = 'opponent_next_b_v1';

  SharedPreferences? _prefs;

  Future<void> ensureLoaded() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  List<OpponentRecord> getAll() {
    final raw = _prefs?.getString(_kOpponents);
    return OpponentRecord.listFromJson(raw);
  }

  /// 名前または ID の部分一致（小文字）
  List<OpponentRecord> search(String query) {
    final q = query.trim().toLowerCase();
    final all = getAll();
    if (q.isEmpty) return List.of(all)..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return all
        .where(
          (o) =>
              o.displayName.toLowerCase().contains(q) || o.id.toLowerCase().contains(q),
        )
        .toList()
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
  }

  Future<String> _allocateNextId() async {
    await ensureLoaded();
    var nextA = _prefs!.getInt(_kNextA) ?? 1;
    var nextB = _prefs!.getInt(_kNextB) ?? 1;
    if (nextA <= 9999) {
      final id = 'billA${nextA.toString().padLeft(4, '0')}';
      await _prefs!.setInt(_kNextA, nextA + 1);
      return id;
    }
    if (nextB <= 9999) {
      final id = 'billB${nextB.toString().padLeft(4, '0')}';
      await _prefs!.setInt(_kNextB, nextB + 1);
      return id;
    }
    final fallback = DateTime.now().millisecondsSinceEpoch;
    return 'billX$fallback';
  }

  Future<OpponentRecord> registerNew({
    required String displayName,
    required PlayerRank rank,
  }) async {
    await ensureLoaded();
    final id = await _allocateNextId();
    final now = DateTime.now().millisecondsSinceEpoch;
    final rec = OpponentRecord(
      id: id,
      displayName: displayName.trim().isEmpty ? '相手' : displayName.trim(),
      rank: rank,
      createdAtMs: now,
      matchCount: 0,
      lastPlayedAtMs: 0,
    );
    final list = getAll()..add(rec);
    await _prefs!.setString(_kOpponents, OpponentRecord.listToJson(list));
    return rec;
  }

  Future<void> saveAll(List<OpponentRecord> list) async {
    await ensureLoaded();
    await _prefs!.setString(_kOpponents, OpponentRecord.listToJson(list));
  }

  OpponentRecord? findById(String id) {
    for (final o in getAll()) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// 試合開始時に呼ぶ。対戦回数と最終対戦日時を更新する。
  Future<void> recordMatchPlayed(String opponentId) async {
    await ensureLoaded();
    final list = getAll();
    final i = list.indexWhere((o) => o.id == opponentId);
    if (i < 0) return;
    final o = list[i];
    final now = DateTime.now().millisecondsSinceEpoch;
    list[i] = OpponentRecord(
      id: o.id,
      displayName: o.displayName,
      rank: o.rank,
      createdAtMs: o.createdAtMs,
      matchCount: o.matchCount + 1,
      lastPlayedAtMs: now,
    );
    await saveAll(list);
  }

  /// よく対戦（回数順）を優先し、足りなければ新しい登録順で埋めて最大 [limit] 件。
  List<OpponentRecord> topFrequentOrRecent({int limit = 3}) {
    final all = getAll();
    if (all.isEmpty) return [];
    final withPlays = all.where((o) => o.matchCount > 0).toList()
      ..sort((a, b) {
        final c = b.matchCount.compareTo(a.matchCount);
        if (c != 0) return c;
        return b.lastPlayedAtMs.compareTo(a.lastPlayedAtMs);
      });
    final out = <OpponentRecord>[];
    final ids = <String>{};
    for (final o in withPlays) {
      if (out.length >= limit) break;
      out.add(o);
      ids.add(o.id);
    }
    if (out.length < limit) {
      final rest = all.where((o) => !ids.contains(o.id)).toList()
        ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
      for (final o in rest) {
        if (out.length >= limit) break;
        out.add(o);
        ids.add(o.id);
      }
    }
    return out;
  }
}
