import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/rotation_game.dart';
import '../models/scoreboard_models.dart';
import '../models/shot_clock.dart';
import '../theme/apple_theme.dart';

class RotationArgs {
  const RotationArgs({
    required this.p1Name,
    required this.p2Name,
    this.p1Rank,
    this.p2Rank,
  });

  final String p1Name;
  final String p2Name;
  final PlayerRank? p1Rank;
  final PlayerRank? p2Rank;
}

class RotationScreen extends StatefulWidget {
  const RotationScreen({
    super.key,
    required this.p1Name,
    required this.p2Name,
    this.p1Rank,
    this.p2Rank,
  });

  final String p1Name;
  final String p2Name;
  final PlayerRank? p1Rank;
  final PlayerRank? p2Rank;

  @override
  State<RotationScreen> createState() => _RotationScreenState();
}

/// クラス別のエクステンション回数の初期値（A級以上3回、それ以外2回）。
int _defaultExtensionsFor(PlayerRank? rank) =>
    rank == PlayerRank.a || rank == PlayerRank.sa ? 3 : 2;

class _RotationScreenState extends State<RotationScreen> {
  late final RotationGame _game = RotationGame(
    extensions: [
      _defaultExtensionsFor(widget.p1Rank),
      _defaultExtensionsFor(widget.p2Rank),
    ],
  );
  final ShotClock _clock = ShotClock();
  Timer? _ticker;

  List<String> get _names => [widget.p1Name, widget.p2Name];

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// 入力（球・ミス・ファウル）のあと、ショットクロックを次のショット用に戻して計測する。
  /// ラックが終わった・試合が終わった・[stopClock] のときは止めて待機。
  void _act(VoidCallback action, {bool stopClock = false}) {
    HapticFeedback.selectionClick();
    final rackBefore = _game.rackNumber;
    setState(() {
      action();
      if (stopClock || _game.winner != null || _game.rackNumber != rackBefore) {
        _clock.stopAndReset();
      } else {
        _clock.resetAndRun();
      }
    });
    _syncTicker();
  }

  void _undo() {
    HapticFeedback.selectionClick();
    setState(() {
      _game.undo();
      _clock.running && _game.winner == null
          ? _clock.resetAndRun()
          : _clock.stopAndReset();
    });
    _syncTicker();
  }

  void _toggleClock() {
    setState(() => _clock.running ? _clock.pause() : _clock.start());
    _syncTicker();
  }

  void _useExtension() {
    setState(() {
      if (_game.useExtension()) _clock.extend();
    });
    _syncTicker();
  }

