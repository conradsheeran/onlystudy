import 'package:flutter/material.dart';
import 'package:onlystudy/l10n/app_localizations.dart';

import '../services/app_bootstrapper.dart';

/// 启动失败界面（OPT-011）。
///
/// 显示失败阶段与重试入口，避免应用在 `runApp()` 前崩溃
/// 或进入“看似启动成功、首次使用时再崩溃”的半初始化状态。
class BootstrapApp extends StatelessWidget {
  const BootstrapApp({super.key, required this.failure, required this.onRetry});

  final BootstrapFailed failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('zh'), Locale('en')],
      theme: ThemeData.dark(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: ThemeMode.dark,
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context)!;
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(
                      l10n.bootstrapFailed,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.bootstrapFailedPhase(failure.phase.name),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
