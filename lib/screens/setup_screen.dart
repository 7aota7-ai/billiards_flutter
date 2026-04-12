import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/scoreboard_models.dart';
import '../models/opponent_record.dart';
import '../services/opponent_repository.dart';
import '../services/self_profile_repository.dart';
import '../theme/apple_theme.dart';
import 'game_screen.dart';

/// `_LabeledRow` のラベル列幅。入力・リンクの左端を揃える。
const double _kLabeledContentInset = 52;

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _oppRepo = OpponentRepository();
  final _selfRepo = SelfProfileRepository();
  final _p1Name = TextEditingController(text: 'あなた');
  final _p2Name = TextEditingController(text: '相手');
  final _p2Search = TextEditingController();
  PlayerRank _p1Rank = PlayerRank.b;
  PlayerRank _p2Rank = PlayerRank.a;

  /// 検索で選んだ既存相手。未設定なら試合開始時に新規採番
  String? _p2OpponentId;
  List<OpponentRecord> _p2SearchResults = [];
  List<OpponentRecord> _topCandidates = [];

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
    _p2SearchResults = _oppRepo.search(_p2Search.text);
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

  void _applyOpponent(OpponentRecord o) {
    setState(() {
      _p2OpponentId = o.id;
      _p2Name.text = o.displayName;
      _p2Rank = o.rank;
      _p2Search.text = o.displayName;
      _refreshOpponentUi();
    });
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
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                        color: AppleColors.glyphGraySecondary,
                                      ),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1, thickness: 0.5),
                                itemBuilder: (context, i) {
                                  final o = filtered[i];
                                  return ListTile(
                                    title: Text(o.displayName),
                                    subtitle: Text('${o.id} · ${o.rank.labelJa}'),
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
    final ok = v1 != null &&
        v2 != null &&
        v1 >= 1 &&
        v1 <= 99 &&
        v2 >= 1 &&
        v2 <= 99;
    setState(() => _targetsValid = ok);
  }

  Future<void> _start() async {
    _validateTargets();
    if (!_targetsValid) return;

    final v1 = int.parse(_t1.text);
    final v2 = int.parse(_t2.text);
    final p1 = _p1Name.text.trim().isEmpty ? 'P1' : _p1Name.text.trim();
    final p2 = _p2Name.text.trim().isEmpty ? 'P2' : _p2Name.text.trim();

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

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => GameScreen(setup: setup),
      ),
    );
    if (mounted) {
      setState(_refreshOpponentUi);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: buildAppleGlassAppBar(
        context,
        title: 'スコアボード設定',
        centerTitle: true,
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
                      _rankDropdown(_p1Rank, (v) => setState(() => _p1Rank = v!)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: _kLabeledContentInset),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _saveMyProfile,
                      child: const Text('自分の情報を登録'),
                    ),
                  ),
                ),
                Builder(
                  builder: (context) {
                    final self = _selfRepo.load();
                    if (self == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(left: _kLabeledContentInset, top: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'ユーザID: ${self.id}',
                          style: tt.labelSmall?.copyWith(
                            color: AppleColors.glyphGraySecondary,
                          ),
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
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _rankDropdown(_p2Rank, (v) => setState(() => _p2Rank = v!)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'よく対戦する相手',
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
                                onTap: () => _applyOpponent(_topCandidates[i]),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: AppleColors.separator),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
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
                                          color: AppleColors.glyphGraySecondary,
                                        ),
                                      ),
                                      if (_topCandidates[i].matchCount > 0) ...[
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
                      if (_p2OpponentId != null) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: InputChip(
                            label: Text('ユーザID: $_p2OpponentId'),
                            onDeleted: () => setState(() => _p2OpponentId = null),
                          ),
                        ),
                      ],
                      if (_p2SearchResults.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 168),
                          child: Material(
                            color: AppleColors.lightGray,
                            borderRadius: BorderRadius.circular(8),
                            clipBehavior: Clip.antiAlias,
                            child: ListView.separated(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: _p2SearchResults.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1, thickness: 0.5),
                              itemBuilder: (context, i) {
                                final o = _p2SearchResults[i];
                                return ListTile(
                                  dense: true,
                                  title: Text(o.displayName),
                                  subtitle: Text('${o.id} · ${o.rank.labelJa}'),
                                  onTap: () => _applyOpponent(o),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () async {
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
                          },
                          child: const Text('今の名前・級で新規登録'),
                        ),
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
                      final cardHeight = (128 + w * 0.12).clamp(200.0, 260.0);
                      const narrowBreak = 600.0;
                      final narrow = w < narrowBreak;

                      Widget tileA() => SizedBox(
                            height: cardHeight,
                            width: narrow ? double.infinity : null,
                            child: _TimerModeTile(
                              title: 'A  持ち時間',
                              subtitle: '各自の持ち時間のあと、1ショットタイマーに切り替わります',
                              selected: _tab == TimerTabKind.totalThenShot,
                              onTap: () => setState(() => _tab = TimerTabKind.totalThenShot),
                            ),
                          );
                      Widget tileB() => SizedBox(
                            height: cardHeight,
                            width: narrow ? double.infinity : null,
                            child: _TimerModeTile(
                              title: 'B  1ショットクロック',
                              subtitle: '1ショットごとにカウント。一時停止・リセットは相手が操作',
                              selected: _tab == TimerTabKind.shotClockOnly,
                              onTap: () => setState(() => _tab = TimerTabKind.shotClockOnly),
                            ),
                          );
                      Widget tileC() => SizedBox(
                            height: cardHeight,
                            width: narrow ? double.infinity : null,
                            child: _TimerModeTile(
                              title: 'C  制限なし',
                              subtitle: 'タイマーなしで進行します',
                              selected: _tab == TimerTabKind.unlimited,
                              onTap: () => setState(() => _tab = TimerTabKind.unlimited),
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
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: tileB(),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: tileC(),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                if (_tab == TimerTabKind.totalThenShot) ...[
                  // IntrinsicHeight+stretch は初回レイアウトで intrinsic と実高さが 1px ずれて overflow しやすい
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _TimerOptColumn(
                          label: '持ち時間（各自）',
                          field: _aTotal,
                          suffix: '分',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TimerOptColumn(
                          label: '時間切れ後の1ショット',
                          field: _aShot,
                          suffix: '秒',
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '持ち時間が切れたら1ショットタイマーに切り替わります。',
                      style: tt.labelLarge?.copyWith(
                        color: AppleColors.glyphGraySecondary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
                if (_tab == TimerTabKind.shotClockOnly) ...[
                  _OptRow(
                    label: '1ショットの制限時間',
                    field: _bShot,
                    suffix: '秒',
                    min: 5,
                    max: 300,
                    compact: true,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'スタート後にカウントダウン。一時停止・リセットは相手が操作します。',
                      style: tt.labelLarge?.copyWith(
                        color: AppleColors.glyphGraySecondary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
                if (_tab == TimerTabKind.unlimited)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '時間制限なしで進行します。',
                      style: tt.bodyLarge?.copyWith(color: AppleColors.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
          _CardBlock(
            title: 'マッチ設定',
            badge: '任意',
            child: Row(
              children: [
                Text(
                  '最大セット数',
                  style: tt.bodyMedium?.copyWith(color: AppleColors.textSecondary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _maxSets,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
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
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              onPressed: _targetsValid ? () => _start() : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('試合開始'),
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppleColors.separator),
                      borderRadius: BorderRadius.circular(4),
                      color: AppleColors.lightGray,
                    ),
                    child: Text(
                      badge!,
                      style: tt.labelLarge?.copyWith(color: AppleColors.glyphGraySecondary),
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
  });

  final String name;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

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
              style: TextStyle(
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
                  borderSide: const BorderSide(color: AppleColors.separator, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppleColors.appleBlue, width: 2),
                ),
              ),
              onChanged: onChanged,
            ),
          ),
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

/// モードA: 持ち時間・ショット時間（横並び・フォント拡大）
class _TimerOptColumn extends StatelessWidget {
  const _TimerOptColumn({
    required this.label,
    required this.field,
    required this.suffix,
  });

  final String label;
  final TextEditingController field;
  final String suffix;

  static const double _scale = 1.2;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final labelFs = (tt.labelLarge?.fontSize ?? 14) * _scale;
    final fieldFs = (tt.bodyLarge?.fontSize ?? 17) * _scale;
    final suffixStyle = tt.labelLarge?.copyWith(
      fontSize: labelFs * 0.95,
      color: AppleColors.glyphGraySecondary,
      fontWeight: FontWeight.w500,
    );

    final borderRadius = BorderRadius.circular(8);
    final outlineBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: const BorderSide(color: AppleColors.separator),
    );
    final outlineFocused = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: const BorderSide(color: AppleColors.appleBlue, width: 2),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: tt.labelLarge?.copyWith(
            fontSize: labelFs,
            color: AppleColors.textSecondary,
            fontWeight: FontWeight.w500,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 68,
              child: TextField(
                controller: field,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(
                  fontSize: fieldFs,
                  fontWeight: FontWeight.w600,
                  color: AppleColors.textPrimary,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: AppleColors.white,
                  contentPadding: EdgeInsets.symmetric(
                    vertical: (10 * _scale).floorToDouble(),
                    horizontal: 8,
                  ),
                  border: outlineBorder,
                  enabledBorder: outlineBorder,
                  focusedBorder: outlineFocused,
                  disabledBorder: outlineBorder,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(suffix, style: suffixStyle),
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
                  color: selected ? AppleColors.appleBlue : AppleColors.textPrimary,
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

class _OptRow extends StatelessWidget {
  const _OptRow({
    required this.label,
    required this.field,
    required this.suffix,
    required this.min,
    required this.max,
    this.compact = false,
  });

  final String label;
  final TextEditingController field;
  final String suffix;
  final int min;
  final int max;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
          color: AppleColors.textSecondary,
          fontWeight: FontWeight.w500,
        );
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 4 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (compact)
            SizedBox(
              width: 148,
              child: Text(label, style: labelStyle),
            )
          else
            Expanded(
              child: Text(label, style: labelStyle),
            ),
          if (compact) const SizedBox(width: 10),
          SizedBox(
            width: 56,
            child: TextField(
              controller: field,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            suffix,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppleColors.glyphGraySecondary,
                ),
          ),
        ],
      ),
    );
  }
}
