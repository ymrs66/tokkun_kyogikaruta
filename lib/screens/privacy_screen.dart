// lib/screens/privacy_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/background_scaffold.dart';
import '../widgets/back_to_home.dart';

const _policyUrl = 'https://doc-hosting.flycricket.io/kyougi-karuta-tokkun-privacy-policy/aeb77bcf-73e8-4707-af0e-0608e39c400d/privacy'; // ←公開URLに差し替え

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  Future<void> _openPolicy(BuildContext context) async {
    final uri = Uri.parse(_policyUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ブラウザを開けませんでした')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BackToHome(
      child: BackgroundScaffold(
      appBar: homeAppBar(context, 'プライバシーポリシー'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('プライバシーポリシーは以下のリンクからご覧いただけます。'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _openPolicy(context),
              icon: const Icon(Icons.open_in_browser),
              label: const Text('ブラウザで開く'),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => context.go('/'),
              child: const Text('ホームに戻る'),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
