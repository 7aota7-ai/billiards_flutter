import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/scoreboard_models.dart';

class GameSessionData {
  GameSessionData({
    required this.setup,
    required this.match,
    required this.startingPlayerB,
    required this.activeTurnPlayerB,
  });

  final MatchSetup setup;
  final MatchState match;
  final int startingPlayerB;
  final int activeTurnPlayerB;
}

class GameSessionStorage {
  static const _activeGameKey = 'active_game_session_v1';

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeGameKey);
  }

  static Future<void> save({
    required MatchSetup setup,
    required MatchState match,
    required int startingPlayerB,
    required int activeTurnPlayerB,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode({
      'setup': _setupToJson(setup),
      'match': _matchToJson(match),
      'startingPlayerB': startingPlayerB,
      'activeTurnPlayerB': activeTurnPlayerB,
    });
    await prefs.setString(_activeGameKey, json);
  }

  static Future<GameSessionData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activeGameKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final root = jsonDecode(raw) as Map<String, dynamic>;
      final setup = _setupFromJson(root['setup'] as Map<String, dynamic>);
      final match = _matchFromJson(root['match'] as Map<String, dynamic>, setup);
      return GameSessionData(
        setup: setup,
        match: match,
        startingPlayerB: (root['startingPlayerB'] as num?)?.toInt() ?? 0,
        activeTurnPlayerB: (root['activeTurnPlayerB'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _setupToJson(MatchSetup s) => {
        'p1Name': s.p1Name,
        'p2Name': s.p2Name,
        'p1Rank': s.p1Rank.name,
        'p2Rank': s.p2Rank.name,
        'p1UserKey': s.p1UserKey,
        'p2OpponentKey': s.p2OpponentKey,
        'p1Target': s.p1Target,
        'p2Target': s.p2Target,
        'timerTab': s.timerTab.name,
        'aTotalMinutes': s.aTotalMinutes,
        'aShotSeconds': s.aShotSeconds,
        'bShotSeconds': s.bShotSeconds,
        'maxSets': s.maxSets,
      };

  static MatchSetup _setupFromJson(Map<String, dynamic> j) => MatchSetup(
        p1Name: j['p1Name'] as String? ?? 'P1',
        p2Name: j['p2Name'] as String? ?? 'P2',
        p1Rank: _playerRankFromName(j['p1Rank'] as String?),
        p2Rank: _playerRankFromName(j['p2Rank'] as String?),
        p1UserKey: j['p1UserKey'] as String? ?? '',
        p2OpponentKey: j['p2OpponentKey'] as String? ?? '',
        p1Target: (j['p1Target'] as num?)?.toInt() ?? 5,
        p2Target: (j['p2Target'] as num?)?.toInt() ?? 5,
        timerTab: _timerTabFromName(j['timerTab'] as String?),
        aTotalMinutes: (j['aTotalMinutes'] as num?)?.toInt() ?? 30,
        aShotSeconds: (j['aShotSeconds'] as num?)?.toInt() ?? 25,
        bShotSeconds: (j['bShotSeconds'] as num?)?.toInt() ?? 45,
        maxSets: (j['maxSets'] as num?)?.toInt() ?? 0,
      );

  static Map<String, dynamic> _matchToJson(MatchState m) => {
        'scores': m.scores,
        'turnSwitchCountB': m.turnSwitchCountB,
        'fouls': m.fouls,
        'setWins': m.setWins,
        'currentSet': m.currentSet,
        'setResults': m.setResults,
        'gameOver': m.gameOver,
        'liveTimer': _liveTimerToJson(m.liveTimer),
      };

  static MatchState _matchFromJson(Map<String, dynamic> j, MatchSetup setup) {
    final liveTimer = _liveTimerFromJson(j['liveTimer'] as Map<String, dynamic>? ?? {}, setup);
    final m = MatchState(setup: setup, liveTimer: liveTimer);
    final scores = (j['scores'] as List?)?.cast<num>().map((e) => e.toInt()).toList();
    if (scores != null && scores.length == 2) {
      m.scores[0] = scores[0];
      m.scores[1] = scores[1];
    }
    final fouls = (j['fouls'] as List?)?.cast<num>().map((e) => e.toInt()).toList();
    if (fouls != null && fouls.length == 2) {
      m.fouls[0] = fouls[0];
      m.fouls[1] = fouls[1];
    }
    final setWins = (j['setWins'] as List?)?.cast<num>().map((e) => e.toInt()).toList();
    if (setWins != null && setWins.length == 2) {
      m.setWins[0] = setWins[0];
      m.setWins[1] = setWins[1];
    }
    m.turnSwitchCountB = (j['turnSwitchCountB'] as num?)?.toInt() ?? 0;
    m.currentSet = (j['currentSet'] as num?)?.toInt() ?? 1;
    m.gameOver = j['gameOver'] as bool? ?? false;
    final setResultsRaw = (j['setResults'] as List?) ?? const [];
    for (var i = 0; i < m.setResults.length && i < setResultsRaw.length; i++) {
      final v = setResultsRaw[i];
      m.setResults[i] = v == null ? null : (v as num).toInt();
    }
    return m;
  }

  static Map<String, dynamic> _liveTimerToJson(LiveTimer t) {
    if (t is LiveTimerA) {
      return {
        'type': 'A',
        'totalSecPerPlayer': t.totalSecPerPlayer,
        'shotSec': t.shotSec,
        'remain': t.remain,
        'phase': t.phase.name,
        'activePlayer': t.activePlayer,
        'shotRemain': t.shotRemain,
        'running': t.running,
        'paused': t.paused,
      };
    }
    if (t is LiveTimerB) {
      return {
        'type': 'B',
        'shotSec': t.shotSec,
        'remain': t.remain,
        'running': t.running,
        'paused': t.paused,
      };
    }
    return {'type': 'C'};
  }

  static LiveTimer _liveTimerFromJson(Map<String, dynamic> j, MatchSetup setup) {
    final type = j['type'] as String? ?? 'C';
    if (type == 'A') {
      return LiveTimerA(
        totalSecPerPlayer: (j['totalSecPerPlayer'] as num?)?.toInt() ?? setup.aTotalMinutes * 60,
        shotSec: (j['shotSec'] as num?)?.toInt() ?? setup.aShotSeconds,
        remain: ((j['remain'] as List?)?.cast<num>().map((e) => e.toInt()).toList()) ??
            [setup.aTotalMinutes * 60, setup.aTotalMinutes * 60],
        phase: _phaseFromName(j['phase'] as String?),
        activePlayer: (j['activePlayer'] as num?)?.toInt() ?? 0,
        shotRemain: (j['shotRemain'] as num?)?.toInt() ?? setup.aShotSeconds,
        running: j['running'] as bool? ?? false,
        paused: j['paused'] as bool? ?? false,
      );
    }
    if (type == 'B') {
      return LiveTimerB(
        shotSec: (j['shotSec'] as num?)?.toInt() ?? setup.bShotSeconds,
        remain: (j['remain'] as num?)?.toInt() ?? setup.bShotSeconds,
        running: j['running'] as bool? ?? false,
        paused: j['paused'] as bool? ?? false,
      );
    }
    return LiveTimerC();
  }

  static PlayerRank _playerRankFromName(String? name) {
    return PlayerRank.values.firstWhere(
      (v) => v.name == name,
      orElse: () => PlayerRank.b,
    );
  }

  static TimerTabKind _timerTabFromName(String? name) {
    return TimerTabKind.values.firstWhere(
      (v) => v.name == name,
      orElse: () => TimerTabKind.totalThenShot,
    );
  }

  static LiveTimerAPhase _phaseFromName(String? name) {
    return LiveTimerAPhase.values.firstWhere(
      (v) => v.name == name,
      orElse: () => LiveTimerAPhase.total,
    );
  }
}
