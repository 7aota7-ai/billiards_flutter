import 'package:flutter/services.dart';

import 'clock_sound.dart';

void unlockClockSound() {}

void playClockBeep(ClockBeep beep) {
  switch (beep) {
    case ClockBeep.alert:
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    case ClockBeep.countdown:
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.mediumImpact();
    case ClockBeep.expired:
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.vibrate();
  }
}
