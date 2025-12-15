import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/screens/settings_screen.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Logout requires password when folder is locked', (WidgetTester tester) async {
    const password = '123';
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    
    SharedPreferences.setMockInitialValues({
      'folder_is_locked': true,
      'folder_lock_password': digest.toString(),
      'isLoggedIn': true,
    });

    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(),
      ),
    );

    await tester.pumpAndSettle();
    final logoutIconFinder = find.byIcon(Icons.logout);
    expect(logoutIconFinder, findsOneWidget);

    await tester.tap(logoutIconFinder);
    await tester.pumpAndSettle();
    expect(find.text('验证密码'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(find.text('确定'));
    await tester.pump();
    
    expect(find.text('密码错误'), findsOneWidget);
    expect(find.text('验证密码'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('确定要退出登录吗？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    
    expect(find.text('确定要退出登录吗？'), findsNothing);
  });
}
