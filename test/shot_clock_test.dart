import 'package:billiards_flutter/models/rotation_game.dart';
import 'package:billiards_flutter/models/shot_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('デフォルト45秒、15秒で1回アラート、5秒前からカウントダウン、0で時間切れ', () {
    final c = ShotClock()..start();
    expect(c.shotSec, 45);
    final events = <int, ShotClockEvent>{};
    while (c.running) {
      final e = c.tick();
      if (e != ShotClockEvent.none) events[c.remaining] = e;
    }
    expect(events[15], ShotClockEvent.alert);
    for (var s = 5; s >= 1; s--) {
      expect(events[s], ShotClockEvent.countdown);
    }
    expect(events[0], ShotClockEvent.expired);
    expect(events.length, 7);
  });

  test('停止中は進まない・エクステンションで1ショット分追加', () {
    final c = ShotClock(shotSec: 45);
    expect(c.tick(), ShotClockEvent.none);
    expect(c.remaining, 45);
    c.start();
    for (var i = 0; i < 45; i++) {
      c.tick();
    }
    expect(c.running, isFalse);
    c.extend();
    expect(c.remaining, 45);
    expect(c.running, isTrue);
  });

  test('秒数変更は停止中なら即反映', () {
    final c = ShotClock()..setShotSec(30);
    expect(c.remaining, 30);
    c.resetAndRun();
    c.tick();
    c.setShotSec(60);
    expect(c.remaining, 29);
    c.resetAndRun();
    expect(c.remaining, 60);
  });

  test('エクステンション回数：選手ごと、使い切ったら false、取消で戻る', () {
    final g = RotationGame(extensions: [3, 2]);
    expect(g.extensionsLeft, [3, 2]);
    expect(g.useExtension(), isTrue);
    expect(g.extensionsLeft, [2, 2]);
    g.undo();
    expect(g.extensionsLeft, [3, 2]);
    g.miss();
    expect(g.useExtension(), isTrue);
    expect(g.useExtension(), isTrue);
    expect(g.useExtension(), isFalse);
    expect(g.extensionsLeft, [3, 0]);
  });

  test('上限変更は使用済み回数を維持', () {
    final g = RotationGame(extensions: [2, 2])..useExtension();
    g.setExtensionLimit(0, 3);
    expect(g.extensionLimits[0], 3);
    expect(g.extensionsLeft[0], 2);
    g.setExtensionLimit(0, 0);
    expect(g.extensionsLeft[0], 0);
  });
}
