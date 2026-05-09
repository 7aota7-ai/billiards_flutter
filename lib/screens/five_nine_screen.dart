import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/opponent_record.dart';
import '../services/opponent_repository.dart';
import '../services/self_profile_repository.dart';
import '../theme/apple_theme.dart';

class _PlayerRow {
  _PlayerRow({
    required this.id,
    required String name,
  }) : controller = TextEditingController(text: name);

  final String id;
  final TextEditingController controller;

  String get name => controller.text.trim();

  void dispose() => controller.dispose();
}

class _ScoreEntry {
  const _ScoreEntry({
    required this.playerId,
    required this.playerName,
    required this.points,
  });

  final String playerId;
  final String playerName;
  final int points;
}

class FiveNineScreen extends StatefulWidget {
  const FiveNineScreen({super.key});

  @override
  State<FiveNineScreen> createState() => _FiveNineScreenState();
}

class _FiveNineScreenState extends State<FiveNineScreen> {
  final _oppRepo = OpponentRepository();
  final _selfRepo = SelfProfileRepository();

  StoredSelfProfile? _self;
  List<OpponentRecord> _opponents = [];
  final List<_PlayerRow> _players = [
    _PlayerRow(id: 'local-1', name: 'プレイヤー1'),
    _PlayerRow(id: 'local-2', name: 'プレイヤー2'),
  ];
  final List<TextEditingController> _pointBalls = [
    TextEditingController(text: '5'),
    TextEditingController(text: '9'),
  ];

