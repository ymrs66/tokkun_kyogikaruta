// lib/widgets/pass_button.dart
import 'package:flutter/material.dart';

/// 見送りボタン（空札ありのときだけ表示）。札と見分けやすい白地・墨色の枠。
class PassButton extends StatelessWidget {
  const PassButton({
    super.key,
    required this.enabled,
    required this.onPressed,
    this.vertical = false,
  });

  /// 受付中だけ押せる（カウントダウン中・判定表示中は薄く表示）
  final bool enabled;
  final VoidCallback onPressed;

  /// 横画面用（縦長のボタン）
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF2B2B2B);
    final label = vertical
        ? const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.pan_tool_outlined, size: 28),
              SizedBox(height: 8),
              Text('見\n送\nり',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, height: 1.2)),
            ],
          )
        : const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.pan_tool_outlined, size: 24),
              SizedBox(width: 10),
              Text('見 送 り',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 4)),
            ],
          );
    return Semantics(
      button: true,
      label: '見送り',
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: OutlinedButton(
          onPressed: enabled ? onPressed : null,
          style: OutlinedButton.styleFrom(
            backgroundColor: const Color(0xFFFFFDF7),
            foregroundColor: ink,
            disabledForegroundColor: ink,
            side: const BorderSide(color: ink, width: 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: EdgeInsets.zero,
          ),
          child: label,
        ),
      ),
    );
  }
}
