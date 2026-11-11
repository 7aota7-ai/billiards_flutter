import 'package:web/web.dart' as web;

import 'clock_sound.dart';

web.AudioContext? _ctx;

web.AudioContext? _context() {
  try {
    return _ctx ??= web.AudioContext();
  } catch (_) {
    return null; // Web Audio 非対応ブラウザ
  }
}

/// iOS Safari では、ユーザー操作の中で AudioContext を resume し、
/// 一度でも音（無音でよい）を鳴らすと、以降タイマーからも鳴らせるようになる。
void unlockClockSound() {
  final ctx = _context();
  if (ctx == null) return;
  if (ctx.state != 'running') {
    ctx.resume();
    _tone(ctx, frequency: 440, seconds: 0.01, volume: 0.0001);
  }
}

void playClockBeep(ClockBeep beep) {
  final ctx = _context();
  if (ctx == null) return;
  if (ctx.state != 'running') ctx.resume();
  switch (beep) {
    case ClockBeep.alert:
      // ピピッ（2回）
      _tone(ctx, frequency: 880, seconds: 0.14);
      _tone(ctx, frequency: 880, seconds: 0.14, delay: 0.22);
    case ClockBeep.countdown:
      // ピッ（短く高め）
      _tone(ctx, frequency: 1200, seconds: 0.1);
    case ClockBeep.expired:
      // ピーー（長く低め）
      _tone(ctx, frequency: 660, seconds: 0.8, volume: 0.6);
  }
}

void _tone(
  web.AudioContext ctx, {
  required double frequency,
  required double seconds,
  double delay = 0,
  double volume = 0.5,
}) {
  final start = ctx.currentTime + delay;
  final end = start + seconds;
  final osc = ctx.createOscillator()
    ..type = 'square'
    ..frequency.value = frequency;
  final gain = ctx.createGain();
  // クリックノイズを避けるため短いフェードイン／アウト
  gain.gain
    ..setValueAtTime(0.0001, start)
    ..exponentialRampToValueAtTime(volume, start + 0.01)
    ..setValueAtTime(volume, end - 0.02)
    ..exponentialRampToValueAtTime(0.0001, end);
  osc.connect(gain);
  gain.connect(ctx.destination);
  osc.start(start);
  osc.stop(end + 0.02);
}
