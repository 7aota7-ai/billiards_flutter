/// 1秒ごとの tick() で進むショットクロック（UI のタイマーから駆動する）。
enum ShotClockEvent {
  none,

  /// 残り [ShotClock.alertAt] 秒になった（1回だけ）
  alert,

  /// 残り [ShotClock.countdownFrom] 秒以下のカウントダウン（毎秒）
  countdown,

  /// 0秒になった
  expired,
}

class ShotClock {
  ShotClock({this.shotSec = defaultShotSec}) : remaining = shotSec;

  static const int defaultShotSec = 45;
  static const int alertAt = 15;
  static const int countdownFrom = 5;

  int shotSec;
  int remaining;
  bool running = false;

  void start() {
    if (remaining <= 0) remaining = shotSec;
    running = true;
  }

  void pause() => running = false;

  /// 次のショットのために満タンに戻して計測を始める。
  void resetAndRun() {
    remaining = shotSec;
    running = true;
  }

  /// 満タンに戻して止める（ラック間・試合終了時）。
  void stopAndReset() {
    remaining = shotSec;
    running = false;
  }

  /// エクステンション：残り時間に1ショット分を足して計測を続ける。
  void extend() {
    remaining += shotSec;
    running = true;
  }

  void setShotSec(int sec) {
    if (sec <= 0) return;
    shotSec = sec;
    if (!running) remaining = sec;
  }

  ShotClockEvent tick() {
    if (!running) return ShotClockEvent.none;
    remaining--;
    if (remaining <= 0) {
      remaining = 0;
      running = false;
      return ShotClockEvent.expired;
    }
    if (remaining <= countdownFrom) return ShotClockEvent.countdown;
    if (remaining == alertAt) return ShotClockEvent.alert;
    return ShotClockEvent.none;
  }
}
