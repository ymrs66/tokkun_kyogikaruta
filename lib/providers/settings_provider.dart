// lib/providers/settings_provider.dart
import 'package:hooks_riverpod/hooks_riverpod.dart';

final soundOnProvider = StateProvider<bool>((ref) => true);
final textFlowOnProvider = StateProvider<bool>((ref) => true); // 文字スクロールON/OFF