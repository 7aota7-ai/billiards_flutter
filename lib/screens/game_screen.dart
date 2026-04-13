import 'dart:async';

import 'package:flutter/material.dart';

import '../models/scoreboard_models.dart';
import '../theme/apple_theme.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.setup});

  final MatchSetup setup;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late MatchState _match;
  Timer? _tick;
  int _startingPlayerB = 0;
  int _activeTurnPlayerB = 0;

  MatchSetup get _s => widget.setup;

  @override
  void initState() {
    super.initState();
    _match = MatchState(setup: _s, liveTimer: _createInitialTimer());
    _startingPlayerB = 0;
    _activeTurnPlayerB = 0;
  }

  @override
  void dispose() {
    _stopTick();
    super.dispose();
  }

  LiveTimer _createInitialTimer() {
    switch (_s.timerTab) {
      case TimerTabKind.totalThenShot:
        final total = _s.aTotalMinutes * 60;
        return LiveTimerA(
          totalSecPerPlayer: total,
          shotSec: _s.aShotSeconds,
          remain: [total, total],
        );
      case TimerTabKind.shotClockOnly:
        return LiveTimerB(
          shotSec: _s.bShotSeconds,
          remain: _s.bShotSeconds,
        );
      case TimerTabKind.unlimited:
        return LiveTimerC();
    }
  }

  void _stopTick() {
    _tick?.cancel();
    _tick = null;
  }

  void _startPeriodic(void Function() onTick) {
    _stopTick();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_match.gameOver) {
        _stopTick();
        return;
      }
      onTick();
      setState(() {});
    });
  }

  /// 試合終了時: 周期タイマーを止め、LiveTimer の進行を止める
  void _applyGameOverFreeze() {
    _stopTick();
    final t = _match.liveTimer;
    if (t is LiveTimerB) {
      t.running = false;
      t.paused = true;
    } else if (t is LiveTimerA) {
      t.running = false;
      t.paused = true;
    }
  }

  // --- Mode B ---
  void _bStart() {
    final t = _match.liveTimer;
    if (t is! LiveTimerB) return;
    if (t.running || t.paused) return;
    t.running = true;
    t.paused = false;
    _startPeriodic(() {
      final tm = _match.liveTimer as LiveTimerB;
      tm.remain--;
      if (tm.remain <= 0) {
        tm.remain = 0;
        tm.running = false;
        _stopTick();
      }
    });
  }

  void _bPause() {
    final t = _match.liveTimer;
    if (t is! LiveTimerB) return;
    _stopTick();
    t.running = false;
    t.paused = true;
  }

  void _bResume() {
    final t = _match.liveTimer;
    if (t is! LiveTimerB) return;
    if (!t.paused) return;
    t.paused = false;
    t.running = true;
    _startPeriodic(() {
      final tm = _match.liveTimer as LiveTimerB;
      tm.remain--;
      if (tm.remain <= 0) {
        tm.remain = 0;
        tm.running = false;
        tm.paused = false;
        _stopTick();
      }
    });
  }

  void _bReset() {
    final t = _match.liveTimer;
    if (t is! LiveTimerB) return;
    _stopTick();
    t.running = false;
    t.paused = false;
    t.remain = t.shotSec;
  }

  void _onTurnSwitchB() {
    if (_match.gameOver) return;
    final t = _match.liveTimer;
    if (t is! LiveTimerB) return;
    setState(() {
      _match.turnSwitchCountB++;
      _activeTurnPlayerB = 1 - _activeTurnPlayerB;
    });
  }

  void _setStartingPlayerB(int player) {
    if (_match.gameOver) return;
    final t = _match.liveTimer;
    if (t is! LiveTimerB) return;
    setState(() {
      _startingPlayerB = player;
      _activeTurnPlayerB = player;
    });
  }

  // --- Mode A: total ---
  void _aStartPlayer(int player) {
    final t = _match.liveTimer;
    if (t is! LiveTimerA) return;
    if (t.phase != LiveTimerAPhase.total) return;
    _stopTick();
    t.running = true;
    t.paused = false;
    t.activePlayer = player;
    _startPeriodic(() {
      final tm = _match.liveTimer as LiveTimerA;
      if (tm.phase != LiveTimerAPhase.total) {
        _stopTick();
        return;
      }
      tm.remain[player]--;
      if (tm.remain[player] <= 0) {
        tm.remain[player] = 0;
        if (tm.remain[0] <= 0 && tm.remain[1] <= 0) {
          tm.phase = LiveTimerAPhase.shot;
          tm.shotRemain = tm.shotSec;
        }
        tm.running = false;
        _stopTick();
      }
    });
  }

  void _aPause() {
    final t = _match.liveTimer;
    if (t is! LiveTimerA) return;
    if (t.phase != LiveTimerAPhase.total) return;
    _stopTick();
    t.running = false;
  }

  // --- Mode A: shot ---
  void _aShotStart() {
    final t = _match.liveTimer;
    if (t is! LiveTimerA) return;
    if (t.phase != LiveTimerAPhase.shot) return;
    if (t.running || t.paused) return;
    t.running = true;
    t.paused = false;
    _startPeriodic(() {
      final tm = _match.liveTimer as LiveTimerA;
      tm.shotRemain--;
      if (tm.shotRemain <= 0) {
        tm.shotRemain = 0;
        tm.running = false;
        _stopTick();
      }
    });
  }

  void _aShotPause() {
    final t = _match.liveTimer;
    if (t is! LiveTimerA) return;
    if (t.phase != LiveTimerAPhase.shot) return;
    _stopTick();
    t.running = false;
    t.paused = true;
  }

  void _aShotResume() {
    final t = _match.liveTimer;
    if (t is! LiveTimerA) return;
    if (t.phase != LiveTimerAPhase.shot) return;
    if (!t.paused) return;
    t.paused = false;
    t.running = true;
    _startPeriodic(() {
      final tm = _match.liveTimer as LiveTimerA;
      tm.shotRemain--;
      if (tm.shotRemain <= 0) {
        tm.shotRemain = 0;
        tm.running = false;
        tm.paused = false;
        _stopTick();
      }
    });
  }

  void _aShotReset() {
    final t = _match.liveTimer;
    if (t is! LiveTimerA) return;
    if (t.phase != LiveTimerAPhase.shot) return;
    _stopTick();
    t.running = false;
    t.paused = false;
    t.shotRemain = t.shotSec;
  }

  void _onScoreDelta(int player, int delta) {
    if (_match.gameOver) return;
    setState(() {
      _match.scores[player] = (_match.scores[player] + delta).clamp(0, 9999);
      if (_s.maxSets > 0) {
        for (var i = 0; i < 2; i++) {
          if (_match.scores[i] >= _match.targets[i]) {
            final idx = _match.currentSet - 1;
            if (idx >= 0 && idx < _match.setResults.length) {
              _match.setResults[idx] = i;
            }
            _match.setWins[i]++;
            final firstTo = _s.firstToWinSets;
            final totalPlayed = _match.setWins[0] + _match.setWins[1];
            _match.gameOver =
                _match.setWins[i] >= firstTo || totalPlayed >= _s.maxSets;
            _match.fouls[0] = 0;
            _match.fouls[1] = 0;
            break;
          }
        }
      } else {
        for (var i = 0; i < 2; i++) {
          if (_match.scores[i] >= _match.targets[i]) {
            _match.gameOver = true;
            _match.fouls[0] = 0;
            _match.fouls[1] = 0;
            break;
          }
        }
      }
      if (_match.gameOver) {
        _applyGameOverFreeze();
      }
    });

    if (!_match.gameOver) {
      final tm = _match.liveTimer;
      if (tm is LiveTimerB) {
        _bReset();
      } else if (tm is LiveTimerA && tm.phase == LiveTimerAPhase.shot) {
        _aShotReset();
      }
      setState(() {});
    }
  }

  void _nextSet() {
    setState(() {
      _match.scores[0] = 0;
      _match.scores[1] = 0;
      _match.fouls[0] = 0;
      _match.fouls[1] = 0;
      _match.currentSet++;
    });
  }

  void _resetMatch() {
    _stopTick();
    setState(() {
      _match.scores[0] = 0;
      _match.scores[1] = 0;
      for (var i = 0; i < _match.setResults.length; i++) {
        _match.setResults[i] = null;
      }
      _match.currentSet = 1;
      _match.setWins[0] = 0;
      _match.setWins[1] = 0;
      _match.fouls[0] = 0;
      _match.fouls[1] = 0;
      _match.turnSwitchCountB = 0;
      _match.gameOver = false;
      _match.liveTimer = _createInitialTimer();
      _startingPlayerB = 0;
      _activeTurnPlayerB = 0;
    });
  }

  void _onFoul(int player) {
    if (_match.gameOver) return;
    setState(() {
      _match.fouls[player]++;
      if (_match.fouls[player] < 3) return;

      final opp = 1 - player;
      _match.scores[opp] = (_match.scores[opp] + 1).clamp(0, 9999);
      _match.fouls[0] = 0;
      _match.fouls[1] = 0;

      if (_s.maxSets > 0) {
        final idx = _match.currentSet - 1;
        if (idx >= 0 && idx < _match.setResults.length) {
          _match.setResults[idx] = opp;
        }
        _match.setWins[opp]++;
        final firstTo = _s.firstToWinSets;
        final totalPlayed = _match.setWins[0] + _match.setWins[1];
        _match.gameOver =
            _match.setWins[opp] >= firstTo || totalPlayed >= _s.maxSets;
      } else if (_match.scores[opp] >= _match.targets[opp]) {
        _match.gameOver = true;
      }
      if (_match.gameOver) {
        _applyGameOverFreeze();
      }
    });

    if (!_match.gameOver) {
      final tm = _match.liveTimer;
      if (tm is LiveTimerB) {
        _bReset();
      } else if (tm is LiveTimerA && tm.phase == LiveTimerAPhase.shot) {
        _aShotReset();
      }
      setState(() {});
    }
  }

  /// 連続ファウルを手動で解消（当該プレイヤーのみ 0 に）
  void _onFoulReset(int player) {
    if (_match.gameOver) return;
    if (_match.fouls[player] == 0) return;
    setState(() {
      _match.fouls[player] = 0;
    });
  }

  String _fmt(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showSets = _s.maxSets > 0;

    return Scaffold(
      appBar: buildAppleGlassAppBar(
        context,
        title: 'スコアボード',
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          color: AppleColors.textOnDark,
          onPressed: () {
            _stopTick();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: Stack(
        children: [
          AppleContentWidth(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                _TimerSection(
                  match: _match,
                  fmt: _fmt,
                  onBStart: _bStart,
                  onBPause: _bPause,
                  onBResume: _bResume,
                  onBReset: _bReset,
                  onBTurnSwitch: _onTurnSwitchB,
                  onAStartPlayer: _aStartPlayer,
                  onAPause: _aPause,
                  onAShotStart: _aShotStart,
                  onAShotPause: _aShotPause,
                  onAShotResume: _aShotResume,
                  onAShotReset: _aShotReset,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      flex: 1,
                      fit: FlexFit.loose,
                      child: _PlayerCard(
                        match: _match,
                        playerIndex: 0,
                        isModeB: _match.liveTimer is LiveTimerB,
                        isStartingPlayerB: _startingPlayerB == 0,
                        isActiveTurnB: _activeTurnPlayerB == 0,
                        onSelectStartingB: () => _setStartingPlayerB(0),
                        onDelta: _onScoreDelta,
                        onFoul: _onFoul,
                        onFoulReset: _onFoulReset,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      flex: 1,
                      fit: FlexFit.loose,
                      child: _PlayerCard(
                        match: _match,
                        playerIndex: 1,
                        isModeB: _match.liveTimer is LiveTimerB,
                        isStartingPlayerB: _startingPlayerB == 1,
                        isActiveTurnB: _activeTurnPlayerB == 1,
                        onSelectStartingB: () => _setStartingPlayerB(1),
                        onDelta: _onScoreDelta,
                        onFoul: _onFoul,
                        onFoulReset: _onFoulReset,
                      ),
                    ),
                  ],
                ),
                if (showSets) ...[
                  const SizedBox(height: 12),
                  _SetSection(
                    match: _match,
                    setup: _s,
                    onNextSet: _nextSet,
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        _stopTick();
                        Navigator.of(context).pop();
                      },
                      child: const Text('設定に戻る'),
                    ),
                    TextButton(
                      onPressed: _resetMatch,
                      style: TextButton.styleFrom(foregroundColor: cs.error),
                      child: const Text('リセット'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_match.gameOver)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: _MatchOverOverlay(
                  setup: _s,
                  match: _match,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MatchOverOverlay extends StatelessWidget {
  const _MatchOverOverlay({
    required this.setup,
    required this.match,
  });

  final MatchSetup setup;
  final MatchState match;

  String _message() {
    if (setup.maxSets > 0) {
      if (match.setWins[0] == match.setWins[1]) {
        return '試合終了';
      }
      final w = match.setWins[0] > match.setWins[1] ? 0 : 1;
      return '${match.names[w]} の勝利！';
    }
    for (var i = 0; i < 2; i++) {
      if (match.scores[i] >= match.targets[i]) {
        return '${match.names[i]} の勝利！';
      }
    }
    return '試合終了';
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final msg = _message();

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0x99000000),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) {
                return Opacity(
                  opacity: t,
                  child: Transform.scale(
                    scale: 0.88 + 0.12 * t,
                    child: child,
                  ),
                );
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppleColors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: AppleColors.cardShadow,
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '🏆',
                        style: tt.displaySmall?.copyWith(height: 1),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '試合終了',
                        style: tt.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppleColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        msg,
                        textAlign: TextAlign.center,
                        style: tt.titleMedium?.copyWith(
                          color: AppleColors.appleBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimerSection extends StatelessWidget {
  const _TimerSection({
    required this.match,
    required this.fmt,
    required this.onBStart,
    required this.onBPause,
    required this.onBResume,
    required this.onBReset,
    required this.onBTurnSwitch,
    required this.onAStartPlayer,
    required this.onAPause,
    required this.onAShotStart,
    required this.onAShotPause,
    required this.onAShotResume,
    required this.onAShotReset,
  });

  final MatchState match;
  final String Function(int) fmt;
  final VoidCallback onBStart;
  final VoidCallback onBPause;
  final VoidCallback onBResume;
  final VoidCallback onBReset;
  final VoidCallback onBTurnSwitch;
  final void Function(int player) onAStartPlayer;
  final VoidCallback onAPause;
  final VoidCallback onAShotStart;
  final VoidCallback onAShotPause;
  final VoidCallback onAShotResume;
  final VoidCallback onAShotReset;

  @override
  Widget build(BuildContext context) {
    final t = match.liveTimer;

    if (t is LiveTimerC) {
      return _timerCard(
        context,
        badge: '制限なし',
        mainText: '∞',
        mainStyle: Theme.of(context).textTheme.displayMedium?.copyWith(
              color: AppleColors.textPrimary,
            ),
        sub: '',
        actions: const [],
      );
    }

    if (t is LiveTimerB) {
      final r = t.remain;
      Color? mainColor;
      if (t.paused) {
        mainColor = AppleColors.glyphGraySecondary;
      } else if (r == 0) {
        mainColor = AppleColors.systemRed;
      } else if (r <= 10) {
        mainColor = AppleColors.systemOrange;
      }

      final line1 = t.paused ? '一時停止中' : (r == 0 ? '時間切れ！' : 'カウント中');
      final sub = '$line1\n攻守交替 ${match.turnSwitchCountB}回';

      return _timerCard(
        context,
        badge: '1ショットクロック — ${t.shotSec}秒',
        mainText: fmt(r),
        mainStyle: Theme.of(context).textTheme.displayMedium?.copyWith(
              color: mainColor,
              letterSpacing: 2,
            ),
        sub: sub,
        helperText: '攻守交替: 撞き番が交代した時に使用します。',
        actions: [
          if (t.paused) ...[
            FilledButton(
              onPressed: onBResume,
              child: const Text('再開'),
            ),
            OutlinedButton(
                onPressed: onBReset, child: const Text('リセット（相手操作）')),
            OutlinedButton(
              onPressed: match.gameOver ? null : onBTurnSwitch,
              child: const Text('攻守交替'),
            ),
          ] else if (!t.running) ...[
            FilledButton(
              onPressed: onBStart,
              child: const Text('スタート'),
            ),
            OutlinedButton(
                onPressed: onBReset, child: const Text('リセット（相手操作）')),
            OutlinedButton(
              onPressed: match.gameOver ? null : onBTurnSwitch,
              child: const Text('攻守交替'),
            ),
          ] else ...[
            FilledButton(
              onPressed: onBPause,
              style: FilledButton.styleFrom(
                backgroundColor: AppleColors.nearBlack,
                foregroundColor: AppleColors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('一時停止'),
            ),
            OutlinedButton(
                onPressed: onBReset, child: const Text('リセット（相手操作）')),
            OutlinedButton(
              onPressed: match.gameOver ? null : onBTurnSwitch,
              child: const Text('攻守交替'),
            ),
          ],
        ],
      );
    }

    if (t is LiveTimerA) {
      if (t.phase == LiveTimerAPhase.total) {
        final ap = t.activePlayer;
        final rActive = t.remain[ap];
        final r0 = t.remain[0];
        final r1 = t.remain[1];
        final sub = t.running
            ? '${match.names[ap]} の持ち時間カウント中　|　${match.names[0]}: ${fmt(r0)}　${match.names[1]}: ${fmt(r1)}'
            : '${match.names[0]}: ${fmt(r0)}　${match.names[1]}: ${fmt(r1)}';

        return _timerCard(
          context,
          badge: '持ち時間モード',
          mainText: fmt(rActive),
          mainStyle: Theme.of(context).textTheme.displayMedium?.copyWith(
                color: t.running && rActive <= 30
                    ? AppleColors.systemOrange
                    : null,
                letterSpacing: 2,
              ),
          sub: sub,
          actions: [
            FilledButton(
              onPressed: () => onAStartPlayer(0),
              child: Text(match.names[0]),
            ),
            FilledButton(
              onPressed: () => onAStartPlayer(1),
              child: Text(match.names[1]),
            ),
            FilledButton(
              onPressed: onAPause,
              style: FilledButton.styleFrom(
                backgroundColor: AppleColors.nearBlack,
                foregroundColor: AppleColors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('一時停止'),
            ),
          ],
        );
      }

      // shot phase
      final r = t.shotRemain;
      Color? mainColor;
      if (t.paused) {
        mainColor = AppleColors.glyphGraySecondary;
      } else if (r == 0) {
        mainColor = AppleColors.systemRed;
      } else if (r <= 10) {
        mainColor = AppleColors.systemOrange;
      }

      final sub = t.paused ? '一時停止中' : (r == 0 ? '時間切れ！' : 'カウント中');

      return _timerCard(
        context,
        badge: '持ち時間終了 → 1ショット ${t.shotSec}秒',
        mainText: fmt(r),
        mainStyle: Theme.of(context).textTheme.displayMedium?.copyWith(
              color: mainColor,
              letterSpacing: 2,
            ),
        sub: sub,
        actions: [
          if (t.paused) ...[
            FilledButton(
              onPressed: onAShotResume,
              child: const Text('再開'),
            ),
            OutlinedButton(
                onPressed: onAShotReset, child: const Text('リセット（相手操作）')),
          ] else if (!t.running) ...[
            FilledButton(
              onPressed: onAShotStart,
              child: const Text('スタート'),
            ),
            OutlinedButton(
                onPressed: onAShotReset, child: const Text('リセット（相手操作）')),
          ] else ...[
            FilledButton(
              onPressed: onAShotPause,
              style: FilledButton.styleFrom(
                backgroundColor: AppleColors.nearBlack,
                foregroundColor: AppleColors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('一時停止'),
            ),
            OutlinedButton(
                onPressed: onAShotReset, child: const Text('リセット（相手操作）')),
          ],
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _timerCard(
    BuildContext context, {
    required String badge,
    required String mainText,
    required TextStyle? mainStyle,
    required String sub,
    String? helperText,
    required List<Widget> actions,
  }) {
    final tt = Theme.of(context).textTheme;
    return AppleCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: AppleColors.separator),
              borderRadius: BorderRadius.circular(4),
              color: AppleColors.lightGray,
            ),
            child: Text(
              badge,
              style: tt.labelLarge
                  ?.copyWith(color: AppleColors.glyphGraySecondary),
            ),
          ),
          const SizedBox(height: 12),
          Text(mainText, style: mainStyle),
          const SizedBox(height: 6),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: tt.labelLarge
                ?.copyWith(color: AppleColors.glyphGraySecondary, height: 1.35),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: actions,
            ),
            if (helperText != null) ...[
              const SizedBox(height: 8),
              Text(
                helperText,
                textAlign: TextAlign.center,
                style: tt.labelMedium?.copyWith(
                  color: AppleColors.glyphGraySecondary,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.match,
    required this.playerIndex,
    required this.isModeB,
    required this.isStartingPlayerB,
    required this.isActiveTurnB,
    required this.onSelectStartingB,
    required this.onDelta,
    required this.onFoul,
    required this.onFoulReset,
  });

  final MatchState match;
  final int playerIndex;
  final bool isModeB;
  final bool isStartingPlayerB;
  final bool isActiveTurnB;
  final VoidCallback onSelectStartingB;
  final void Function(int player, int delta) onDelta;
  final void Function(int player) onFoul;
  final void Function(int player) onFoulReset;

  @override
  Widget build(BuildContext context) {
    final wonThisSet = _playerWonCurrentSetVisual(match, playerIndex);

    final tt = Theme.of(context).textTheme;
    final fc = match.fouls[playerIndex];

    return AppleCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      backgroundColor:
          wonThisSet ? AppleColors.systemGreen.withValues(alpha: 0.1) : null,
      borderColor: wonThisSet
          ? AppleColors.systemGreen.withValues(alpha: 0.45)
          : (isModeB && isActiveTurnB ? AppleColors.appleBlue : null),
      borderWidth: isModeB && isActiveTurnB ? 2 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (wonThisSet)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppleColors.systemGreen.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'セット取得！',
                style: tt.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppleColors.systemGreen,
                ),
              ),
            ),
          Text(
            match.names[playerIndex],
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (isModeB) ...[
            const SizedBox(height: 2),
            TextButton(
              onPressed: onSelectStartingB,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: isStartingPlayerB
                    ? AppleColors.appleBlue
                    : AppleColors.glyphGraySecondary,
              ),
              child: Text(
                '先攻',
                style: tt.labelLarge?.copyWith(
                  fontWeight:
                      isStartingPlayerB ? FontWeight.w700 : FontWeight.w400,
                  color: isStartingPlayerB
                      ? AppleColors.appleBlue
                      : AppleColors.glyphGraySecondary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              final filled = fc > i;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '○',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    height: 1,
                    color: filled
                        ? AppleColors.systemOrange
                        : AppleColors.separator,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: match.gameOver ? null : () => onFoul(playerIndex),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'ファウル',
                  style: tt.labelLarge?.copyWith(
                    color: match.gameOver
                        ? AppleColors.glyphGraySecondary
                        : AppleColors.appleBlue,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Text(
                  '/',
                  style: tt.labelLarge?.copyWith(
                    color: AppleColors.glyphGraySecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: match.gameOver || fc == 0
                    ? null
                    : () => onFoulReset(playerIndex),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'リセット',
                  style: tt.labelLarge?.copyWith(
                    color: match.gameOver || fc == 0
                        ? AppleColors.glyphGraySecondary
                        : AppleColors.appleBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            match.ranks[playerIndex].labelJa,
            style: tt.labelLarge?.copyWith(color: AppleColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            '${match.scores[playerIndex]}',
            style: tt.displayLarge?.copyWith(
              fontSize: 56,
              fontWeight: FontWeight.w600,
              height: 1.05,
              color: wonThisSet
                  ? AppleColors.systemGreen
                  : AppleColors.textPrimary,
            ),
          ),
          Text(
            '/ ${match.targets[playerIndex]} 点',
            style:
                tt.labelLarge?.copyWith(color: AppleColors.glyphGraySecondary),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _RoundBtn(
                label: '−',
                onPressed:
                    match.gameOver ? null : () => onDelta(playerIndex, -1),
              ),
              const SizedBox(width: 10),
              _RoundBtn(
                label: '＋',
                filled: true,
                onPressed:
                    match.gameOver ? null : () => onDelta(playerIndex, 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

bool _playerWonCurrentSetVisual(MatchState match, int playerIndex) {
  if (match.setup.maxSets == 0) return false;
  final idx = match.currentSet - 1;
  if (idx < 0 || idx >= match.setResults.length) return false;
  return match.setResults[idx] == playerIndex;
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? AppleColors.appleBlue : AppleColors.lightGray,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: filled ? AppleColors.white : AppleColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SetSection extends StatelessWidget {
  const _SetSection({
    required this.match,
    required this.setup,
    required this.onNextSet,
  });

  final MatchState match;
  final MatchSetup setup;
  final VoidCallback onNextSet;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final ms = setup.maxSets;

    String info;
    if (match.gameOver) {
      final w = match.setWins[0] > match.setWins[1] ? 0 : 1;
      if (match.setWins[0] == match.setWins[1]) {
        info = '引き分け';
      } else {
        info = '🏆 ${match.names[w]} の勝利！';
      }
    } else {
      final pending = match.setResults.length >= match.currentSet &&
          match.setResults[match.currentSet - 1] != null;
      if (pending) {
        info = '第${match.currentSet}セット終了';
      } else {
        info = '第${match.currentSet}セット';
      }
    }

    final showNext = !match.gameOver &&
        match.setResults.length >= match.currentSet &&
        match.setResults[match.currentSet - 1] != null;

    return AppleCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'セット記録',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                info,
                style:
                    tt.labelLarge?.copyWith(color: AppleColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SetGrid(match: match, maxSets: ms),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: tt.bodyLarge,
                    children: [
                      TextSpan(text: '${match.names[0]} '),
                      TextSpan(
                        text: '${match.setWins[0]}',
                        style: TextStyle(
                          color: AppleColors.systemGreen,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const TextSpan(text: ' — '),
                      TextSpan(
                        text: '${match.setWins[1]}',
                        style: TextStyle(
                          color: AppleColors.systemRed,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                      ),
                      TextSpan(text: ' ${match.names[1]}'),
                    ],
                  ),
                ),
              ),
              if (showNext)
                FilledButton(
                  onPressed: onNextSet,
                  child: const Text('次のセットへ →'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SetGrid extends StatelessWidget {
  const _SetGrid({required this.match, required this.maxSets});

  final MatchState match;
  final int maxSets;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: {
        0: const FixedColumnWidth(56),
        for (var i = 0; i < maxSets; i++) i + 1: const FlexColumnWidth(),
      },
      children: [
        TableRow(
          children: [
            const SizedBox(),
            for (var s = 1; s <= maxSets; s++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'G$s',
                  textAlign: TextAlign.center,
                  style: tt.labelLarge
                      ?.copyWith(color: AppleColors.glyphGraySecondary),
                ),
              ),
          ],
        ),
        for (var p = 0; p < 2; p++)
          TableRow(
            children: [
              Text(
                _shortNameJa(match.names[p]),
                style:
                    tt.labelLarge?.copyWith(color: AppleColors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
              for (var s = 1; s <= maxSets; s++)
                _SetCell(
                  match: match,
                  player: p,
                  setIndex: s - 1,
                  maxSets: maxSets,
                ),
            ],
          ),
      ],
    );
  }
}

String _shortNameJa(String n) {
  if (n.length <= 5) return n;
  return '${n.substring(0, n.length >= 4 ? 4 : n.length)}…';
}

class _SetCell extends StatelessWidget {
  const _SetCell({
    required this.match,
    required this.player,
    required this.setIndex,
    required this.maxSets,
  });

  final MatchState match;
  final int player;
  final int setIndex;
  final int maxSets;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final r =
        setIndex < match.setResults.length ? match.setResults[setIndex] : null;
    final isCurrent =
        setIndex == match.currentSet - 1 && !match.gameOver && r == null;

    String text = '';
    Color? bg;
    Color? border;
    Color? fg;

    if (r != null) {
      if (r == player) {
        text = '○';
        bg = AppleColors.systemGreen.withValues(alpha: 0.12);
        border = AppleColors.systemGreen.withValues(alpha: 0.55);
        fg = AppleColors.systemGreen;
      } else {
        text = '×';
        bg = AppleColors.systemRed.withValues(alpha: 0.08);
        border = AppleColors.systemRed.withValues(alpha: 0.45);
        fg = AppleColors.systemRed;
      }
    } else if (isCurrent) {
      text = '…';
      border = AppleColors.appleBlue;
      bg = AppleColors.appleBlue.withValues(alpha: 0.1);
    }

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Container(
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg ?? AppleColors.lightGray,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: border ?? AppleColors.separator,
            width: isCurrent ? 1.5 : 0.5,
          ),
        ),
        child: Text(
          text,
          style: tt.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: fg ?? AppleColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
