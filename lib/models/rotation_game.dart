/// ローテーション（15ボール）の試合状態。
///
/// 一般的なルール:
/// - 1〜15番の球を使い、入れた球の番号がそのまま得点（1ラック合計120点）。
/// - 先に目標点（デフォルト120点・選手ごとに変更可）へ到達した選手の勝ち。
/// - ファウル時に入った球は得点にならず台に戻す（＝入力しない）。相手はフリーボール。
/// - 15球すべて入ったら次のラックへ。ブレイクは勝者ブレイク（ラックの最後の球を入れた人）。
/// - ブレイクで規定数の球をキッチンに出せなかった場合のみ、ブレイク権が相手に移る。
class RotationGame {
  RotationGame({List<int>? targets, List<int>? extensions, int breaker = 0})
      : targets = List<int>.of(targets ?? const [defaultTarget, defaultTarget]),
        extensionLimits = List<int>.of(
          extensions ?? const [defaultExtensions, defaultExtensions],
        ),
        extensionsLeft = List<int>.of(
          extensions ?? const [defaultExtensions, defaultExtensions],
        ),
        _breaker = breaker,
        _shooter = breaker;

  static const int defaultTarget = 120;
  static const int ballCount = 15;
  static const int rackTotal = 120; // 1+2+...+15
  static const int defaultExtensions = 2;
  static const int maxExtensions = 5;

  final List<int> targets;
  final List<int> scores = [0, 0];
  final List<int> fouls = [0, 0];

  /// 試合全体で使えるエクステンション回数（B級2回・A級3回など、選手ごとに設定）
  final List<int> extensionLimits;
  final List<int> extensionsLeft;

  /// 現ラックで入った球 → 得点した選手
  final Map<int, int> pocketed = <int, int>{};

  /// 終了したラックごとの [p1得点, p2得点]
  final List<List<int>> rackHistory = <List<int>>[];

  int _breaker;
  int _shooter;
  int? winner;
  int _plays = 0;
  int _rackPlays = 0;

  final List<_Snapshot> _undoStack = <_Snapshot>[];

  int get shooter => _shooter;
  int get breaker => _breaker;
  int get rackNumber => rackHistory.length + 1;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get isStarted => _plays > 0;

  /// 台に残っている球（昇順）
  List<int> get remainingBalls => [
        for (var n = 1; n <= ballCount; n++)
          if (!pocketed.containsKey(n)) n,
      ];

  /// 次に最初に当てるべき球（台上の最小番号）
  int? get lowestBall {
    final r = remainingBalls;
    return r.isEmpty ? null : r.first;
  }

  /// ラック開始直後（ブレイクショット前後で、まだ入力がない）か。
  bool get canBreakFail =>
      winner == null && pocketed.isEmpty && _rackPlays == 0;

  int get remainingPoints => remainingBalls.fold(0, (a, b) => a + b);

  /// 現ラックでの各選手の得点
  List<int> get currentRackScores {
    final s = [0, 0];
    pocketed.forEach((ball, player) => s[player] += ball);
    return s;
  }

  void setBreaker(int player) {
    if (isStarted) return;
    _breaker = player;
    _shooter = player;
  }

  void setTarget(int player, int value) {
    if (value <= 0) return;
    _push();
    targets[player] = value;
    _checkWinner();
  }

  /// エクステンション回数の上限を変更する。使用済み回数は維持する。
  void setExtensionLimit(int player, int limit) {
    final n = limit.clamp(0, maxExtensions);
    if (n == extensionLimits[player]) return;
    _push();
    final used = extensionLimits[player] - extensionsLeft[player];
    extensionLimits[player] = n;
    extensionsLeft[player] = (n - used).clamp(0, n);
  }

  /// 手番の選手がエクステンションを使う。残っていなければ false。
  bool useExtension() {
    if (winner != null || extensionsLeft[_shooter] <= 0) return false;
    _push();
    extensionsLeft[_shooter]--;
    return true;
  }

