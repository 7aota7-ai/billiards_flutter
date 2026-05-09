import 'package:flutter/material.dart';

import '../theme/apple_theme.dart';

/// Elo の説明をポップアップで表示するためのリンク風ウィジェット。
/// 「Elo」に点線下線、[i] アイコンを付け、タップでダイアログを開く。
class EloInfoLink extends StatelessWidget {
  const EloInfoLink({
    super.key,
    this.label = 'Elo',
    this.style,
    this.iconSize = 17,
    this.suffix,
  });

  final String label;
  final TextStyle? style;
  final double iconSize;
  final Widget? suffix;

  static Future<void> showExplanationDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        final tt = Theme.of(ctx).textTheme;
        return AlertDialog(
          title: Text(
            'Elo（Elo rating）',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          content: SingleChildScrollView(
            child: Text(
              '平均的強さのプレイヤーと対戦した際の勝率を対数変換した指標。試合のたびに対戦前の相互のレーティングに基づいて勝利確率を計算し、これと実際の対戦結果との差異に基づいてレーティングを更新します。\n\n'
              'デフォルト値は1500です。',
              style: tt.bodyMedium?.copyWith(height: 1.45),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyMedium;
    final linkStyle = base?.copyWith(
      color: AppleColors.linkBlue,
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: AppleColors.linkBlue,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Semantics(
          button: true,
          label: 'Eloレーティングの説明を表示',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => showExplanationDialog(context),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(label, style: linkStyle),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.info_outline,
                      size: iconSize,
                      color: AppleColors.linkBlue,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (suffix != null) suffix!,
      ],
    );
  }
}
