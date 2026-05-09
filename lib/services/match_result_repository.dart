import 'package:shared_preferences/shared_preferences.dart';

import '../models/match_result_record.dart';
import '../models/scoreboard_models.dart';

class MatchResultRepository {
  MatchResultRepository();

  static const _kMatchupStats = 'matchup_stats_v1';

  SharedPreferences? _prefs;

  Future<void> ensureLoaded() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Map<String, MatchupStatsRecord> _loadMap() {
    final raw = _prefs?.getString(_kMatchupStats);
    return MatchupStatsRecord.mapFromJson(raw);
  }

  Future<void> _saveMap(Map<String, MatchupStatsRecord> map) async {
    await ensureLoaded();
    await _prefs!.setString(_kMatchupStats, MatchupStatsRecord.mapToJson(map));
  }

  Future<void> recordMatch({
    required String opponentId,
    required bool myWin,
    required int myFouls,
    required int opponentFouls,
    required TimerTabKind timerTab,
    required int aTotalMinutes,
    required int aShotSeconds,
    required int bShotSeconds,
    required List<List<int>> setUsedSeconds,
  }) async {
    await ensureLoaded();
    final map = _loadMap();
    final now = DateTime.now().millisecondsSinceEpoch;
    final base = map[opponentId];
    final modeCounts = <String, int>{
      ...?base?.timerModeCounts,
    };
    modeCounts[timerTab.name] = (modeCounts[timerTab.name] ?? 0) + 1;
    final history = <MatchHistoryEntry>[
      ...?base?.matchHistory,
      MatchHistoryEntry(
        atMs: now,
        myWin: myWin,
        setUsedSeconds: setUsedSeconds,
      ),
    ];
    const keep = 200;
    if (history.length > keep) {
      history.removeRange(0, history.length - keep);
    }
    final next = MatchupStatsRecord(
      opponentId: opponentId,
      matches: (base?.matches ?? 0) + 1,
      wins: (base?.wins ?? 0) + (myWin ? 1 : 0),
      myFouls: (base?.myFouls ?? 0) + myFouls,
      opponentFouls: (base?.opponentFouls ?? 0) + opponentFouls,
      updatedAtMs: now,
      timerModeCounts: modeCounts,
      lastTimerTab: timerTab,
      lastATotalMinutes: aTotalMinutes,
      lastAShotSeconds: aShotSeconds,
      lastBShotSeconds: bShotSeconds,
      matchHistory: history,
    );
    map[opponentId] = next;
    await _saveMap(map);
  }

  Future<MatchupStatsRecord?> loadStats(String opponentId) async {
    await ensureLoaded();
    return _loadMap()[opponentId];
  }
}
