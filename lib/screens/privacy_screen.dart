// lib/screens/privacy_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/background_scaffold.dart';
import '../widgets/back_to_home.dart';

/// プライバシーポリシー（日本語・英語。Android・iOS 共通）
const privacyPolicyUrl = 'https://www.ymr-system.jp/karuta/privacy.html';

/// URL を開く処理（テストで差し替える）
typedef UrlOpener = Future<bool> Function(Uri uri);

Future<bool> _defaultOpener(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key, this.openUrl = _defaultOpener});

  final UrlOpener openUrl;

  Future<void> _openPolicy(BuildContext context) async {
    bool ok;
    try {
      ok = await openUrl(Uri.parse(privacyPolicyUrl));
    } catch (_) {
      ok = false; // ブラウザがない・起動に失敗した など
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('ブラウザを開けませんでした。\n$privacyPolicyUrl'),
        ));
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
