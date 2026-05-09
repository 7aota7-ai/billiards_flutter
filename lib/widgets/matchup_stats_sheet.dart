import 'package:flutter/material.dart';

import '../models/match_result_record.dart';
import '../models/scoreboard_models.dart';
import '../theme/apple_theme.dart';

Future<void> showMatchupStatsSheet(
  BuildContext context, {
  required String opponentName,
  required MatchupStatsRecord? stats,
}) async {
  final mediaBottom = MediaQuery.viewInsetsOf(context).bottom;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, mediaBottom + 20),
          child: _MatchupStatsSheet(
            opponentName: opponentName,
            stats: stats,
          ),
        ),
      );
    },
  );
}

class _MatchupStatsSheet extends StatelessWidget {
  const _MatchupStatsSheet({
    required this.opponentName,
    required this.stats,
  });

  final String opponentName;
  final MatchupStatsRecord? stats;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$opponentName との対戦成績',
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        if (stats == null)
          Text(
            'この相手との対戦記録はまだありません。',
            style: tt.bodyMedium?.copyWith(
              color: AppleColors.glyphGraySecondary,
            ),
          )
        else ...[
          _MYSummary(stats: stats!),
          const SizedBox(height: 10),
          _RateGraph(
            wins: stats!.wins,
            losses: stats!.losses,
          ),
          const SizedBox(height: 12),
          _FoulGraph(
            myFouls: stats!.myFouls,
            opponentFouls: stats!.opponentFouls,
          ),
          const SizedBox(height: 12),
          _TimerInfoCard(stats: stats!),
        ],
      ],
    );
  }
}

class _MYSummary extends StatelessWidget {
  const _MYSummary({required this.stats});
  final MatchupStatsRecord stats;

  @override
  Widget build(BuildContext context) {
    final latest = stats.matchHistory.isEmpty
        ? null
        : stats.matchHistory.last;
    final latestDate = latest == null
        ? '--/--/--'
        : _formatYmd(DateTime.fromMillisecondsSinceEpoch(latest.atMs));
    final tt = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppleColors.lightGray,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          '$latestDate  ${stats.wins}勝${stats.losses}敗',
          style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  String _formatYmd(DateTime d) {
    final yy = (d.year % 100).toString().padLeft(2, '0');
    return '$yy/${d.month}/${d.day}';
  }
}

class _RateGraph extends StatelessWidget {
  const _RateGraph({
    required this.wins,
    required this.losses,
  });

  final int wins;
  final int losses;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final total = wins + losses;
    final winRate = total == 0 ? 0.0 : wins / total;
    return _BarChartCard(
      title: '勝率',
      leftLabel: '勝ち',
      rightLabel: '負け',
      leftValue: wins,
      rightValue: losses,
      leftRate: winRate,
      leftColor: AppleColors.systemGreen,
      rightColor: AppleColors.systemRed,
      summary: '${(winRate * 100).toStringAsFixed(1)}%',
      textTheme: tt,
      animate: true,
    );
  }
}

class _FoulGraph extends StatelessWidget {
  const _FoulGraph({
    required this.myFouls,
    required this.opponentFouls,
  });

  final int myFouls;
  final int opponentFouls;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final total = myFouls + opponentFouls;
    final myRate = total == 0 ? 0.0 : myFouls / total;
    return _BarChartCard(
      title: 'ファール比率',
      leftLabel: 'あなた',
      rightLabel: '相手',
      leftValue: myFouls,
      rightValue: opponentFouls,
      leftRate: myRate,
      leftColor: AppleColors.systemOrange,
      rightColor: AppleColors.appleBlue,
      summary: 'あなた ${(myRate * 100).toStringAsFixed(1)}%',
      textTheme: tt,
      animate: false,
    );
  }
}

class _BarChartCard extends StatelessWidget {
  const _BarChartCard({
    required this.title,
    required this.leftLabel,
    required this.rightLabel,
    required this.leftValue,
    required this.rightValue,
    required this.leftRate,
    required this.leftColor,
    required this.rightColor,
    required this.summary,
    required this.textTheme,
    required this.animate,
  });

  final String title;
  final String leftLabel;
  final String rightLabel;
  final int leftValue;
  final int rightValue;
  final double leftRate;
  final Color leftColor;
  final Color rightColor;
  final String summary;
  final TextTheme textTheme;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final clamped = leftRate.clamp(0.0, 1.0);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppleColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppleColors.separator),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppleColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (animate)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: clamped),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => Text(
                      '${(value * 100).toStringAsFixed(1)}%',
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppleColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  Text(
                    summary,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppleColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: animate ? clamped : clamped),
              duration: Duration(milliseconds: animate ? 700 : 0),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 14,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: rightColor.withValues(alpha: 0.6)),
                        FractionallySizedBox(
                          widthFactor: value,
                          alignment: Alignment.centerLeft,
                          child: ColoredBox(color: leftColor),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$leftLabel  $leftValue',
                  style: textTheme.labelLarge?.copyWith(color: leftColor),
                ),
                Text(
                  '$rightLabel  $rightValue',
                  style: textTheme.labelLarge?.copyWith(color: rightColor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimerInfoCard extends StatelessWidget {
  const _TimerInfoCard({required this.stats});

  final MatchupStatsRecord stats;

  String _modeLabel(String modeName) {
    switch (modeName) {
      case 'totalThenShot':
        return 'A 持ち時間';
      case 'shotClockOnly':
        return 'B 1ショット';
      case 'unlimited':
        return 'C 制限なし';
      case 'countNine':
        return 'D カウントナイン';
      default:
        return modeName;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final entries = stats.timerModeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    String latest = 'なし';
    switch (stats.lastTimerTab) {
      case TimerTabKind.totalThenShot:
        latest = 'A 持ち時間 ${stats.lastATotalMinutes ?? 0}分 / 1ショット ${stats.lastAShotSeconds ?? 0}秒';
        break;
      case TimerTabKind.shotClockOnly:
        latest = 'B 1ショット ${stats.lastBShotSeconds ?? 0}秒';
        break;
      case TimerTabKind.unlimited:
        latest = 'C 制限なし';
        break;
      case TimerTabKind.countNine:
        latest = 'D カウントナイン';
        break;
      case null:
        break;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppleColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppleColors.separator),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'タイマー情報',
              style: tt.bodyMedium?.copyWith(
                color: AppleColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '最近の設定: $latest',
              style: tt.labelLarge?.copyWith(color: AppleColors.textSecondary),
            ),
            if (entries.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final e in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${_modeLabel(e.key)}  ${e.value}回',
                    style: tt.labelLarge?.copyWith(
                      color: AppleColors.glyphGraySecondary,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