  void _syncTicker() {
    if (_clock.running && _game.winner == null) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _onTick() {
    if (!mounted) return;
    String? message;
    setState(() {
      switch (_clock.tick()) {
        case ShotClockEvent.none:
          break;
        case ShotClockEvent.alert:
          SystemSound.play(SystemSoundType.alert);
          HapticFeedback.heavyImpact();
        case ShotClockEvent.countdown:
          SystemSound.play(SystemSoundType.click);
          HapticFeedback.mediumImpact();
        case ShotClockEvent.expired:
          HapticFeedback.vibrate();
          final player = _names[_game.shooter];
          if (_game.useExtension()) {
            // エクステンションが残っていれば自動延長
            _clock.extend();
            message =
                '$player：エクステンション自動使用（残り${_game.extensionsLeft[_game.shooter]}回）';
          } else {
            // 残っていなければ時間切れファウル → 相手の手番で計測再開
            _game.foul();
            _clock.resetAndRun();
            message = '$player：時間切れファウル';
          }
      }
    });
    _syncTicker();
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message!),
            duration: const Duration(seconds: 3),
          ),
        );
    }
  }

  Future<void> _editShotSec() async {
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('ショットクロック（1ショット）'),
        children: [
          for (final sec in const [30, 35, 40, 45, 50, 60])
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(sec),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: sec == _clock.shotSec
                        ? const Icon(Icons.check, size: 18)
                        : null,
                  ),
                  Text('$sec秒'),
                ],
              ),
            ),
        ],
      ),
    );
    if (result == null) return;
    setState(() => _clock.setShotSec(result));
  }

  Future<void> _editExtensions(int player) async {
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('${_names[player]} のエクステンション回数'),
        children: [
          for (var n = 0; n <= RotationGame.maxExtensions; n++)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(n),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: n == _game.extensionLimits[player]
                        ? const Icon(Icons.check, size: 18)
                        : null,
                  ),
                  Text(
                    n == 2
                        ? '2回（B級）'
                        : n == 3
                            ? '3回（A級）'
                            : n == 0
                                ? 'なし'
                                : '$n回',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (result == null) return;
    setState(() => _game.setExtensionLimit(player, result));
  }

  Future<void> _editTarget(int player) async {
    final controller = TextEditingController(text: '${_game.targets[player]}');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${_names[player]} の目標点'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(suffixText: '点'),
          onSubmitted: (v) => Navigator.of(ctx).pop(int.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(int.tryParse(controller.text)),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result <= 0) return;
    setState(() => _game.setTarget(player, result));
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('試合をリセットしますか？'),
        content: const Text('得点とラック履歴がすべて消えます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('リセット'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _game.reset();
      _clock.stopAndReset();
    });
    _syncTicker();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final winner = _game.winner;
    final lowest = _game.lowestBall;

    return Scaffold(
      appBar: buildAppleGlassAppBar(
        context,
        title: 'ローテーション',
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          color: AppleColors.textOnDark,
          onPressed: () {
            Navigator.of(context)
                .pushNamedAndRemoveUntil('/setup', (route) => false);
          },
        ),
      ),
      body: AppleContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (winner != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppleCard(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  child: Text(
                    '${_names[winner]} の勝利（${_game.scores[0]} - ${_game.scores[1]}）',
                    textAlign: TextAlign.center,
                    style: tt.titleMedium?.copyWith(
                      color: AppleColors.appleBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            // 左右のパネルは各行の高さを固定しているので常に同じ高さになる
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var p = 0; p < 2; p++) ...[
                  if (p == 1) const SizedBox(width: 10),
                  Expanded(
                    child: _PlayerPanel(
                      name: _names[p],
                      score: _game.scores[p],
                      target: _game.targets[p],
                      rackScore: _game.currentRackScores[p],
                      fouls: _game.fouls[p],
                      isShooter: winner == null && _game.shooter == p,
                      isBreaker: _game.breaker == p,
                      onTapName: _game.isStarted
                          ? null
                          : () => setState(() => _game.setBreaker(p)),
                      onTapTarget: () => _editTarget(p),
                      extensionsLeft: _game.extensionsLeft[p],
                      extensionLimit: _game.extensionLimits[p],
                      onTapExtensions: () => _editExtensions(p),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            AppleCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        'ラック ${_game.rackNumber}',
                        style: tt.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Text(
                        lowest == null
                            ? '残り ${_game.remainingPoints}点'
                            : '的球 $lowest番 ・ 残り ${_game.remainingPoints}点',
                        style: tt.bodySmall?.copyWith(
                          color: AppleColors.glyphGraySecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    winner == null
                        ? '${_names[_game.shooter]} の手番：入れた球をタップ'
                        : '試合終了',
                    style: tt.bodySmall
                        ?.copyWith(color: AppleColors.glyphGraySecondary),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, c) {
                      const cols = 5;
                      const gap = 10.0;
                      final size = ((c.maxWidth - gap * (cols - 1)) / cols)
                          .clamp(36.0, 64.0);
                      return Wrap(
                        alignment: WrapAlignment.center,
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (var n = 1; n <= RotationGame.ballCount; n++)
                            _RotationBall(
                              number: n,
                              size: size,
                              ownerLabel: _game.pocketed.containsKey(n)
                                  ? _initial(_names[_game.pocketed[n]!])
                                  : null,
                              isLowest: n == lowest,
                              onTap: winner != null ||
                                      _game.pocketed.containsKey(n)
                                  ? null
                                  : () => _act(() => _game.pocket(n)),
                            ),
                        ],
                      );
                    },
                  ),
                  if (_game.canBreakFail) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _act(_game.breakFailed, stopClock: true),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(40),
                        foregroundColor: AppleColors.systemOrange,
                        side: const BorderSide(color: AppleColors.systemOrange),
                      ),
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: Text(
                        'キッチンに出せず → ${_names[1 - _game.breaker]} がブレイク',
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed:
                              winner != null ? null : () => _act(_game.miss),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('ミス・交代'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed:
                              winner != null ? null : () => _act(_game.foul),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            backgroundColor: AppleColors.systemOrange,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('ファウル'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _game.canUndo ? _undo : null,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          icon: const Icon(Icons.undo, size: 18),
                          label: const Text('取消'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _ShotClockCard(
              clock: _clock,
              shooterName: _names[_game.shooter],
              extensionsLeft: _game.extensionsLeft[_game.shooter],
              enabled: winner == null,
              onToggle: _toggleClock,
              onExtension: _useExtension,
              onSettings: _editShotSec,
            ),
            if (_game.rackHistory.isNotEmpty) ...[
              const SizedBox(height: 12),
              AppleCard(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'ラック履歴',
                      style:
                          tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    for (var i = 0; i < _game.rackHistory.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 72,
                              child: Text('ラック ${i + 1}', style: tt.bodySmall),
                            ),
                            Expanded(
                              child: Text(
                                '${_game.rackHistory[i][0]} - ${_game.rackHistory[i][1]}',
                                textAlign: TextAlign.center,
                                style: tt.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                '※ 試合開始前は名前をタップで先攻ブレイクを切り替え。\n'
                '※ ブレイクで球をキッチンに出せなかったときは、ラック開始直後に出るボタンで交代。\n'
                '※ 目標点をタップで変更（ハンデ戦にも対応）。\n'
                '※ ファウル中に入った球はタップせず台に戻してください。',
                style: tt.bodySmall
                    ?.copyWith(color: AppleColors.glyphGraySecondary),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _confirmReset,
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('リセット'),
              ),
            ),
            AppleCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ローテーションルール',
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppleColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '● 1〜15番の15球を使用。入れた球の番号がそのまま得点（1ラック合計120点）。\n'
                    '● 手球は常に台上の最小番号の球に最初に当てる。正しく当てれば、どの球が入っても得点。\n'
                    '● 球を入れ続ける限り撞き続けられ、入らなければ交代。\n'
                    '● ファウル時に入った球は得点にならず台に戻す。相手はフリーボール（手球を自由に置ける）。\n'
                    '● ショットクロックは1ショット45秒（設定で変更可）。残り15秒でアラート、5秒前からカウントダウン。\n'
                    '● エクステンションは試合を通して選手ごとに設定した回数（B級2回・A級3回）。残っていれば時間切れ時に自動で延長し、使い切っていれば時間切れはファウル。\n'
                    '● 15球すべて入ったら次のラック。ブレイクは勝者ブレイク（そのラックで最後の球を入れた人。15番が途中でフロックで入っていたら、最後に入れた球の人）。\n'
                    '● ブレイクで球をキッチンに出せなかった場合のみ、ブレイク権が相手に移る。\n'
                    '● 先に目標点（デフォルト120点）に到達した方の勝ち。',
                    style: tt.bodySmall?.copyWith(
                      color: AppleColors.glyphGraySecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _initial(String name) {
    final t = name.trim();
    return t.isEmpty ? '?' : String.fromCharCode(t.runes.first);
  }
}

class _PlayerPanel extends StatelessWidget {
  const _PlayerPanel({
    required this.name,
    required this.score,
    required this.target,
    required this.rackScore,
    required this.fouls,
    required this.isShooter,
    required this.isBreaker,
    required this.onTapName,
    required this.onTapTarget,
    required this.extensionsLeft,
    required this.extensionLimit,
    required this.onTapExtensions,
  });

  final String name;
  final int score;
  final int target;
  final int rackScore;
  final int fouls;
  final bool isShooter;
  final bool isBreaker;
  final VoidCallback? onTapName;
  final VoidCallback onTapTarget;
  final int extensionsLeft;
  final int extensionLimit;
  final VoidCallback onTapExtensions;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final need = (target - score).clamp(0, 9999);
    final secondary = tt.bodySmall?.copyWith(
      color: AppleColors.glyphGraySecondary,
      fontSize: 11,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 名前（カードの上・中央）。試合開始前はタップで先攻ブレイク切替。
        InkWell(
          onTap: onTapName,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 30,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isShooter)
                  const Icon(
                    Icons.play_arrow_rounded,
                    size: 20,
                    color: AppleColors.appleBlue,
                  ),
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isShooter
                          ? AppleColors.appleBlue
                          : AppleColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isShooter ? AppleColors.appleBlue : Colors.transparent,
              width: 3,
            ),
          ),
          child: AppleCard(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ブレイクバッジ（右上）。有無で高さが変わらないよう固定。
                SizedBox(
                  height: 20,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: isBreaker ? const _Badge(label: 'ブレイク') : null,
                  ),
                ),
                // 点数（特大）＋ 目標点
                SizedBox(
                  height: 120,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$score',
                          style: const TextStyle(
                            fontSize: 120,
                            height: 1,
                            fontWeight: FontWeight.w800,
                            color: AppleColors.textPrimary,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: onTapTarget,
                          child: Text(
                            '/$target',
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                              color: AppleColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // 左下：ファウル  右下：残り点・延長
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _Badge(
                          label: 'ファウル',
                          color: AppleColors.systemOrange,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < 3; i++)
                              Container(
                                width: 18,
                                height: 18,
                                margin: const EdgeInsets.only(right: 3),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: i < fouls
                                      ? AppleColors.textPrimary
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: AppleColors.textPrimary,
                                    width: 1.4,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 「あと◯点」は試合中に一番よく見るので大きく
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'あと ',
                                    style: tt.bodyMedium?.copyWith(
                                      color: AppleColors.glyphGraySecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  TextSpan(
                                    text: '$need',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      height: 1.1,
                                      fontWeight: FontWeight.w800,
                                      color: AppleColors.textPrimary,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  TextSpan(
                                    text: '点',
                                    style: tt.bodyMedium?.copyWith(
                                      color: AppleColors.glyphGraySecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                            ),
                          ),
                          Text(
                            '今ラック $rackScore点',
                            maxLines: 1,
                            style: secondary,
                          ),
                          const SizedBox(height: 2),
                          InkWell(
                            onTap: onTapExtensions,
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              height: 20,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '延長',
                                    style: secondary?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  if (extensionLimit == 0)
                                    Text('なし', style: secondary)
                                  else
                                    for (var i = 0; i < extensionLimit; i++)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 2),
                                        child: Icon(
                                          i < extensionsLeft
                                              ? Icons.circle
                                              : Icons.circle_outlined,
                                          size: 10,
                                          color: i < extensionsLeft
                                              ? AppleColors.systemGreen
                                              : AppleColors.separator,
                                        ),
                                      ),
                                  const SizedBox(width: 2),
                                  const Icon(
                                    Icons.edit,
                                    size: 12,
                                    color: AppleColors.glyphGraySecondary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ShotClockCard extends StatelessWidget {
  const _ShotClockCard({
    required this.clock,
    required this.shooterName,
    required this.extensionsLeft,
    required this.enabled,
    required this.onToggle,
    required this.onExtension,
    required this.onSettings,
  });

  final ShotClock clock;
  final String shooterName;
  final int extensionsLeft;
  final bool enabled;
  final VoidCallback onToggle;
  final VoidCallback onExtension;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final remain = clock.remaining;
    final Color color;
    if (remain <= ShotClock.countdownFrom) {
      color = AppleColors.systemRed;
    } else if (remain <= ShotClock.alertAt) {
      color = AppleColors.systemOrange;
    } else {
      color = AppleColors.appleBlue;
    }
    final progress =
        clock.shotSec == 0 ? 0.0 : (remain / clock.shotSec).clamp(0.0, 1.0);
    const ringSize = 132.0;

    return AppleCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
      backgroundColor: remain <= ShotClock.countdownFrom && clock.running
          ? AppleColors.systemRed.withValues(alpha: 0.08)
          : null,
      child: Row(
        children: [
          // 円形のショットクロック（残り秒を大きく）
          SizedBox(
            width: ringSize,
            height: ringSize,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF2B2B2E),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(7),
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 12,
                    color: color,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                Center(
                  child: Text(
                    '$remain',
                    style: const TextStyle(
                      fontSize: 58,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        clock.running ? '$shooterName の持ち時間' : 'ショットクロック 停止中',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: AppleColors.glyphGraySecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '秒数の設定',
                      visualDensity: VisualDensity.compact,
                      onPressed: onSettings,
                      icon: const Icon(Icons.settings, size: 20),
                      color: AppleColors.glyphGraySecondary,
                    ),
                  ],
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    color: color,
                    backgroundColor: AppleColors.lightGray,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: enabled ? onToggle : null,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  icon: Icon(
                    clock.running ? Icons.pause : Icons.play_arrow,
                    size: 20,
                  ),
                  label: Text(
                    clock.running ? '一時停止' : '開始',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: enabled && extensionsLeft > 0 ? onExtension : null,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    foregroundColor: AppleColors.systemGreen,
                  ),
                  child: Text(
                    '延長（残り$extensionsLeft）',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.color = AppleColors.appleBlue});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _RotationBall extends StatelessWidget {
  const _RotationBall({
    required this.number,
    required this.size,
    required this.ownerLabel,
    required this.isLowest,
    required this.onTap,
  });

  final int number;
  final double size;
  final String? ownerLabel;
  final bool isLowest;
  final VoidCallback? onTap;

  static const _colors = <Color>[
    Color(0xFFF4C20D), // 1 yellow
    Color(0xFF1E88E5), // 2 blue
    Color(0xFFC62828), // 3 red
    Color(0xFF6A1B9A), // 4 purple
    Color(0xFFEF6C00), // 5 orange
    Color(0xFF2E7D32), // 6 green
    Color(0xFF8D2A1E), // 7 maroon
    Color(0xFF212121), // 8 black
  ];

  @override
  Widget build(BuildContext context) {
    final pocketed = ownerLabel != null;
    final base = _colors[(number - 1) % 8];
    final stripe = number >= 9;
    final fontSize = size * 0.34;

    Widget ball = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: stripe ? Colors.white : base,
        border: isLowest
            ? Border.all(color: AppleColors.appleBlue, width: 3)
            : null,
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.25),
            blurRadius: 3,
            offset: Offset(0, 1.5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (stripe) Container(height: size * 0.56, color: base),
          Container(
            width: size * 0.5,
            height: size * 0.5,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w800,
                fontSize: fontSize,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );

    if (pocketed) {
      ball = Stack(
        alignment: Alignment.center,
        children: [
          Opacity(opacity: 0.22, child: ball),
          Text(
            ownerLabel!,
            style: TextStyle(
              fontSize: size * 0.36,
              fontWeight: FontWeight.w800,
              color: AppleColors.glyphGraySecondary,
            ),
          ),
        ],
      );
    }

    return Semantics(
      button: onTap != null,
      label: '$number番${pocketed ? '（ポケット済み）' : ''}',
      child: GestureDetector(onTap: onTap, child: ball),
    );
  }
}
