import 'package:flutter/material.dart';

import '../models/elo_rating_models.dart';
import '../models/scoreboard_models.dart';
import '../services/elo_rating_repository.dart';
import '../theme/apple_theme.dart';

class CountNineArgs {
  const CountNineArgs({
    required this.p1Name,
    required this.p2Name,
    required this.p1Rank,
    required this.p2Rank,
    required this.p1UserKey,
    required this.p2OpponentKey,
  });

  final String p1Name;
  final String p2Name;
  final PlayerRank p1Rank;
  final PlayerRank p2Rank;
  final String p1UserKey;
  final String p2OpponentKey;
}

class CountNineScreen extends StatefulWidget {
  const CountNineScreen({
    super.key,
    required this.p1Name,
    required this.p2Name,
    required this.p1Rank,
    required this.p2Rank,
    required this.p1UserKey,
    required this.p2OpponentKey,
  });

  final String p1Name;
  final String p2Name;
  final PlayerRank p1Rank;
  final PlayerRank p2Rank;
  final String p1UserKey;
  final String p2OpponentKey;

  @override
  State<CountNineScreen> createState() => _CountNineScreenState();
}

class _CountNineScreenState extends State<CountNineScreen> {
  final _eloRepo = EloRatingRepository();
  late final List<int> _targets = [
    _targetForRank(widget.p1Rank),
    _targetForRank(widget.p2Rank),
  ];
  final List<int> _scores = [0, 0];
  final List<int> _fouls = [0, 0];
  final Set<int> _disabledBalls = <int>{};
  final Set<int> _invalidBalls = <int>{};
  final Map<int, int> _ballOwner = <int, int>{};
  int _breakStarter = 0;
  int? _winner;
  bool _eloRecorded = false;

  @override
  void initState() {
    super.initState();
    _eloRepo.ensureLoaded();
  }

  bool get _canChangeStarter => _scores[0] == 0 && _scores[1] == 0;

  static int _targetForRank(PlayerRank rank) {
    if (rank == PlayerRank.a || rank == PlayerRank.sa) return 60;
    if (rank == PlayerRank.c) return 30;
    return 40;
  }

  void _selectStarter(int index) {
    if (_winner != null || !_canChangeStarter) return;
    setState(() {
      _breakStarter = index;
    });
  }

  void _onPotBall(int player, int number) {
    if (_winner != null) return;
    if (_invalidBalls.contains(number)) return;
    final owner = _ballOwner[number];
    final delta = number == 9 ? 2 : 1;
    setState(() {
      if (owner != null) {
        // すでに得点済みの球はタップで得点取り消し
        _scores[owner] = (_scores[owner] - delta).clamp(0, 9999);
        _disabledBalls.remove(number);
        _ballOwner.remove(number);
      } else {
        _scores[player] = (_scores[player] + delta).clamp(0, 9999);
        _fouls[player] = 0;
        _disabledBalls.add(number);
        _ballOwner[number] = player;
        if (number == 9) {
          // 9番が入ったら次ラック扱いとしてボール状態を全解除する。
          _disabledBalls.clear();
          _invalidBalls.clear();
          _ballOwner.clear();
        }
        if (_scores[player] >= _targets[player]) {
          _winner = player;
          _recordEloIfNeeded(player);
        }
      }
    });
  }

  void _recordEloIfNeeded(int winner) {
    if (_eloRecorded) return;
    final winnerId = winner == 0 ? widget.p1UserKey : widget.p2OpponentKey;
    final loserId = winner == 0 ? widget.p2OpponentKey : widget.p1UserKey;
    if (winnerId.isEmpty || loserId.isEmpty) return;
    _eloRecorded = true;
    _eloRepo.applyMatchResult(
      winnerId: winnerId,
      loserId: loserId,
      pool: EloPool.countNine,
    );
  }

  void _onBallLongPress(int number) {
    if (_winner != null) return;
    final delta = number == 9 ? 2 : 1;
    setState(() {
      final owner = _ballOwner[number];
      if (owner != null) {
        _scores[owner] = (_scores[owner] - delta).clamp(0, 9999);
        _disabledBalls.remove(number);
        _ballOwner.remove(number);
      }
      _invalidBalls.add(number);
    });
  }

  void _onFoul(int player) {
    if (_winner != null) return;
    setState(() {
      _fouls[player]++;
      if (_fouls[player] >= 3) {
        _scores[player] = (_scores[player] - 1).clamp(0, 9999);
        _fouls[player] = 0;
      }
    });
  }

  void _resetFoul(int player) {
    if (_winner != null) return;
    setState(() {
      _fouls[player] = 0;
    });
  }

