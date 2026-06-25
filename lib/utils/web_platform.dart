import 'package:flutter/foundation.dart';

/// True on Flutter Web running on iPhone / iPad / Android browsers.
bool get isMobileWeb {
  if (!kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
}

/// True on Flutter Web in desktop browsers (Chrome on Windows, etc.).
bool get isDesktopWeb => kIsWeb && !isMobileWeb;

/// HTML `capture` attribute works only on mobile browsers.
bool get supportsBrowserCameraCapture => isMobileWeb;
