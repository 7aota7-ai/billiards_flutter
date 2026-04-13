import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/bowlard_record_repository.dart';
import '../theme/apple_theme.dart';

class BowlardRecordScreen extends StatefulWidget {
  const BowlardRecordScreen({super.key});

  @override
  State<BowlardRecordScreen> createState() => _BowlardRecordScreenState();
}

class _BowlardRecordScreenState extends State<BowlardRecordScreen> {
  final _repo = BowlardRecordRepository();
  final _firstBalls = List.generate(10, (_) => TextEditingController());
  final _secondBalls = List.generate(10, (_) => TextEditingController());
  final _bonus1 = TextEditingController();
  final _bonus2 = TextEditingController();

  DateTime _playedOn = DateTime.now();
  List<BowlardRecord> _records = [];
  int? _totalScore;
  String? _grade;
  String? _errorText;
  bool _halfwayCelebrated = false;
  bool _showHalfwayOverlay = false;
  Timer? _halfwayOverlayTimer;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  void dispose() {
    for (final c in _firstBalls) {
      c.dispose();
    }
    for (final c in _secondBalls) {
      c.dispose();
    }
    _bonus1.dispose();
    _bonus2.dispose();
    _halfwayOverlayTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    final loaded = await _repo.loadAll();
    if (!mounted) return;
    setState(() => _records = loaded);
  }

  int? _parseRoll(TextEditingController c) {
    final raw = c.text.trim();
    if (raw.isEmpty) return 0;
    final v = int.tryParse(raw);
    if (v == null || v < 0 || v > 10) return null;
    return v;
  }

  int? _parseRollForCompletion(TextEditingController c) {
    final raw = c.text.trim();
    if (raw.isEmpty) return null;
    final v = int.tryParse(raw);
    if (v == null || v < 0 || v > 10) return null;
    return v;
  }

  bool _isFirstFiveFramesCompleted() {
    for (var i = 0; i < 5; i++) {
      final f = _parseRollForCompletion(_firstBalls[i]);
      final s = _parseRollForCompletion(_secondBalls[i]);
      if (f == null || s == null) return false;
      if (f < 10 && f + s > 10) return false;
    }
    return true;
  }