  void _resetMatch() {
    setState(() {
      _scores[0] = 0;
      _scores[1] = 0;
      _fouls[0] = 0;
      _fouls[1] = 0;
      _disabledBalls.clear();
      _invalidBalls.clear();
      _ballOwner.clear();
      _breakStarter = 0;
      _winner = null;
      _eloRecorded = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppleGlassAppBar(
        context,
        title: 'カウントナイン',
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          color: AppleColors.textOnDark,
          onPressed: () {
            Navigator.of(context).pushNamedAndRemoveUntil('/setup', (route) => false);
          },
        ),
      ),
      body: AppleContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            if (_winner != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppleCard(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  child: Text(
                    '${_winner == 0 ? widget.p1Name : widget.p2Name} の勝利',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppleColors.appleBlue,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 640;

                Widget playerCard({
                  required String name,
                  required PlayerRank rank,
                  required int score,
                  required int target,
                  required int foulCount,
                  required bool isStarter,
                  required bool showInvalidBallArea,
                  required VoidCallback? onSelectStarter,
                  required ValueChanged<int> onBallTap,
                  required VoidCallback onFoul,
                  required VoidCallback onFoulReset,
                }) {
                  return _CountNinePlayerCard(
                    name: name,
                    rank: rank,
                    score: score,
                    target: target,
                    foulCount: foulCount,
                    isStarter: isStarter,
                    onSelectStarter: onSelectStarter,
                    onBallTap: onBallTap,
                    onBallLongPress: _onBallLongPress,
                    isBallDisabled: (n) => _disabledBalls.contains(n),
                  isBallInvalid: (n) => _invalidBalls.contains(n),
                  invalidBalls: _invalidBalls.toList()..sort(),
                    showInvalidBallArea: showInvalidBallArea,
                    onFoul: onFoul,
                    onFoulReset: onFoulReset,
                  );
                }

                final first = playerCard(
                  name: widget.p1Name,
                  rank: widget.p1Rank,
                  score: _scores[0],
                  target: _targets[0],
                  foulCount: _fouls[0],
                  isStarter: _breakStarter == 0,
                  showInvalidBallArea: true,
                  onSelectStarter: _canChangeStarter ? () => _selectStarter(0) : null,
                  onBallTap: (n) => _onPotBall(0, n),
                  onFoul: () => _onFoul(0),
                  onFoulReset: () => _resetFoul(0),
                );
                final second = playerCard(
                  name: widget.p2Name,
                  rank: widget.p2Rank,
                  score: _scores[1],
                  target: _targets[1],
                  foulCount: _fouls[1],
                  isStarter: _breakStarter == 1,
                  showInvalidBallArea: false,
                  onSelectStarter: _canChangeStarter ? () => _selectStarter(1) : null,
                  onBallTap: (n) => _onPotBall(1, n),
                  onFoul: () => _onFoul(1),
                  onFoulReset: () => _resetFoul(1),
                );

                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      first,
                      const SizedBox(height: 10),
                      second,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SizedBox(height: 284, child: first),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(height: 284, child: second),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                '※ 先攻ブレイクは名前をタップすることで切り替えられます\n'
                '※ ボールをタップで得点。得点済みボールはタップで取り消し。\n'
                '※ 長押しで無効球にします（無効球は得点に含まれません）。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppleColors.glyphGraySecondary,
                    ),
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _resetMatch,
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                child: const Text('リセット'),
              ),
            ),
            const SizedBox(height: 8),
            AppleCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'カウントナインルール',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppleColors.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '● 自分と相手の持ち点があり、先に自分の持ち点に到達したほうが勝ち。\n'
                    '● 点数は1球1点、9番のみ2点（するなら、マスワリすれば10点）。\n'
                    '● ショットミスをしたら、対戦相手は毎回フリーボールスタート。\n'
                    '● 9番だけはショットミスをしてもフリーボールにはならず、ミスした現状配置からスタート。相手が間違って9番の時に手球を取ってしまったらファール扱いとなり、相手がフリーボールで9番を撞く。\n'
                    '● 2人対戦のブレイクは交互ブレイク（ブレイク順番を間違えたらそのセットはそのまま続行し、次のセットから飛ばされた人がブレイクし、そこから交互ブレイクになる）。\n'
                    '● 3人以上対戦の場合は勝者ブレイク。\n'
                    '● ブレイクエースは2点と他に入った球が得点となり、その時点でそのセットを終了。\n'
                    '● ファール、スクラッチの罰則はないが、的球を直接撞いたり、手で触るなど、わざとファールした場合は反則負けとなる。3回連続ファールしても負け。\n'
                    '● 2度撞きOK。\n'
                    '● プッシュアウトはすべてのクラスであり。\n'
                    '● フロックインは有効で、同時に入った球も得点になる。\n'
                    '● ファールした時にポケットインしたボールは得点にはならず、ポケットインした球はそのまま無効球となる（9番が落ちた場合は9番のみフットスポットに戻す）。\n'
                    '● 9番が途中で有効なショットで落ちた場合はその時点でそのセットは終わりとなり、次の人がブレイク。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
}

class _CountNinePlayerCard extends StatelessWidget {
  const _CountNinePlayerCard({
    required this.name,
    required this.rank,
    required this.score,
    required this.target,
    required this.foulCount,
    required this.isStarter,
    required this.onSelectStarter,
    required this.onBallTap,
    required this.onBallLongPress,
    required this.isBallDisabled,
    required this.isBallInvalid,
    required this.invalidBalls,
    required this.showInvalidBallArea,
    required this.onFoul,
    required this.onFoulReset,
  });

  final String name;
  final PlayerRank rank;
  final int score;
  final int target;
  final int foulCount;
  final bool isStarter;
  final VoidCallback? onSelectStarter;
  final ValueChanged<int> onBallTap;
  final ValueChanged<int> onBallLongPress;
  final bool Function(int number) isBallDisabled;
  final bool Function(int number) isBallInvalid;
  final List<int> invalidBalls;
  final bool showInvalidBallArea;
  final VoidCallback onFoul;
  final VoidCallback onFoulReset;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onSelectStarter,
      child: AppleCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (showInvalidBallArea)
                      _InvalidBallArea(invalidBalls: invalidBalls),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  rank.labelJa,
                  style: tt.bodySmall?.copyWith(color: AppleColors.glyphGraySecondary),
                ),
                if (isStarter) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppleColors.appleBlue.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '先攻ブレイク',
                      style: tt.bodySmall?.copyWith(
                        color: AppleColors.appleBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '$score/$target',
              style: tt.headlineMedium?.copyWith(
                color: AppleColors.appleBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(9, (i) {
                final n = i + 1;
                return _BallTapChip(
                  number: n,
                  disabled: isBallDisabled(n),
                  invalid: isBallInvalid(n),
                  onTap: () => onBallTap(n),
                  onLongPress: () => onBallLongPress(n),
                );
              }),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) {
                final filled = foulCount > i;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '○',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      height: 1,
                      color: filled ? AppleColors.systemOrange : AppleColors.separator,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 2),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 2,
              runSpacing: 2,
              children: [
                TextButton(
                  onPressed: onFoul,
                  child: const Text('ファウル'),
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
                  onPressed: foulCount > 0 ? onFoulReset : null,
                  child: const Text('リセット'),
                ),
              ],
            ),
            Text(
              '※3ファウルで1点失点',
              style: tt.bodySmall?.copyWith(color: AppleColors.glyphGraySecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _BallTapChip extends StatelessWidget {
  const _BallTapChip({
    required this.number,
    required this.disabled,
    required this.invalid,
    required this.onTap,
    required this.onLongPress,
  });

  final int number;
  final bool disabled;
  final bool invalid;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: (disabled || invalid)
              ? AppleColors.glyphGraySecondary
              : _ballColor(number),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.25),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Text(
                '$number',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
              ),
            ),
            if (invalid)
              Center(
                child: Transform.rotate(
                  angle: -0.8,
                  child: Container(
                    width: 18,
                    height: 1.8,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Color _ballColor(int n) {
    switch (n) {
      case 1:
        return const Color(0xFFF4C20D);
      case 2:
        return const Color(0xFF1E88E5);
      case 3:
        return const Color(0xFFC62828);
      case 4:
        return const Color(0xFF6A1B9A);
      case 5:
        return const Color(0xFFEF6C00);
      case 6:
        return const Color(0xFF2E7D32);
      case 7:
        return const Color(0xFF7B1FA2);
      case 8:
        return const Color(0xFF212121);
      case 9:
      default:
        return const Color(0xFFFFD54F);
    }
  }
}

class _InvalidBallArea extends StatelessWidget {
  const _InvalidBallArea({required this.invalidBalls});

  final List<int> invalidBalls;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppleColors.lightGray,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppleColors.separator),
      ),
      child: Text(
        invalidBalls.isEmpty ? '無効球: -' : '無効球: ${invalidBalls.join(',')}',
        style: tt.labelSmall?.copyWith(
          color: AppleColors.glyphGraySecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
