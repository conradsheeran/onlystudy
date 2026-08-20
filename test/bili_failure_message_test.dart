import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import 'package:onlystudy/services/bili_failure.dart';
import 'package:onlystudy/services/bili_failure_message.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<String> messageFor(
    WidgetTester tester,
    Object error, {
    Locale locale = const Locale('zh'),
  }) async {
    late String result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('zh'), Locale('en')],
        locale: locale,
        home: Builder(
          builder: (context) {
            result = error.toUserMessage(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return result;
  }

  testWidgets('BiliFailure 映射到对应本地化文案', (tester) async {
    expect(
      await messageFor(tester, const BiliFailure(BiliFailureKind.network)),
      contains('网络'),
    );
    expect(
      await messageFor(tester, const BiliFailure(BiliFailureKind.unauthorized)),
      contains('登录'),
    );
    expect(
      await messageFor(
        tester,
        const BiliFailure(BiliFailureKind.bizError, code: -403),
      ),
      contains('403'),
    );
  });

  testWidgets('非 BiliFailure 异常不展示 Exception 前缀', (tester) async {
    final message = await messageFor(tester, Exception('boom'));
    expect(message, isNot(contains('Exception')));
    expect(message, isNot(contains('boom')));
  });

  testWidgets('英文环境下不出现中文错误', (tester) async {
    final message = await messageFor(
      tester,
      const BiliFailure(BiliFailureKind.network),
      locale: const Locale('en'),
    );
    expect(message, contains('Network'));
    expect(message, isNot(contains('网络')));
  });
}