  int _scorePlayer = 0;
  int _inning = 1;
  final List<_ScoreEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    Future.wait([_oppRepo.ensureLoaded(), _selfRepo.ensureLoaded()]).then((_) {
      if (!mounted) return;
      setState(() {
        _self = _selfRepo.load();
        _opponents = _oppRepo.getAll()
          ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
        if (_self != null) {
          _players[0].controller.text = _self!.displayName;
        }
      });
    });
  }

  @override
  void dispose() {
    for (final p in _players) {
      p.dispose();
    }
    for (final c in _pointBalls) {
      c.dispose();
    }
    super.dispose();
  }

  String _playerName(int index) {
    final t = _players[index].name;
    return t.isEmpty ? 'プレイヤー${index + 1}' : t;
  }

  int _totalFor(int playerIndex) {
    var sum = 0;
    for (final e in _entries) {
      if (e.playerId == _players[playerIndex].id) sum += e.points;
    }
    return sum;
  }

  void _addPlayer() {
    setState(() {
      _players.add(
        _PlayerRow(
          id: 'local-${DateTime.now().microsecondsSinceEpoch}',
          name: 'プレイヤー${_players.length + 1}',
        ),
      );
    });
  }

  void _removePlayer(int index) {
    if (_players.length <= 2) return;
    setState(() {
      _players.removeAt(index).dispose();
      if (_scorePlayer >= _players.length) _scorePlayer = _players.length - 1;
    });
  }

  void _onReorderPlayers(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final selectedId = _players[_scorePlayer.clamp(0, _players.length - 1)].id;
      final item = _players.removeAt(oldIndex);
      _players.insert(newIndex, item);
      var ni = _players.indexWhere((p) => p.id == selectedId);
      if (ni < 0) ni = 0;
      _scorePlayer = ni.clamp(0, _players.length - 1);
    });
  }

  void _addPointBall() {
    setState(() {
      _pointBalls.add(TextEditingController());
    });
  }

  void _removePointBall(int index) {
    setState(() {
      _pointBalls.removeAt(index).dispose();
    });
  }

  Future<void> _pickRegisteredPlayer(int index) async {
    final all = <String, String>{};
    if (_self != null) {
      all[_self!.id] = _self!.displayName;
    }
    for (final o in _opponents) {
      all[o.id] = o.displayName;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        if (all.isEmpty) {
          return const SafeArea(
            child: SizedBox(
              height: 140,
              child: Center(child: Text('登録済みプレイヤーがありません')),
            ),
          );
        }
        final entries = all.entries.toList();
        return SafeArea(
          child: SizedBox(
            height: 380,
            child: ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final e = entries[i];
                return ListTile(
                  title: Text(e.value),
                  subtitle: Text(e.key),
                  onTap: () {
                    setState(() {
                      _players[index].controller.text = e.value;
                    });
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _adjustScoreFor(int playerIndex, int sign) {
    final delta = sign;
    final player = _players[playerIndex];
    final name = _playerName(playerIndex);
    setState(() {
      _scorePlayer = playerIndex;
      _entries.insert(
        0,
        _ScoreEntry(
          playerId: player.id,
          playerName: name,
          points: delta,
        ),
      );
      // 5-9想定: 誰かが加点したら、プレイしていない全員に同値の減点を自動反映。
      if (delta > 0) {
        for (var i = 0; i < _players.length; i++) {
          if (i == playerIndex) continue;
          _entries.insert(
            0,
            _ScoreEntry(
              playerId: _players[i].id,
              playerName: _playerName(i),
              points: -delta,
            ),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: buildAppleGlassAppBar(context, title: '5-9（たたき台）', centerTitle: true),
      body: AppleContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            AppleCard(
              borderColor: AppleColors.systemGreen.withValues(alpha: 0.5),
              borderWidth: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('スコア記録（入力はここ）',
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppleColors.systemGreen,
                      )),
                  const SizedBox(height: 12),
                  Text(
                    '左の＝を長押ししながら上下にドラッグして並べ替えできます。タップで選択、+ / - で点数調整。',
                    style: tt.bodyMedium?.copyWith(color: AppleColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: math.min(460, math.max(120.0, _players.length * 84.0 + 24)),
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.all(0),
                      buildDefaultDragHandles: false,
                      itemCount: _players.length,
                      onReorder: _onReorderPlayers,
                      itemBuilder: (context, i) {
                        final p = _players[i];
                        return Material(
                          key: ValueKey(p.id),
                          color: Colors.transparent,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ReorderableDragStartListener(
                                  index: i,
                                  child: const Padding(
                                    padding: EdgeInsets.only(top: 8, right: 4),
                                    child: Icon(
                                      Icons.drag_handle,
                                      color: AppleColors.glyphGraySecondary,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () {
                                        setState(() => _scorePlayer = i);
                                      },
                                      child: Ink(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: _scorePlayer == i
                                                ? AppleColors.appleBlue
                                                : AppleColors.separator,
                                            width: _scorePlayer == i ? 2 : 1,
                                          ),
                                          color: _scorePlayer == i
                                              ? AppleColors.appleBlue
                                                  .withValues(alpha: 0.08)
                                              : AppleColors.white,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 9),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  _playerName(i),
                                                  style: tt.bodyLarge,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Text(
                                                '${_totalFor(i)}点',
                                                style: tt.labelLarge?.copyWith(
                                                  color: AppleColors.textSecondary,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              FilledButton.tonal(
                                                onPressed: () => _adjustScoreFor(i, 1),
                                                style: FilledButton.styleFrom(
                                                  minimumSize: const Size(0, 34),
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 10, vertical: 0),
                                                ),
                                                child: const Text('+'),
                                              ),
                                              const SizedBox(width: 4),
                                              FilledButton.tonal(
                                                onPressed: () => _adjustScoreFor(i, -1),
                                                style: FilledButton.styleFrom(
                                                  minimumSize: const Size(0, 34),
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 10, vertical: 0),
                                                ),
                                                child: const Text('-'),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('イニング', style: tt.bodyLarge),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: () => setState(() => _inning = _inning > 1 ? _inning - 1 : 1),
                        style: FilledButton.styleFrom(minimumSize: const Size(36, 34), padding: EdgeInsets.zero),
                        child: const Text('−'),
                      ),
                      const SizedBox(width: 8),
                      Text('$_inning', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: () => setState(() => _inning += 1),
                        style: FilledButton.styleFrom(minimumSize: const Size(36, 34), padding: EdgeInsets.zero),
                        child: const Text('＋'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('現在の合計点', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  for (var i = 0; i < _players.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(child: Text(_playerName(i), style: tt.bodyLarge)),
                          Text('${_totalFor(i)} 点',
                              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('記録一覧', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  if (_entries.isEmpty)
                    Text('まだありません。上の「記録」で追加してください。',
                        style: tt.bodyMedium?.copyWith(color: AppleColors.glyphGraySecondary))
                  else
                    for (var i = 0; i < _entries.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '${i + 1}. ${_entries[i].playerName} / ${_entries[i].points > 0 ? '+' : ''}${_entries[i].points}',
                          style: tt.bodyMedium,
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('参加プレイヤー', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  if (_self != null)
                    Text('登録済みの自分: ${_self!.displayName}',
                        style: tt.labelLarge?.copyWith(color: AppleColors.glyphGraySecondary)),
                  if (_opponents.isNotEmpty)
                    Text('登録済み相手: ${_opponents.length}名',
                        style: tt.labelLarge?.copyWith(color: AppleColors.glyphGraySecondary)),
                  const SizedBox(height: 8),
                  Text(
                    '左の＝をドラッグして並べ替え。上と同順になります。',
                    style: tt.labelLarge?.copyWith(color: AppleColors.glyphGraySecondary),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: math.min(460, math.max(120.0, _players.length * 58.0 + 24)),
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.all(0),
                      buildDefaultDragHandles: false,
                      itemCount: _players.length,
                      onReorder: _onReorderPlayers,
                      itemBuilder: (context, eIndex) {
                        final row = _players[eIndex];
                        return Material(
                          key: ValueKey('edit-${row.id}'),
                          color: Colors.transparent,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                ReorderableDragStartListener(
                                  index: eIndex,
                                  child: const Padding(
                                    padding: EdgeInsets.only(top: 6, right: 4),
                                    child: Icon(
                                      Icons.drag_handle,
                                      color: AppleColors.glyphGraySecondary,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: row.controller,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      labelText: 'プレイヤー ${eIndex + 1}',
                                      border: const OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '登録済みから選択',
                                  onPressed: () => _pickRegisteredPlayer(eIndex),
                                  icon: const Icon(Icons.manage_search_rounded),
                                ),
                                IconButton(
                                  onPressed: _players.length <= 2 ? null : () => _removePlayer(eIndex),
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addPlayer,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('プレイヤーを追加'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('点球リスト', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('得点対象にする球番です。点数は上の「スコア記録」で入力します。',
                      style: tt.bodyMedium?.copyWith(color: AppleColors.textSecondary)),
                  const SizedBox(height: 8),
                  for (final e in _pointBalls.asMap().entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: e.value,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: '点球 ${e.key + 1}',
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _removePointBall(e.key),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _addPointBall,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('点球を追加'),
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