  /// 現在の手番の選手が [ball] を入れた。
  void pocket(int ball) {
    if (winner != null) return;
    if (ball < 1 || ball > ballCount || pocketed.containsKey(ball)) return;
    _push();
    _plays++;
    _rackPlays++;
    pocketed[ball] = _shooter;
    scores[_shooter] += ball;
    fouls[_shooter] = 0;
    _checkWinner();
    if (winner == null && pocketed.length == ballCount) {
      _finishRack();
    }
  }

  /// ミス（ノーイン）で手番交代。
  void miss() {
    if (winner != null) return;
    _push();
    _plays++;
    _rackPlays++;
    fouls[_shooter] = 0;
    _switchShooter();
  }

  /// 手番の選手のファウル。相手にフリーボールで手番交代。
  void foul() {
    if (winner != null) return;
    _push();
    _plays++;
    _rackPlays++;
    fouls[_shooter]++;
    _switchShooter();
  }

  /// ブレイクで球をキッチンに出せなかった：ブレイク権を相手に渡して再ブレイク。
  void breakFailed() {
    if (!canBreakFail) return;
    _push();
    _plays++;
    _breaker = 1 - _breaker;
    _shooter = _breaker;
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _undoStack.removeLast().restoreTo(this);
  }

  void reset() {
    scores
      ..[0] = 0
      ..[1] = 0;
    fouls
      ..[0] = 0
      ..[1] = 0;
    extensionsLeft
      ..[0] = extensionLimits[0]
      ..[1] = extensionLimits[1];
    pocketed.clear();
    rackHistory.clear();
    _undoStack.clear();
    winner = null;
    _plays = 0;
    _rackPlays = 0;
    _shooter = _breaker;
  }

  void _switchShooter() => _shooter = 1 - _shooter;

  void _checkWinner() {
    for (var p = 0; p < 2; p++) {
      if (scores[p] >= targets[p]) {
        winner = p;
        return;
      }
    }
    winner = null;
  }

  void _finishRack() {
    final rack = currentRackScores;
    rackHistory.add(rack);
    pocketed.clear();
    fouls
      ..[0] = 0
      ..[1] = 0;
    _rackPlays = 0;
    // 勝者ブレイク：ラックの最後の球を入れた人（＝今の手番）が次をブレイク。
    // 15番が途中でフロックで入っていても、最後に入れた球の人が対象。
    _breaker = _shooter;
    _shooter = _breaker;
  }

  void _push() => _undoStack.add(_Snapshot.of(this));
}

class _Snapshot {
  _Snapshot.of(RotationGame g)
      : targets = List<int>.of(g.targets),
        scores = List<int>.of(g.scores),
        fouls = List<int>.of(g.fouls),
        extensionLimits = List<int>.of(g.extensionLimits),
        extensionsLeft = List<int>.of(g.extensionsLeft),
        pocketed = Map<int, int>.of(g.pocketed),
        rackHistory = [for (final r in g.rackHistory) List<int>.of(r)],
        breaker = g._breaker,
        shooter = g._shooter,
        winner = g.winner,
        plays = g._plays,
        rackPlays = g._rackPlays;

  final List<int> targets;
  final List<int> scores;
  final List<int> fouls;
  final List<int> extensionLimits;
  final List<int> extensionsLeft;
  final Map<int, int> pocketed;
  final List<List<int>> rackHistory;
  final int breaker;
  final int shooter;
  final int? winner;
  final int plays;
  final int rackPlays;

  void restoreTo(RotationGame g) {
    g.targets
      ..clear()
      ..addAll(targets);
    g.scores
      ..clear()
      ..addAll(scores);
    g.fouls
      ..clear()
      ..addAll(fouls);
    g.extensionLimits
      ..clear()
      ..addAll(extensionLimits);
    g.extensionsLeft
      ..clear()
      ..addAll(extensionsLeft);
    g.pocketed
      ..clear()
      ..addAll(pocketed);
    g.rackHistory
      ..clear()
      ..addAll(rackHistory);
    g._breaker = breaker;
    g._shooter = shooter;
    g.winner = winner;
    g._plays = plays;
    g._rackPlays = rackPlays;
  }
}
