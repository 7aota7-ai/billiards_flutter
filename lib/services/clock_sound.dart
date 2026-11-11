import 'clock_sound_stub.dart'
    if (dart.library.io) 'clock_sound_io.dart'
    if (dart.library.js_interop) 'clock_sound_web.dart' as impl;

/// ショットクロックの合図の種類
enum ClockBeep {
  /// 残り15秒（1回だけ）
  alert,

  /// 残り5〜1秒（毎秒）
  countdown,

  /// 0秒（時間切れ・自動エクステンション）
  expired,
}

/// ショットクロックの音（と振動）。
///
/// - ネイティブ（iOS/Android アプリ）: OS のシステム音＋振動。
/// - Web: Web Audio API でビープ音を生成して鳴らす。
///   iOS Safari などは「ユーザー操作の中で音を有効化」しないと鳴らないため、
///   ボタンや球のタップ時に [unlock] を呼ぶこと。
class ClockSound {
  ClockSound._();

  /// ユーザー操作（タップ）の中で呼ぶ。Web では音声出力を有効化する。
  static void unlock() => impl.unlockClockSound();

  static void play(ClockBeep beep) => impl.playClockBeep(beep);
}
