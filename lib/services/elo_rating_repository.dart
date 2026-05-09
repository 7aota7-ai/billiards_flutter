import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/elo_rating_models.dart';

class EloRatingRepository {
  EloRatingRepository();

  static const _kEloRatings = 'elo_ratings_v1';

  SharedPreferences? _prefs;

  Future<void> ensureLoaded() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Map<String, Map<String, EloRatingRecord>> _loadAll() {
    final raw = _prefs?.getString(_kEloRatings);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    final root = jsonDecode(raw) as Map<String, dynamic>;
    final out = <String, Map<String, EloRatingRecord>>{};
    for (final poolEntry in root.entries) {
      final byIdRaw = poolEntry.value as Map<String, dynamic>;
      out[poolEntry.key] = byIdRaw.map(
        (k, v) => MapEntry(
          k,
          EloRatingRecord.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
      );
    }
    return out;
  }

  Future<void> _saveAll(Map<String, Map<String, EloRatingRecord>> all) async {
    final root = <String, dynamic>{};
    for (final poolEntry in all.entries) {
      root[poolEntry.key] = poolEntry.value.map(
        (k, v) => MapEntry(k, v.toJson()),
      );
    }
    await _prefs!.setString(_kEloRatings, jsonEncode(root));
  }

  Future<EloRatingRecord> loadRating(String playerId, EloPool pool) async {
    await ensureLoaded();
    final all = _loadAll();
    final poolKey = pool.name;
    final byId = all[poolKey] ?? {};
    return byId[playerId] ??
        EloRatingRecord(
          playerId: playerId,
          rating: 1500,
          ratedGames: 0,
          wins: 0,
          losses: 0,
          updatedAtMs: 0,
        );
  }

  Future<Map<String, EloRatingRecord>> loadPool(EloPool pool) async {
    await ensureLoaded();
    final all = _loadAll();
    return Map<String, EloRatingRecord>.from(all[pool.name] ?? const {});
  }

  int _kFor(int ratedGames) {
    if (ratedGames < 30) return 32;
    return 24;
  }

  double _expectedScore(int myRating, int oppRating) {
    return 1.0 / (1.0 + math.pow(10, (oppRating - myRating) / 400.0));
  }

  Future<EloMatchUpdate> applyMatchResult({
    required String winnerId,
    required String loserId,
    required EloPool pool,
  }) async {
    await ensureLoaded();
    final now = DateTime.now().millisecondsSinceEpoch;
    final all = _loadAll();
    final poolKey = pool.name;
    final byId = all[poolKey] ?? <String, EloRatingRecord>{};

    final winner = byId[winnerId] ??
        EloRatingRecord(
          playerId: winnerId,
          rating: 1500,
          ratedGames: 0,
          wins: 0,
          losses: 0,
          updatedAtMs: 0,
        );
    final loser = byId[loserId] ??
        EloRatingRecord(
          playerId: loserId,
          rating: 1500,
          ratedGames: 0,
          wins: 0,
          losses: 0,
          updatedAtMs: 0,
        );

    final expectedWinner = _expectedScore(winner.rating, loser.rating);
    final expectedLoser = _expectedScore(loser.rating, winner.rating);
    final kWinner = _kFor(winner.ratedGames);
    final kLoser = _kFor(loser.ratedGames);

    final nextWinner = (winner.rating + kWinner * (1 - expectedWinner)).round();
    final nextLoser = (loser.rating + kLoser * (0 - expectedLoser)).round();

    byId[winnerId] = EloRatingRecord(
      playerId: winner.playerId,
      rating: nextWinner,
      ratedGames: winner.ratedGames + 1,
      wins: winner.wins + 1,
      losses: winner.losses,
      updatedAtMs: now,
    );
    byId[loserId] = EloRatingRecord(
      playerId: loser.playerId,
      rating: nextLoser,
      ratedGames: loser.ratedGames + 1,
      wins: loser.wins,
      losses: loser.losses + 1,
      updatedAtMs: now,
    );
    all[poolKey] = byId;
    await _saveAll(all);

    return EloMatchUpdate(
      winnerBefore: winner.rating,
      winnerAfter: nextWinner,
      loserBefore: loser.rating,
      loserAfter: nextLoser,
      kWinner: kWinner,
      kLoser: kLoser,
      expectedWinner: expectedWinner,
      expectedLoser: expectedLoser,
    );
  }
}
