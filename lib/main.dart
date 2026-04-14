import 'package:flutter/material.dart';

import 'screens/ball_layout_editor_screen.dart';
import 'screens/bowlard_record_screen.dart';
import 'screens/count_nine_screen.dart';
import 'screens/game_screen.dart';
import 'screens/setup_screen.dart';
import 'services/game_session_storage.dart';
import 'theme/apple_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final restored = await GameSessionStorage.load();
  final initialRoute = _normalizeInitialRoute();
  runApp(BilliardsApp(initialRoute: initialRoute, restored: restored));
}

class BilliardsApp extends StatelessWidget {
  const BilliardsApp({
    super.key,
    required this.initialRoute,
    required this.restored,
  });

  final String initialRoute;
  final GameSessionData? restored;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ビリヤードスコア',
      debugShowCheckedModeBanner: false,
      theme: buildAppleTheme(),
      initialRoute: initialRoute,
      onGenerateRoute: (settings) {
        final name = settings.name ?? '/setup';
        switch (name) {
          case '/':
          case '/setup':
            return MaterialPageRoute<void>(
              settings: const RouteSettings(name: '/setup'),
              builder: (_) => const SetupScreen(),
            );
          case '/layout':
            return MaterialPageRoute<void>(
              settings: const RouteSettings(name: '/layout'),
              builder: (_) => const BallLayoutEditorScreen(),
            );
          case '/bowlard':
            return MaterialPageRoute<void>(
              settings: const RouteSettings(name: '/bowlard'),
              builder: (_) => const BowlardRecordScreen(),
            );
          case '/count-nine':
            final args = settings.arguments;
            if (args is CountNineArgs) {
              return MaterialPageRoute<void>(
                settings: const RouteSettings(name: '/count-nine'),
                builder: (_) => CountNineScreen(
                  p1Name: args.p1Name,
                  p2Name: args.p2Name,
                  p1Rank: args.p1Rank,
                  p2Rank: args.p2Rank,
                ),
              );
            }
            return MaterialPageRoute<void>(
              settings: const RouteSettings(name: '/setup'),
              builder: (_) => const SetupScreen(),
            );
          case '/scoreboard':
            final args = settings.arguments;
            if (args is GameScreenArgs) {
              return MaterialPageRoute<void>(
                settings: const RouteSettings(name: '/scoreboard'),
                builder: (_) => GameScreen(setup: args.setup),
              );
            }
            if (restored != null) {
              return MaterialPageRoute<void>(
                settings: const RouteSettings(name: '/scoreboard'),
                builder: (_) => GameScreen(
                  setup: restored!.setup,
                  restoredSession: restored,
                ),
              );
            }
            return MaterialPageRoute<void>(
              settings: const RouteSettings(name: '/setup'),
              builder: (_) => const SetupScreen(),
            );
          default:
            return MaterialPageRoute<void>(
              settings: const RouteSettings(name: '/setup'),
              builder: (_) => const SetupScreen(),
            );
        }
      },
    );
  }
}

String _normalizeInitialRoute() {
  final path = Uri.base.path.trim();
  if (path.isEmpty || path == '/') return '/setup';
  const allowed = {'/setup', '/scoreboard', '/layout', '/bowlard', '/count-nine'};
  return allowed.contains(path) ? path : '/setup';
}
