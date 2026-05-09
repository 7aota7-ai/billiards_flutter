import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/elo_rating_models.dart';
import '../models/scoreboard_models.dart';
import '../models/opponent_record.dart';
import '../models/match_result_record.dart';
import '../services/elo_rating_repository.dart';
import '../services/match_result_repository.dart';
import '../services/opponent_repository.dart';
import '../services/self_profile_repository.dart';
import '../theme/apple_theme.dart';
import '../widgets/elo_info_link.dart';
import '../widgets/matchup_stats_sheet.dart';
import 'count_nine_screen.dart';
import 'game_screen.dart';

/// `_LabeledRow` のラベル列幅。入力・リンクの左端を揃える。
const double _kLabeledContentInset = 52;

class _ResolvedKeys {
  const _ResolvedKeys({
    required this.p1Key,
    required this.p2Key,
  });

  final String p1Key;
  final String p2Key;
}

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _oppRepo = OpponentRepository();
  final _selfRepo = SelfProfileRepository();
  final _resultRepo = MatchResultRepository();
  final _eloRepo = EloRatingRepository();
  final _p1Name = TextEditingController(text: 'あなた');
  final _p2Name = TextEditingController(text: '相手');
  final _p2Search = TextEditingController();
  PlayerRank _p1Rank = PlayerRank.b;
  PlayerRank _p2Rank = PlayerRank.a;

  /// 検索で選んだ既存相手。未設定なら試合開始時に新規採番
  String? _p2OpponentId;
  List<OpponentRecord> _topCandidates = [];
  MatchupStatsRecord? _selectedStats;

  final _t1 = TextEditingController(text: '5');
  final _t2 = TextEditingController(text: '5');

  TimerTabKind _tab = TimerTabKind.totalThenShot;
  final _aTotal = TextEditingController(text: '30');
  final _aShot = TextEditingController(text: '25');
  final _bShot = TextEditingController(text: '45');

  int _maxSets = 0;

  bool _targetsValid = true;

  @override
  void initState() {
    super.initState();
    Future.wait([
      _oppRepo.ensureLoaded(),
      _selfRepo.ensureLoaded(),
      _resultRepo.ensureLoaded(),
      _eloRepo.ensureLoaded(),
    ]).then((_) {
      if (!mounted) return;
      final self = _selfRepo.load();
      setState(() {
        if (self != null) {
          _p1Name.text = self.displayName;
          _p1Rank = self.rank;
        }
        _refreshOpponentUi();
      });
    });
  }

  void _refreshOpponentUi() {
    _topCandidates = _oppRepo.topFrequentOrRecent(limit: 3);
  }

  Future<void> _saveMyProfile() async {
    await _selfRepo.ensureLoaded();
    await _selfRepo.saveMyProfile(
      displayName: _p1Name.text,
      rank: _p1Rank,
    );
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('自分の情報を登録しました')),
    );
  }

  Future<void> _registerOpponentProfile() async {
    await _oppRepo.ensureLoaded();
    final rec = await _oppRepo.registerNew(
      displayName: _p2Name.text,
      rank: _p2Rank,
    );
    if (!mounted) return;
    setState(() {
      _p2OpponentId = rec.id;
      _p2Name.text = rec.displayName;
      _refreshOpponentUi();
    });
    await _loadSelectedOpponentStats();
  }

  void _applyOpponent(OpponentRecord o) {
    setState(() {
      _p2OpponentId = o.id;
      _p2Name.text = o.displayName;
      _p2Rank = o.rank;
      _p2Search.text = o.displayName;
      _refreshOpponentUi();
    });
    _loadSelectedOpponentStats();
  }

  Future<void> _loadSelectedOpponentStats() async {
    final id = _p2OpponentId;
    if (id == null) {
      if (!mounted) return;
      setState(() => _selectedStats = null);
      return;
    }
    final stats = await _resultRepo.loadStats(id);
    if (!mounted) return;
    setState(() => _selectedStats = stats);
  }

  void _changeTarget(TextEditingController controller, int delta) {
    final current = int.tryParse(controller.text) ?? 1;
    final next = (current + delta).clamp(1, 99);
    controller.text = '$next';
    _validateTargets();
  }

  Future<void> _showMatchupStatsSheet() async {
    final id = _p2OpponentId;
    if (id == null) return;
    await _loadSelectedOpponentStats();
    if (!mounted) return;
    await showMatchupStatsSheet(
      context,
      opponentName: _p2Name.text.trim().isEmpty ? '相手' : _p2Name.text.trim(),
      stats: _selectedStats,
    );
  }

  Future<void> _showAllMatchHistorySheet() async {
    await Future.wait([
      _oppRepo.ensureLoaded(),
      _resultRepo.ensureLoaded(),
      _eloRepo.ensureLoaded(),
    ]);
    final self = _selfRepo.load();
    final statsMap = await _resultRepo.loadAllStats();
    final scoreElo = await _eloRepo.loadPool(EloPool.scoreboard);
    final c9Elo = await _eloRepo.loadPool(EloPool.countNine);
    if (!mounted) return;

    final opponents = _oppRepo.getAll();
    final nameById = <String, String>{
      for (final o in opponents) o.id: o.displayName,
    };

    final items = statsMap.entries.toList()
      ..sort((a, b) => b.value.updatedAtMs.compareTo(a.value.updatedAtMs));

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final tt = Theme.of(context).textTheme;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.75,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    'これまでの対戦成績',
                    style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (self != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 0,
                      runSpacing: 4,
                      children: [
                        Text(
                          'あなたの',
                          style: tt.labelLarge?.copyWith(
                            color: AppleColors.textSecondary,
                          ),
                        ),
                        EloInfoLink(
                          style: tt.labelLarge?.copyWith(
                            color: AppleColors.textSecondary,
                          ),
                          iconSize: 16,
                        ),
                        Text(
                          '  通常:${scoreElo[self.id]?.rating ?? 1500}  カウントナイン:${c9Elo[self.id]?.rating ?? 1500}',
                          style: tt.labelLarge?.copyWith(
                            color: AppleColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 1),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            'まだ対戦成績がありません',
                            style: tt.bodyMedium?.copyWith(
                              color: AppleColors.glyphGraySecondary,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final id = items[i].key;
                            final s = items[i].value;
                            final name = nameById[id] ?? id;
                            return ListTile(
                              title: Text(name),
                              subtitle: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 4,
                                children: [
                                  Text(
                                    '${s.wins}勝${s.losses}敗  /  ',
                                    style: tt.bodyMedium?.copyWith(
                                      color: AppleColors.textSecondary,
                                    ),
                                  ),
                                  EloInfoLink(
                                    style: tt.bodyMedium?.copyWith(
                                      color: AppleColors.textSecondary,
                                    ),
                                    iconSize: 15,
                                  ),
                                  Text(
                                    ' 通常:${scoreElo[id]?.rating ?? 1500}  C9:${c9Elo[id]?.rating ?? 1500}',
                                    style: tt.bodyMedium?.copyWith(
                                      color: AppleColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Text(
                                _formatYmd(DateTime.fromMillisecondsSinceEpoch(
                                    s.updatedAtMs)),
                                style: tt.labelLarge?.copyWith(
                                  color: AppleColors.glyphGraySecondary,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatYmd(DateTime d) {
    final yy = (d.year % 100).toString().padLeft(2, '0');
    return '$yy/${d.month}/${d.day}';
  }

  Future<void> _deleteOpponent(
    OpponentRecord opponent, {
    VoidCallback? onDeletedInSheet,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('登録済み相手を削除'),
          content: Text('「${opponent.displayName}（${opponent.id}）」を削除しますか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('削除する'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;

    await _oppRepo.ensureLoaded();
    final deleted = await _oppRepo.deleteById(opponent.id);
    if (!mounted || !deleted) return;

    setState(() {
      if (_p2OpponentId == opponent.id) {
        _p2OpponentId = null;
        _selectedStats = null;
      }
      _refreshOpponentUi();
    });
    onDeletedInSheet?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('削除しました: ${opponent.displayName}')),
    );
  }

  Future<void> _showOpponentListSheet() async {
    await _oppRepo.ensureLoaded();
    if (!mounted) return;
    final all = List<OpponentRecord>.of(_oppRepo.getAll())
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final filter = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (context, setModalState) {
              void applyFilter() => setModalState(() {});
              final q = filter.text.trim().toLowerCase();
              final filtered = q.isEmpty
                  ? all
                  : all
                      .where(
                        (o) =>
                            o.displayName.toLowerCase().contains(q) ||
                            o.id.toLowerCase().contains(q),
                      )
                      .toList();

              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.55,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Text(
                          '登録済みから選ぶ',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: filter,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            hintText: '名前またはユーザIDで絞り込み',
                          ),
                          onChanged: (_) => applyFilter(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  '該当なし',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(
                                        color: AppleColors.glyphGraySecondary,
                                      ),
                                ),
                              )
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1, thickness: 0.5),
                                itemBuilder: (context, i) {
                                  final o = filtered[i];
                                  return ListTile(
                                    title: Text(o.displayName),
                                    subtitle:
                                        Text('${o.id} · ${o.rank.labelJa}'),
                                    trailing: IconButton(
                                      tooltip: 'この登録者を削除',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () async {
                                        await _deleteOpponent(
                                          o,
                                          onDeletedInSheet: () {
                                            all.removeWhere(
                                                (e) => e.id == o.id);
                                            applyFilter();
                                          },
                                        );
                                      },
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      _applyOpponent(o);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
    filter.dispose();
  }

  @override
  void dispose() {
    _p1Name.dispose();
    _p2Name.dispose();
    _p2Search.dispose();
    _t1.dispose();
    _t2.dispose();
    _aTotal.dispose();
    _aShot.dispose();
    _bShot.dispose();
    super.dispose();
  }

  void _validateTargets() {
    final v1 = int.tryParse(_t1.text);
    final v2 = int.tryParse(_t2.text);
    final ok =
        v1 != null && v2 != null && v1 >= 1 && v1 <= 99 && v2 >= 1 && v2 <= 99;
    setState(() => _targetsValid = ok);
  }

  Future<void> _start() async {
    _validateTargets();
    if (!_targetsValid) return;

    final v1 = int.parse(_t1.text);
    final v2 = int.parse(_t2.text);
    final p1 = _p1Name.text.trim().isEmpty ? 'P1' : _p1Name.text.trim();
    final p2 = _p2Name.text.trim().isEmpty ? 'P2' : _p2Name.text.trim();

    final keys = await _resolveMatchKeys(p1: p1, p2: p2);
    final p1Key = keys.p1Key;
    final p2Key = keys.p2Key;

    await _oppRepo.recordMatchPlayed(p2Key);

    if (!mounted) return;

    final setup = MatchSetup(
      p1Name: p1,
      p2Name: p2,
      p1Rank: _p1Rank,
      p2Rank: _p2Rank,
      p1UserKey: p1Key,
      p2OpponentKey: p2Key,
      p1Target: v1,
      p2Target: v2,
      timerTab: _tab,
      aTotalMinutes: int.tryParse(_aTotal.text) ?? 30,
      aShotSeconds: int.tryParse(_aShot.text) ?? 25,
      bShotSeconds: int.tryParse(_bShot.text) ?? 45,
      maxSets: _maxSets,
    );

    if (_tab == TimerTabKind.countNine) {
      await Navigator.of(context).pushNamed<void>(
        '/count-nine',
        arguments: CountNineArgs(
          p1Name: p1,
          p2Name: p2,
          p1Rank: _p1Rank,
          p2Rank: _p2Rank,
          p1UserKey: p1Key,
          p2OpponentKey: p2Key,
        ),
      );
    } else {
      await Navigator.of(context).pushNamed<void>(
        '/scoreboard',
        arguments: GameScreenArgs(setup: setup),
      );
    }
    if (mounted) {
      setState(_refreshOpponentUi);
    }
  }

  Future<void> _openBowlardRecord() async {
    await Navigator.of(context).pushNamed<void>('/bowlard');
  }

  Future<void> _openBallLayoutEditor() async {
    await Navigator.of(context).pushNamed<void>('/layout');
  }

  Future<void> _openFiveNineDraft() async {
    await Navigator.of(context).pushNamed<void>('/five-nine');
  }

  Future<void> _openCountNine() async {
    final p1 = _p1Name.text.trim().isEmpty ? 'あなた' : _p1Name.text.trim();
    final p2 = _p2Name.text.trim().isEmpty ? '相手' : _p2Name.text.trim();
    final keys = await _resolveMatchKeys(p1: p1, p2: p2);
    await _oppRepo.recordMatchPlayed(keys.p2Key);
    if (!mounted) return;
    await Navigator.of(context).pushNamed<void>(
      '/count-nine',
      arguments: CountNineArgs(
        p1Name: p1,
        p2Name: p2,
        p1Rank: _p1Rank,
        p2Rank: _p2Rank,
        p1UserKey: keys.p1Key,
        p2OpponentKey: keys.p2Key,
      ),
    );
  }

  Future<_ResolvedKeys> _resolveMatchKeys({
    required String p1,
    required String p2,
  }) async {
    await _oppRepo.ensureLoaded();
    await _selfRepo.ensureLoaded();
    final p1Key = await _selfRepo.userKeyForMatch(
      displayName: p1,
      rank: _p1Rank,
    );
    final String p2Key;
    if (_p2OpponentId != null) {
      p2Key = _p2OpponentId!;
    } else {
      final rec = await _oppRepo.registerNew(displayName: p2, rank: _p2Rank);
      p2Key = rec.id;
      if (mounted) {
        setState(() => _p2OpponentId = rec.id);
      }
    }
    return _ResolvedKeys(p1Key: p1Key, p2Key: p2Key);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: buildAppleGlassAppBar(
        context,
        title: 'スコアボード設定',
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          PopupMenuButton<String>(
            tooltip: 'メニュー',
            icon: const Icon(Icons.menu),
            onSelected: (value) async {
              if (value == 'bowlard') {
                await _openBowlardRecord();
              } else if (value == 'layout') {
                await _openBallLayoutEditor();
              } else if (value == 'five9') {
                await _openFiveNineDraft();
              } else if (value == 'count9') {
                await _openCountNine();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'bowlard',
                child: Text('ボーラード記録ページ'),
              ),
              PopupMenuItem<String>(
                value: 'layout',
                child: Text('配置登録エディタ'),
              ),
              PopupMenuItem<String>(
                value: 'count9',
                child: Text('カウントナイン'),
              ),
              PopupMenuItem<String>(
                value: 'five9',
                child: Text('5-9（5-10）'),
              ),
            ],
          ),
        ],
      ),
      body: AppleContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  'プロトタイプ',
                  style: tt.labelSmall?.copyWith(
                    color: AppleColors.glyphGraySecondary,
                    fontSize: 12,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
            _CardBlock(
              title: 'プレイヤー設定',
              child: Column(
                children: [
                  _LabeledRow(
                    label: 'あなた',
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _p1Name,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _rankDropdown(
                            _p1Rank, (v) => setState(() => _p1Rank = v!)),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: _saveMyProfile,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(64, 40),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('登録'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Builder(
                    builder: (context) {
                      final self = _selfRepo.load();
                      if (self == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(
                            left: _kLabeledContentInset, top: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ユーザID: ${self.id}',
                                style: tt.labelSmall?.copyWith(
                                  color: AppleColors.glyphGraySecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 0, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: _showAllMatchHistorySheet,
                                child: const Text('これまでの対戦成績を一覧表示'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _LabeledRow(
                    label: '相手',
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _p2Name,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {
                              _p2OpponentId = null;
                              _selectedStats = null;
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _rankDropdown(
                            _p2Rank, (v) => setState(() => _p2Rank = v!)),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: _registerOpponentProfile,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(64, 40),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('登録'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(
                        left: _kLabeledContentInset, top: 4, bottom: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 0, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed:
                            _p2OpponentId == null ? null : _showMatchupStatsSheet,
                        child: const Text('対戦成績を表示'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'よく対戦する相手から選ぶ',
                    style: tt.bodyMedium?.copyWith(
                      color: AppleColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_topCandidates.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '登録済みの相手がいません。検索の下から選ぶか、試合開始で新規登録されます。',
                        style: tt.labelLarge?.copyWith(
                          color: AppleColors.glyphGraySecondary,
                          height: 1.35,
                        ),
                      ),
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < _topCandidates.length; i++)
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: i == 0 ? 0 : 4,
                                right: i == _topCandidates.length - 1 ? 0 : 4,
                              ),
                              child: Material(
                                color: AppleColors.white,
                                borderRadius: BorderRadius.circular(10),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () =>
                                      _applyOpponent(_topCandidates[i]),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                          color: AppleColors.separator),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _topCandidates[i].displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: tt.labelLarge?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _topCandidates[i].rank.labelJa,
                                          style: tt.labelSmall?.copyWith(
                                            color:
                                                AppleColors.glyphGraySecondary,
                                          ),
                                        ),
                                        if (_topCandidates[i].matchCount >
                                            0) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            '対戦 ${_topCandidates[i].matchCount}回',
                                            style: tt.labelSmall?.copyWith(
                                              color: AppleColors.appleBlue,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.only(left: _kLabeledContentInset),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '登録済み相手を検索',
                          style: tt.bodyMedium?.copyWith(
                            color: AppleColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _p2Search,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  hintText: '名前またはユーザID',
                                ),
                                onChanged: (_) => setState(_refreshOpponentUi),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Tooltip(
                              message: '一覧から選ぶ',
                              child: IconButton(
                                style: IconButton.styleFrom(
                                  foregroundColor: AppleColors.appleBlue,
                                ),
                                onPressed: _showOpponentListSheet,
                                icon: const Icon(Icons.list_alt_rounded),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _CardBlock(
              title: '先取点数（ハンデ）',
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _HandePlayer(
                          name: _p1Name.text.isEmpty ? 'あなた' : _p1Name.text,
                          controller: _t1,
                          onChanged: (_) => _validateTargets(),
                          onDecrement: () => _changeTarget(_t1, -1),
                          onIncrement: () => _changeTarget(_t1, 1),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 6, right: 6),
                        child: Text(
                          '—',
                          style: tt.headlineMedium?.copyWith(
                            color: AppleColors.glyphGraySecondary,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ),
                      Expanded(
                        child: _HandePlayer(
                          name: _p2Name.text.isEmpty ? '相手' : _p2Name.text,
                          controller: _t2,
                          onChanged: (_) => _validateTargets(),
                          onDecrement: () => _changeTarget(_t2, -1),
                          onIncrement: () => _changeTarget(_t2, 1),
                        ),
                      ),
                    ],
                  ),
                  if (!_targetsValid) ...[
                    const SizedBox(height: 6),
                    Text(
                      '1〜99の数字を入力してください',
                      style: tt.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _CardBlock(
              title: 'タイマー設定',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Table+fill は行高0でカードが消えることがあるため、
                        // 親幅から十分な固定高を決めて 3 枚を必ず表示する
                        final w = constraints.maxWidth;
                        final cardHeight = (108 + w * 0.08).clamp(160.0, 220.0);
                        const narrowBreak = 600.0;
                        final narrow = w < narrowBreak;
                        const timerBandH = 118.0;

                        Widget tileA() => SizedBox(
                              width: narrow ? double.infinity : null,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    height: cardHeight,
                                    child: _TimerModeTile(
                                      title: 'A  持ち時間',
                                      subtitle: '各自の持ち時間のあと、1ショットタイマーに切り替わります',
                                      selected: _tab == TimerTabKind.totalThenShot,
                                      onTap: () => setState(
                                          () => _tab = TimerTabKind.totalThenShot),
                                    ),
                                  ),
                                  if (_tab == TimerTabKind.totalThenShot) ...[
                                    const SizedBox(height: 6),
                                    _TimerBottomBand(
                                      height: timerBandH,
                                      title: '時間の設定',
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Expanded(
                                            child: _TimerNumericField(
                                              label: '各自',
                                              controller: _aTotal,
                                              suffix: '分',
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: _TimerNumericField(
                                              label: '時間切れ後',
                                              controller: _aShot,
                                              suffix: '秒',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                        Widget tileB() => SizedBox(
                              width: narrow ? double.infinity : null,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    height: cardHeight,
                                    child: _TimerModeTile(
                                      title: 'B  1ショットクロック',
                                      subtitle: '１ショットごとにカウント',
                                      selected: _tab == TimerTabKind.shotClockOnly,
                                      onTap: () => setState(
                                          () => _tab = TimerTabKind.shotClockOnly),
                                    ),
                                  ),
                                  if (_tab == TimerTabKind.shotClockOnly) ...[
                                    const SizedBox(height: 6),
                                    _TimerBottomBand(
                                      height: timerBandH,
                                      title: '時間の設定',
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Expanded(
                                            child: _TimerNumericField(
                                              label: '制限時間',
                                              controller: _bShot,
                                              suffix: '秒',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                        Widget tileC() => SizedBox(
                              width: narrow ? double.infinity : null,
                              child: SizedBox(
                                height: cardHeight,
                                child: _TimerModeTile(
                                  title: 'C  制限なし',
                                  subtitle: 'タイマーなしで進行します',
                                  selected: _tab == TimerTabKind.unlimited,
                                  onTap: () => setState(
                                      () => _tab = TimerTabKind.unlimited),
                                ),
                              ),
                            );
                        Widget tileD() => SizedBox(
                              width: narrow ? double.infinity : null,
                              child: SizedBox(
                                height: cardHeight,
                                child: _TimerModeTile(
                                  title: 'D  制限なし（カウントナイン）',
                                  subtitle: 'カウントナイン専用スコアボード',
                                  selected: _tab == TimerTabKind.countNine,
                                  onTap: () => setState(
                                      () => _tab = TimerTabKind.countNine),
                                ),
                              ),
                            );

                        if (narrow) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              tileA(),
                              const SizedBox(height: 10),
                              tileB(),
                              const SizedBox(height: 10),
                              tileC(),
                              const SizedBox(height: 10),
                              tileD(),
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: tileA(),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: tileB(),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: tileC(),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: tileD(),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (_tab == TimerTabKind.unlimited)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '時間制限なしで進行します。',
                        style: tt.bodyLarge
                            ?.copyWith(color: AppleColors.textSecondary),
                      ),
                    ),
                  if (_tab == TimerTabKind.countNine)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'カウントナインページへ移動して対戦します。',
                        style: tt.bodyLarge
                            ?.copyWith(color: AppleColors.textSecondary),
                      ),
                    ),
                ],
              ),
            ),
            _CardBlock(
              title: 'マッチ設定',
              badge: '任意',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '連続でセットマッチを行う際に利用できる機能です',
                    style: tt.labelLarge?.copyWith(
                      color: AppleColors.glyphGraySecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        '最大セット数',
                        style:
                            tt.bodyMedium?.copyWith(color: AppleColors.textSecondary),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _maxSets,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          selectedItemBuilder: (context) => const [
                            Text('設定しない（スコアのみ）', overflow: TextOverflow.ellipsis),
                            Text('3セット（先取2）', overflow: TextOverflow.ellipsis),
                            Text('5セット（先取3）', overflow: TextOverflow.ellipsis),
                            Text('7セット（先取4）', overflow: TextOverflow.ellipsis),
                            Text('9セット（先取5）', overflow: TextOverflow.ellipsis),
                          ],
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('設定しない（スコアのみ）')),
                            DropdownMenuItem(value: 3, child: Text('3セット（先取2）')),
                            DropdownMenuItem(value: 5, child: Text('5セット（先取3）')),
                            DropdownMenuItem(value: 7, child: Text('7セット（先取4）')),
                            DropdownMenuItem(value: 9, child: Text('9セット（先取5）')),
                          ],
                          onChanged: (v) => setState(() => _maxSets = v ?? 0),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: _targetsValid ? () => _start() : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  '試合開始',
                  style: TextStyle(
                    inherit: true,
                    fontFamily: tt.titleMedium?.fontFamily,
                    fontFamilyFallback: tt.titleMedium?.fontFamilyFallback,
                    fontSize: tt.titleMedium?.fontSize,
                    fontWeight: tt.titleMedium?.fontWeight,
                    letterSpacing: tt.titleMedium?.letterSpacing,
                    height: 1.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'データは端末内のみ保存されます',
                      textAlign: TextAlign.center,
                      style: tt.labelSmall?.copyWith(
                        color: AppleColors.glyphGraySecondary,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '© N3 Products.',
                      textAlign: TextAlign.center,
                      style: tt.labelSmall?.copyWith(
                        color: AppleColors.glyphGraySecondary,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rankDropdown(PlayerRank value, ValueChanged<PlayerRank?> onChanged) {
    return DropdownButton<PlayerRank>(
      value: value,
      underline: const SizedBox.shrink(),
      dropdownColor: AppleColors.white,
      style: Theme.of(context).textTheme.bodyLarge,
      items: PlayerRank.values
          .map(
            (e) => DropdownMenuItem(
              value: e,
              child: Text(e.labelJa),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _CardBlock extends StatelessWidget {
  const _CardBlock({
    required this.title,
    required this.child,
    this.badge,
  });

  final String title;
  final Widget child;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppleCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: tt.titleMedium?.copyWith(
                    color: AppleColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppleColors.separator),
                      borderRadius: BorderRadius.circular(4),
                      color: AppleColors.lightGray,
                    ),
                    child: Text(
                      badge!,
                      style: tt.labelLarge
                          ?.copyWith(color: AppleColors.glyphGraySecondary),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppleColors.textSecondary,
                ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _HandePlayer extends StatelessWidget {
  const _HandePlayer({
    required this.name,
    required this.controller,
    required this.onChanged,
    required this.onDecrement,
    required this.onIncrement,
  });

  final String name;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  static const double _inputFontSize = 36;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: tt.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 19,
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 96, maxWidth: 132),
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                fontSize: _inputFontSize,
                fontWeight: FontWeight.w600,
                height: 1.1,
                color: AppleColors.textPrimary,
                letterSpacing: -0.5,
              ),
              decoration: InputDecoration(
                isDense: false,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 18,
                  horizontal: 12,
                ),
                filled: true,
                fillColor: AppleColors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppleColors.separator),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: AppleColors.separator, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppleColors.appleBlue, width: 2),
                ),
              ),
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _TargetAdjustButton(
              icon: Icons.remove,
              onPressed: onDecrement,
            ),
            const SizedBox(width: 10),
            _TargetAdjustButton(
              icon: Icons.add,
              filled: true,
              onPressed: onIncrement,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '先取点',
          textAlign: TextAlign.center,
          style: tt.bodyMedium?.copyWith(
            color: AppleColors.glyphGraySecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _TargetAdjustButton extends StatelessWidget {
  const _TargetAdjustButton({
    required this.icon,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
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
          width: 34,
          height: 34,
          child: Icon(
            icon,
            size: 20,
            color: filled ? AppleColors.white : AppleColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// タイマー A/B の時間入力枠（[title] が null のときは見出し行なし）
class _TimerBottomBand extends StatelessWidget {
  const _TimerBottomBand({
    required this.height,
    this.title,
    required this.child,
  });

  final double height;
  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final showTitle = title != null && title!.isNotEmpty;
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppleColors.lightGray.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppleColors.separator.withValues(alpha: 0.6)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showTitle) ...[
                Text(
                  title!,
                  style: tt.labelLarge?.copyWith(
                    color: AppleColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _TimerNumericField extends StatelessWidget {
  const _TimerNumericField({
    required this.label,
    required this.controller,
    required this.suffix,
  });

  final String label;
  final TextEditingController controller;
  final String suffix;

  static const OutlineInputBorder _border = OutlineInputBorder();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  isDense: true,
                  labelText: label,
                  filled: true,
                  fillColor: AppleColors.white,
                  border: _border,
                  enabledBorder: _border,
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppleColors.appleBlue, width: 2),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              suffix,
              style: tt.labelLarge?.copyWith(
                color: AppleColors.glyphGraySecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// タイマーモード選択用の大きなカードタイル
class _TimerModeTile extends StatelessWidget {
  const _TimerModeTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final card = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          height: double.infinity,
          alignment: Alignment.topLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: BoxDecoration(
            color: selected
                ? AppleColors.appleBlue.withValues(alpha: 0.1)
                : AppleColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppleColors.appleBlue : AppleColors.separator,
              width: selected ? 2.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppleColors.appleBlue.withValues(alpha: 0.1),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : const [
                    BoxShadow(
                      color: Color(0x12000000),
                      blurRadius: 10,
                      offset: Offset(0, 2),
                    ),
                  ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: tt.titleMedium?.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? AppleColors.appleBlue
                      : AppleColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: tt.bodyMedium?.copyWith(
                  fontSize: 15,
                  height: 1.35,
                  color: selected
                      ? AppleColors.textPrimary.withValues(alpha: 0.78)
                      : AppleColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return card;
  }
}

