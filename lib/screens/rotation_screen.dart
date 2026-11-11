import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/rotation_game.dart';
import '../theme/apple_theme.dart';

class RotationArgs {
  const RotationArgs({required this.p1Name, required this.p2Name});

  final String p1Name;
  final String p2Name;
}

class RotationScreen extends StatefulWidget {
  const RotationScreen({super.key, required this.p1Name, required this.p2Name});

  final String p1Name;
  final String p2Name;

  @override
  State<RotationScreen> createState() => _RotationScreenState();
}

class _RotationScreenState extends State<RotationScreen> {
  final RotationGame _game = RotationGame();

  List<String> get _names => [widget.p1Name, widget.p2Name];

  void _act(VoidCallback action) {
    HapticFeedback.selectionClick();
    setState(action);
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
    if (ok == true) setState(_game.reset);
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
                      onPressed: () => _act(_game.breakFailed),
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
                          onPressed:
                              _game.canUndo ? () => _act(_game.undo) : null,
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

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final need = (target - score).clamp(0, 9999);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isShooter ? AppleColors.appleBlue : Colors.transparent,
          width: 2.5,
        ),
      ),
      child: AppleCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onTapName,
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 26,
                child: Row(
                  children: [
                    if (isShooter)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.play_arrow_rounded,
                            size: 18, color: AppleColors.appleBlue),
                      ),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            // バッジの有無で左右の高さがずれないよう、行の高さを固定する
            SizedBox(
              height: 22,
              child: Row(
                children: [
                  if (isBreaker) const _Badge(label: 'ブレイク'),
                  if (isBreaker && fouls > 0) const SizedBox(width: 4),
                  if (fouls > 0)
                    Flexible(
                      child: _Badge(
                        label: 'ファウル $fouls',
                        color: AppleColors.systemOrange,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '$score',
                style: tt.displaySmall?.copyWith(
                  color: AppleColors.appleBlue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            InkWell(
              onTap: onTapTarget,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '/ $target点',
                      style: tt.bodyMedium?.copyWith(
                        color: AppleColors.glyphGraySecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.edit,
                        size: 14, color: AppleColors.glyphGraySecondary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'あと $need点 ・ 今ラック $rackScore点',
              style:
                  tt.bodySmall?.copyWith(color: AppleColors.glyphGraySecondary),
            ),
          ],
        ),
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