  void _handleRollChanged() {
    final completed = _isFirstFiveFramesCompleted();
    if (completed && !_halfwayCelebrated) {
      _halfwayOverlayTimer?.cancel();
      setState(() {
        _halfwayCelebrated = true;
        _showHalfwayOverlay = true;
      });
      _halfwayOverlayTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        setState(() => _showHalfwayOverlay = false);
      });
      return;
    }
    if (!completed && _halfwayCelebrated) {
      _halfwayOverlayTimer?.cancel();
      setState(() {
        _halfwayCelebrated = false;
        _showHalfwayOverlay = false;
      });
      return;
    }
    setState(() {});
  }

  String _gradeFor(int score) {
    if (score < 40) return 'ビギナー';
    if (score < 80) return 'C級';
    if (score < 150) return 'B級';
    return 'A級';
  }

  List<int?> _buildCumulativePreview() {
    final first = <int>[];
    final second = <int>[];
    for (var i = 0; i < 10; i++) {
      final f = _parseRoll(_firstBalls[i]);
      final s = _parseRoll(_secondBalls[i]);
      if (f == null || s == null) return List<int?>.filled(10, null);
      if (f < 10 && f + s > 10) return List<int?>.filled(10, null);
      first.add(f);
      second.add(s);
    }

    final rolls = <int>[];
    for (var i = 0; i < 9; i++) {
      if (first[i] == 10) {
        rolls.add(10);
      } else {
        rolls
          ..add(first[i])
          ..add(second[i]);
      }
    }

    final f10 = first[9];
    final s10 = second[9];
    final isStrike10 = f10 == 10;
    final isSpare10 = !isStrike10 && f10 + s10 == 10;
    final b1 = _parseRoll(_bonus1) ?? 0;
    final b2 = _parseRoll(_bonus2) ?? 0;

    if (isStrike10) {
      rolls
        ..add(10)
        ..add(b1)
        ..add(b2);
    } else if (isSpare10) {
      rolls
        ..add(f10)
        ..add(s10)
        ..add(b1);
    } else {
      rolls
        ..add(f10)
        ..add(s10);
    }

    final cumulative = List<int?>.filled(10, null);
    var idx = 0;
    var score = 0;
    for (var frame = 0; frame < 10; frame++) {
      if (idx >= rolls.length) break;
      if (rolls[idx] == 10) {
        if (idx + 2 >= rolls.length) break;
        score += 10 + rolls[idx + 1] + rolls[idx + 2];
        idx += 1;
      } else if (idx + 1 < rolls.length && rolls[idx] + rolls[idx + 1] == 10) {
        if (idx + 2 >= rolls.length) break;
        score += 10 + rolls[idx + 2];
        idx += 2;
      } else {
        if (idx + 1 >= rolls.length) break;
        score += rolls[idx] + rolls[idx + 1];
        idx += 2;
      }
      cumulative[frame] = score;
    }
    return cumulative;
  }

  String _markForFirst(int value) => value == 10 ? 'X' : '$value';

  String _markForSecond(int first, int second) {
    if (first == 10) return '';
    if (first + second == 10) return '/';
    return '$second';
  }

  Future<void> _evaluateAndSave() async {
    final first = <int>[];
    final second = <int>[];
    for (var i = 0; i < 10; i++) {
      final f = _parseRoll(_firstBalls[i]);
      final s = _parseRoll(_secondBalls[i]);
      if (f == null || s == null) {
        setState(() => _errorText = '各フレームは 0 〜 10 の整数で入力してください。');
        return;
      }
      if (f < 10 && f + s > 10) {
        setState(
            () => _errorText = 'フレーム ${i + 1}: 1投目がストライクでない場合、1投目+2投目は10以下です。');
        return;
      }
      first.add(f);
      second.add(s);
    }

    final rolls = <int>[];
    for (var i = 0; i < 9; i++) {
      if (first[i] == 10) {
        rolls.add(10);
      } else {
        rolls
          ..add(first[i])
          ..add(second[i]);
      }
    }

    final f10 = first[9];
    final s10 = second[9];
    final isStrike10 = f10 == 10;
    final isSpare10 = !isStrike10 && f10 + s10 == 10;

    if (isStrike10) {
      final b1 = _parseRoll(_bonus1);
      final b2 = _parseRoll(_bonus2);
      if (b1 == null || b2 == null) {
        setState(() => _errorText = '10フレーム目がストライクなので、ボーナス2投を入力してください。');
        return;
      }
      rolls
        ..add(10)
        ..add(b1)
        ..add(b2);
    } else if (isSpare10) {
      final b1 = _parseRoll(_bonus1);
      if (b1 == null) {
        setState(() => _errorText = '10フレーム目がスペアなので、ボーナス1投を入力してください。');
        return;
      }
      rolls
        ..add(f10)
        ..add(s10)
        ..add(b1);
    } else {
      rolls
        ..add(f10)
        ..add(s10);
    }

    var idx = 0;
    var score = 0;
    for (var frame = 0; frame < 10; frame++) {
      if (rolls[idx] == 10) {
        score += 10 + rolls[idx + 1] + rolls[idx + 2];
        idx += 1;
      } else if (rolls[idx] + rolls[idx + 1] == 10) {
        score += 10 + rolls[idx + 2];
        idx += 2;
      } else {
        score += rolls[idx] + rolls[idx + 1];
        idx += 2;
      }
    }

    final grade = _gradeFor(score);
    final date = DateUtils.dateOnly(_playedOn);
    final record = BowlardRecord(
      playedOnIso: date.toIso8601String(),
      totalScore: score,
      gradeLabel: grade,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _repo.save(record);
    await _loadRecords();
    if (!mounted) return;
    setState(() {
      _totalScore = score;
      _grade = grade;
      _errorText = null;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _playedOn,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 2),
    );
    if (selected != null && mounted) {
      setState(() => _playedOn = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final dateLabel =
        '${_playedOn.year}/${_playedOn.month.toString().padLeft(2, '0')}/${_playedOn.day.toString().padLeft(2, '0')}';
    final f10 = _parseRoll(_firstBalls[9]) ?? 0;
    final s10 = _parseRoll(_secondBalls[9]) ?? 0;
    final needBonus1 = f10 == 10 || f10 + s10 == 10;
    final needBonus2 = f10 == 10;
    final cumulative = _buildCumulativePreview();

    return Scaffold(
      appBar: buildAppleGlassAppBar(context, title: 'ボーラード記録'),
      body: AppleContentWidth(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
              children: [
                _CardBlock(
                  title: '入力',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '1フレーム=2イニング。10フレームをボウリング式で採点します。',
                        style: tt.bodySmall
                            ?.copyWith(color: AppleColors.glyphGraySecondary),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: List.generate(10, (i) {
                            return Padding(
                              padding: EdgeInsets.only(right: i == 9 ? 0 : 6),
                              child: _scoreFrameCell(i, cumulative[i]),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: _pickDate,
                              child: Text('実施日: $dateLabel'),
                            ),
                          ),
                          if (needBonus1)
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _bonus1,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  labelText: 'B1',
                                ),
                              ),
                            ),
                          if (needBonus2) const SizedBox(width: 8),
                          if (needBonus2)
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _bonus2,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  labelText: 'B2',
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (_errorText != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _errorText!,
                          style: tt.bodySmall
                              ?.copyWith(color: AppleColors.systemRed),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton(
                          onPressed: _evaluateAndSave,
                          child: const Text('採点して保存'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _CardBlock(
                  title: '結果',
                  child: _totalScore == null
                      ? Text(
                          'まだ採点結果がありません。',
                          style: tt.bodyMedium
                              ?.copyWith(color: AppleColors.glyphGraySecondary),
                        )
                      : Row(
                          children: [
                            Text('合計: $_totalScore 点', style: tt.titleMedium),
                            const SizedBox(width: 12),
                            Text('評価: $_grade', style: tt.titleMedium),
                          ],
                        ),
                ),
                const SizedBox(height: 16),
                _CardBlock(
                  title: '記録履歴',
                  child: _records.isEmpty
                      ? Text(
                          '保存された記録はありません。',
                          style: tt.bodyMedium
                              ?.copyWith(color: AppleColors.glyphGraySecondary),
                        )
                      : Column(
                          children: _records.map((r) {
                            final d = DateTime.tryParse(r.playedOnIso);
                            final label = d == null
                                ? r.playedOnIso
                                : '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text('$label - ${r.totalScore}点'),
                              trailing: Text(r.gradeLabel),
                            );
                          }).toList(),
                        ),
                ),
              ],
            ),
            if (_showHalfwayOverlay)
              Positioned.fill(
                child: IgnorePointer(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 1300),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, child) {
                      return Opacity(
                        opacity: t < 0.75 ? 1 : (1 - ((t - 0.75) / 0.25)),
                        child: child,
                      );
                    },
                    child: _HalfwayCelebrationOverlay(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _scoreFrameCell(int index, int? cumulative) {
    final firstValue = _parseRoll(_firstBalls[index]) ?? 0;
    final secondValue = _parseRoll(_secondBalls[index]) ?? 0;
    final isTenth = index == 9;
    final topLabel = '${index + 1}';

    return Container(
      width: isTenth ? 92 : 72,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF9DBA4A)),
      ),
      child: Column(
        children: [
          Container(
            height: 26,
            alignment: Alignment.center,
            color: const Color(0xFFD5EA8B),
            child: Text(
              topLabel,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Container(
            height: 34,
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0xFF9DBA4A)),
                bottom: BorderSide(color: Color(0xFF9DBA4A)),
              ),
            ),
            child: isTenth
                ? _tenthRollRow()
                : _normalRollRow(index, firstValue, secondValue),
          ),
          SizedBox(
            height: 30,
            child: Center(
              child: Text(
                cumulative?.toString() ?? '',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _normalRollRow(int index, int firstValue, int secondValue) {
    return Row(
      children: [
        Expanded(
          child: _rollInput(
            controller: _firstBalls[index],
            alignRight: true,
            hint: _markForFirst(firstValue),
          ),
        ),
        Expanded(
          child: _rollInput(
            controller: _secondBalls[index],
            alignRight: true,
            hint: _markForSecond(firstValue, secondValue),
          ),
        ),
      ],
    );
  }

  Widget _tenthRollRow() {
    final f10 = _parseRoll(_firstBalls[9]) ?? 0;
    final s10 = _parseRoll(_secondBalls[9]) ?? 0;
    final needBonus1 = f10 == 10 || f10 + s10 == 10;
    final needBonus2 = f10 == 10;
    return Row(
      children: [
        Expanded(
          child: _rollInput(
            controller: _firstBalls[9],
            alignRight: true,
            hint: _markForFirst(f10),
          ),
        ),
        Expanded(
          child: _rollInput(
            controller: _secondBalls[9],
            alignRight: true,
            hint: _markForSecond(f10, s10),
          ),
        ),
        Expanded(
          child: _rollInput(
            controller: _bonus1,
            alignRight: true,
            hint: needBonus1 ? '${_parseRoll(_bonus1) ?? 0}' : '',
          ),
        ),
        Expanded(
          child: _rollInput(
            controller: _bonus2,
            alignRight: true,
            hint: needBonus2 ? '${_parseRoll(_bonus2) ?? 0}' : '',
          ),
        ),
      ],
    );
  }

  Widget _rollInput({
    required TextEditingController controller,
    required bool alignRight,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
      style: const TextStyle(
        color: AppleColors.nearBlack,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      cursorColor: AppleColors.nearBlack,
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        hintText: hint,
        hintStyle: const TextStyle(
          color: AppleColors.glyphGraySecondary,
          fontWeight: FontWeight.w600,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      ),
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      onChanged: (_) => _handleRollChanged(),
    );
  }
}

class _HalfwayCelebrationOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final confetti = [
      _confetti('🎉', -90, -110, -10, 90),
      _confetti('✨', -40, -130, 30, 80),
      _confetti('🎊', 30, -110, 95, 90),
      _confetti('⭐', 80, -120, -75, 85),
      _confetti('🎉', -110, -40, -35, 115),
      _confetti('✨', 110, -30, 40, 120),
      _confetti('🔥', -140, -90, 120, 120),
      _confetti('🎉', 135, -100, -120, 125),
      _confetti('💫', -20, -150, -95, 135),
      _confetti('🎊', 20, -150, 95, 135),
      _confetti('⭐', -150, -20, 130, 65),
      _confetti('✨', 150, -15, -130, 70),
    ];

    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.88, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.elasticOut,
        builder: (context, scale, child) {
          return Transform.scale(scale: scale, child: child);
        },
        child: Container(
          width: 304,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFF9E8), Color(0xFFFFFFFF)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              ...AppleColors.cardShadow,
              BoxShadow(
                color: AppleColors.appleBlue.withValues(alpha: 0.28),
                blurRadius: 28,
                spreadRadius: 2,
              ),
            ],
            border: Border.all(
                color: AppleColors.appleBlue.withValues(alpha: 0.6), width: 2),
          ),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              ...confetti,
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.95, end: 1.08),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeInOutSine,
                builder: (context, pulse, child) {
                  return Transform.scale(scale: pulse, child: child);
                },
                child: Text(
                  '折り返し！',
                  style: tt.headlineMedium?.copyWith(
                    color: AppleColors.appleBlue,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _confetti(
    String symbol,
    double fromX,
    double fromY,
    double toX,
    double toY,
  ) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1900),
      curve: Curves.easeOutExpo,
      builder: (context, t, child) {
        final x = fromX + (toX - fromX) * t;
        final y = fromY + (toY - fromY) * t;
        return Transform.translate(
          offset: Offset(x, y),
          child: Opacity(
            opacity: (1 - (t * 0.45)).clamp(0.0, 1.0),
            child: Transform.rotate(
              angle: t * 6.2,
              child: child,
            ),
          ),
        );
      },
      child: Text(symbol, style: const TextStyle(fontSize: 26)),
    );
  }
}

class _CardBlock extends StatelessWidget {
  const _CardBlock({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return AppleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: tt.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
