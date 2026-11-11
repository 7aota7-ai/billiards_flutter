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
}
