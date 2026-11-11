import 'package:billiards_flutter/models/rotation_game.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('デフォルト目標点は120、ボール番号が得点になる', () {
    final g = RotationGame();
    expect(g.targets, [120, 120]);
    g.pocket(1);
    g.pocket(5);
    expect(g.scores, [6, 0]);
    expect(g.lowestBall, 2);
    expect(g.shooter, 0);
  });

  test('ミスで手番交代、交代後の得点は相手に入る', () {
    final g = RotationGame()..pocket(1);
    g.miss();
    expect(g.shooter, 1);
    g.pocket(2);
    expect(g.scores, [1, 2]);
  });

  test('ファウルでカウント・手番交代、得点で連続ファウルはリセット', () {
    final g = RotationGame()..foul();
    expect(g.fouls, [1, 0]);
    expect(g.shooter, 1);
    g.miss();
    g.pocket(3);
    expect(g.fouls, [0, 0]);
  });

  test('15球で次ラック・勝者ブレイク・履歴', () {
    final g = RotationGame();
    for (var n = 1; n <= 15; n++) {
      g.pocket(n);
    }
    expect(g.scores, [120, 0]);
    expect(g.winner, 0);

    final h = RotationGame(targets: [200, 200]);
    for (var n = 1; n <= 15; n++) {
      h.pocket(n);
    }
    expect(h.rackHistory, [
      [120, 0],
    ]);
    expect(h.rackNumber, 2);
    expect(h.pocketed, isEmpty);
    expect(h.breaker, 0); // 勝者（あなた）がブレイク
    expect(h.shooter, 0);
  });

  test('最後の球を入れた人が次のブレイク（得点の多寡は関係ない）', () {
    final g = RotationGame(targets: [500, 500]);
    for (var n = 1; n <= 14; n++) {
      g.pocket(n);
    }
    g.miss();
    g.pocket(15); // あなた105点、相手15点でも最後を入れた相手がブレイク
    expect(g.breaker, 1);
    expect(g.shooter, 1);
  });

  test('15番が途中でフロックで入った場合、14番を入れた人がブレイク', () {
    final g = RotationGame(targets: [500, 500]);
    g.pocket(1);
    g.pocket(15); // フロック
    for (var n = 2; n <= 10; n++) {
      g.pocket(n);
    }
    g.miss(); // 相手へ
    for (var n = 11; n <= 14; n++) {
      g.pocket(n);
    }
    expect(g.rackNumber, 2);
    expect(g.breaker, 1);
    expect(g.shooter, 1);
  });

  test('キッチンに出せなかった場合のみブレイク交代', () {
    final g = RotationGame();
    expect(g.canBreakFail, isTrue);
    g.breakFailed();
    expect(g.breaker, 1);
    expect(g.shooter, 1);
    expect(g.canBreakFail, isTrue); // 再ブレイクも失敗しうる
    g.pocket(1);
    expect(g.canBreakFail, isFalse);
    g.breakFailed();
    expect(g.breaker, 1);
    g.undo();
    g.undo();
    expect(g.breaker, 0);
  });

  test('目標点は選手ごとに変更でき、到達で勝利', () {
    final g = RotationGame();
    g.setTarget(1, 29);
    g.miss();
    g.pocket(15);
    g.pocket(14);
    expect(g.winner, 1);
    g.pocket(13); // 試合終了後は無効
    expect(g.scores[1], 29);
  });

  test('Undoで直前の状態に戻る（ラック跨ぎ含む）', () {
    final g = RotationGame(targets: [500, 500]);
    for (var n = 1; n <= 15; n++) {
      g.pocket(n);
    }
    expect(g.rackNumber, 2);
    g.undo();
    expect(g.rackNumber, 1);
    expect(g.pocketed.containsKey(15), isFalse);
    expect(g.scores, [105, 0]);
    expect(g.breaker, 0);
  });

  test('開始前のみブレイク変更可、目標点変更は開始扱いにしない', () {
    final g = RotationGame()..setTarget(0, 90);
    g.setBreaker(1);
    expect(g.shooter, 1);
    g.miss();
    g.setBreaker(0);
    expect(g.breaker, 1);
  });

  group('イニング記録', () {
    test('手番を受け取るたびにイニングが増え、得点が記録される', () {
      final g = RotationGame(targets: [500, 500]);
      expect(g.rackInnings(0), 1); // ブレイクで1イニング目
      expect(g.rackInnings(1), 0);
      g.pocket(1);
      g.pocket(2);
      g.miss();
      expect(g.rackInnings(1), 1);
      g.pocket(3);
      g.foul();
      expect(g.rackInnings(0), 2);
      expect([for (final i in g.innings) i.points], [3, 3, 0]);
      expect(g.innings[0].end, InningEnd.miss);
      expect(g.innings[1].end, InningEnd.foul);
      expect(g.innings[2].end, isNull);
    });

    test('ラックが替わるとイニング数は新しいラックで数え直す', () {
      final g = RotationGame(targets: [500, 500]);
      for (var n = 1; n <= 15; n++) {
        g.pocket(n);
      }
      expect(g.rackNumber, 2);
      expect(g.innings[0].end, InningEnd.rackOut);
      expect(g.innings[0].points, 120);
      expect(g.rackInnings(0), 1); // 新ラックのブレイク
      expect(g.rackInnings(1), 0);
    });

    test('ブレイク交代はイニング数・成績に数えない', () {
      final g = RotationGame()..breakFailed();
      expect(g.innings.first.end, InningEnd.breakFailed);
      expect(g.statsFor(0).innings, 0);
      expect(g.shooter, 1);
      expect(g.rackInnings(1), 1);
    });

    test('成績：平均得点・ミス・ファウル・ハイラン・ラック平均', () {
      final g = RotationGame(targets: [500, 500]);
      // ラック1：あなた 1+2+3=6 → ミス、相手 4..15=114 で取り切り
      g.pocket(1);
      g.pocket(2);
      g.pocket(3);
      g.miss();
      for (var n = 4; n <= 15; n++) {
        g.pocket(n);
      }
      // ラック2：相手ブレイク → ファウル、あなた 1 → ミス
      g.foul();
      g.pocket(1);
      g.miss();
      final me = g.statsFor(0);
      expect(me.innings, 2);
      expect(me.points, 7);
      expect(me.misses, 2);
      expect(me.fouls, 0);
      expect(me.highRun, 6);
      expect(me.pointsPerInning, 3.5);
      expect(me.pointsPerRack, 6);
      final opp = g.statsFor(1);
      expect(opp.innings, 3); // 114点のイニング・ファウル・進行中
      expect(opp.fouls, 1);
      expect(opp.highRun, 114);
      expect(opp.pointsPerRack, 114);
    });

    test('取消でイニング記録も戻る', () {
      final g = RotationGame()..pocket(1);
      g.miss();
      expect(g.innings.length, 2);
      g.undo();
      expect(g.innings.length, 1);
      expect(g.innings.single.end, isNull);
      expect(g.innings.single.points, 1);
      g.undo();
      expect(g.innings.single.points, 0);
    });

    test('勝利でイニングを閉じる・開始前のブレイク変更でイニングの選手も替わる', () {
      final g = RotationGame()..setBreaker(1);
      expect(g.innings.single.player, 1);
      g.setTarget(1, 3);
      g.pocket(1);
      g.pocket(2);
      expect(g.winner, 1);
      expect(g.currentInning.end, InningEnd.win);
    });
  });

  test('エクステンションの初期値は両者2回', () {
    expect(RotationGame().extensionLimits, [2, 2]);
  });

  test('もう一度対戦：点数・延長・ファウルをリセットし、目標点・延長回数・先攻は維持', () {
    final g = RotationGame(targets: [200, 200])..setBreaker(1);
    g.setTarget(0, 90);
    g.setExtensionLimit(1, 3);
    for (var n = 1; n <= 15; n++) {
      g.pocket(n); // 相手が取り切り → 相手ブレイク継続
    }
    g.foul();
    g.useExtension();
    g.reset();
    expect(g.scores, [0, 0]);
    expect(g.fouls, [0, 0]);
    expect(g.extensionsLeft, [2, 3]);
    expect(g.extensionLimits, [2, 3]);
    expect(g.targets, [90, 200]);
    expect(g.breaker, 1);
    expect(g.shooter, 1);
    expect(g.rackNumber, 1);
    expect(g.innings.single.player, 1);
    expect(g.canUndo, isFalse);
    expect(g.isStarted, isFalse);
  });
}
