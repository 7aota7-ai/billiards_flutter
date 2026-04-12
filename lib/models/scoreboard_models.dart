/// モック HTML `billiards_scoreboard_v6.html` に対応するデータモデル。

enum PlayerRank {
  sa('SA級'),
  a('A級'),
  b('B級'),
  c('C級');

  const PlayerRank(this.labelJa);
  final String labelJa;

}

/// セットアップ画面のタイマータブ（A/B/C）
enum TimerTabKind {
  /// 持ち時間 → 両者切れ後に 1 ショット
  totalThenShot,

  /// 1 ショットクロックのみ
  shotClockOnly,

  /// 制限なし
  unlimited,
}

/// 試合開始前の入力一式
class MatchSetup {
  MatchSetup({
    required this.p1Name,
    required this.p2Name,
    required this.p1Rank,
    required this.p2Rank,
    required this.p1UserKey,
    required this.p2OpponentKey,
    required this.p1Target,
    required this.p2Target,
    required this.timerTab,
    required this.aTotalMinutes,
    required this.aShotSeconds,
    required this.bShotSeconds,
    required this.maxSets,
  });

  final String p1Name;
  final String p2Name;

  /// アーカイブ用。自分プロフィール（例: meA0001）
  final String p1UserKey;

  /// アーカイブ用。相手を一意に識別（例: billA0001）
  final String p2OpponentKey;
  final PlayerRank p1Rank;
  final PlayerRank p2Rank;
  final int p1Target;
  final int p2Target;
  final TimerTabKind timerTab;

  /// 持ち時間モード: 各自の分数
  final int aTotalMinutes;

  /// 持ち時間モード: 時間切れ後の 1 ショット秒
  final int aShotSeconds;

  /// 1 ショットクロック: 秒
  final int bShotSeconds;

  /// 0 = セットなし、3/5/7/9 = 最大セット数
  final int maxSets;

  int get firstToWinSets =>
      maxSets > 0 ? (maxSets + 1) ~/ 2 : 0; // 先取 (例: 5→3)
}

/// 進行中タイマー（JS の TM に相当）
sealed class LiveTimer {}

/// モード A
class LiveTimerA extends LiveTimer {
  LiveTimerA({
    required this.totalSecPerPlayer,
    required this.shotSec,
    required List<int> remain,
    this.phase = LiveTimerAPhase.total,
    this.activePlayer = 0,
    this.shotRemain = 0,
    this.running = false,
    this.paused = false,
  }) : remain = List<int>.from(remain);

  final int totalSecPerPlayer;
  final int shotSec;

  /// 各自の残り秒
  final List<int> remain;

  LiveTimerAPhase phase;
  int activePlayer;
  int shotRemain;
  bool running;
  bool paused;
}

enum LiveTimerAPhase { total, shot }

/// モード B
class LiveTimerB extends LiveTimer {
  LiveTimerB({
    required this.shotSec,
    required this.remain,
    this.running = false,
    this.paused = false,
  });

  final int shotSec;
  int remain;
  bool running;
  bool paused;
}

/// モード C
class LiveTimerC extends LiveTimer {
  LiveTimerC();
}

/// 試合中のスコア・セット状態
class MatchState {
  MatchState({
    required this.setup,
    required this.liveTimer,
  })  : scores = [0, 0],
        setWins = [0, 0],
        currentSet = 1,
        fouls = [0, 0],
        setResults = setup.maxSets > 0
            ? List<int?>.filled(setup.maxSets, null)
            : <int?>[],
        gameOver = false;

  final MatchSetup setup;
  LiveTimer liveTimer;

  final List<int> scores;

  /// モードB: 「攻守交替」ボタンの累計タップ数
  int turnSwitchCountB = 0;

  /// 各プレイヤーの連続ファウル（3で相手に1点＋セット終了など）
  final List<int> fouls;
  final List<int> setWins;
  int currentSet;

  /// 各セットの勝者 0 or 1（長さ = maxSets、未決着は null）
  final List<int?> setResults;
  bool gameOver;

  List<String> get names => [setup.p1Name, setup.p2Name];
  List<PlayerRank> get ranks => [setup.p1Rank, setup.p2Rank];
  List<int> get targets => [setup.p1Target, setup.p2Target];
}
