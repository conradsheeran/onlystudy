import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/screens/settings_screen.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Logout requires password when folder is locked', (WidgetTester tester) async {
    // 1. Setup Mock SharedPreferences with a locked state
    final password = '123';
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    
    SharedPreferences.setMockInitialValues({
      'folder_is_locked': true,
      'folder_lock_password': digest.toString(),
      'isLoggedIn': true, // Assume user is logged in
    });

    // 2. Pump SettingsScreen
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(),
      ),
    );

    // Wait for localizations to load if necessary (usually synchronous in tests)
    await tester.pumpAndSettle();

    // 3. Find Logout Button and Tap
    // The logout button has an icon Icons.logout and text from l10n.
    // We can find it by Icon since text might vary by locale (defaults to English usually in tests if not specified).
    final logoutIconFinder = find.byIcon(Icons.logout);
    expect(logoutIconFinder, findsOneWidget);

    await tester.tap(logoutIconFinder);
    await tester.pumpAndSettle(); // Wait for dialog animation

    // 4. Verify Password Dialog Appears
    // My code uses title '验证密码' (Verify Password)
    expect(find.text('验证密码'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // 5. Enter Wrong Password
    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(find.text('确定'));
    await tester.pump(); // Snackbars often need just a pump, not settle? Or simple pump.
    
    // Check for "Password Error" snackbar '密码错误'
    expect(find.text('密码错误'), findsOneWidget);
    
    // Dialog should still be open
    expect(find.text('验证密码'), findsOneWidget);

    // 6. Enter Correct Password
    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    // 7. Verify Confirmation Dialog Appears
    // "Are you sure you want to logout?" -> '确定要退出登录吗？'
    expect(find.text('确定要退出登录吗？'), findsOneWidget);
    
    // 8. Cancel Confirmation
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    
    expect(find.text('确定要退出登录吗？'), findsNothing);
  });
}
