import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import 'package:onlystudy/screens/login_screen.dart';
import 'package:onlystudy/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LoginScreen 轮询行为测试（OPT-018）。
///
/// 通过注入记录请求并返回固定响应的 fake Dio adapter 验证：
/// - challenge 字段映射（auth_code/url）
/// - poll 挂起时重复 tick 不发起并发请求（防重入）
/// - 成功只保存凭据一次、只导航一次
class _FakeAdapter implements HttpClientAdapter {
  final List<String> requestedPaths = [];
  final List<Completer<void>> pending = [];

  /// 每个 poll 请求返回的结果；null 表示挂起不响应。
  Map<String, dynamic>? Function()? pollResponder;

  int pollCallCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    requestedPaths.add(path);

    if (path.contains('/qrcode/auth_code')) {
      return _json({
        'code': 0,
        'data': {
          'url':
              'https://passport.bilibili.com/x/passport-tv-login/qrcode/auth_code?auth_code=CODE123',
          'auth_code': 'CODE123',
        },
      });
    }

    if (path.contains('/qrcode/poll')) {
      pollCallCount++;
      final responder = pollResponder;
      if (responder == null) {
        final completer = Completer<void>();
        pending.add(completer);
        await completer.future;
        return _json({
          'code': 0,
          'data': {
            'token_info': {'refresh_token': 'REFRESH'},
            'cookie_info': {
              'cookies': [
                {'name': 'SESSDATA', 'value': 'sess-1'},
                {'name': 'bili_jct', 'value': 'jct-1'},
                {'name': 'DedeUserID', 'value': '12345'},
              ],
            },
          },
        });
      }
      return _json(responder()!);
    }

    return _json({'code': -1, 'message': 'unexpected path $path'});
  }

  ResponseBody _json(Map<String, dynamic> body) {
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  /// 让一个挂起的 poll 请求完成（返回 code 0 登录成功）。
  void completePendingWithSuccess() {
    for (final c in pending) {
      if (!c.isCompleted) c.complete();
    }
    pending.clear();
  }

  @override
  void close({bool force = false}) {}
}


/// 记录导航事件的 observer，用于断言"只导航一次"。
class _RecordingObserver extends NavigatorObserver {
  final List<String> events = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    events.add('push:${route.settings.name ?? route.runtimeType}');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    events.add('replace:${newRoute?.settings.name ?? newRoute?.runtimeType}');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    events.add('pop:${route.settings.name ?? route.runtimeType}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAdapter adapter;
  late Dio dio;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    adapter = _FakeAdapter();
    dio = Dio(BaseOptions(baseUrl: 'https://passport.bilibili.com'))
      ..httpClientAdapter = adapter;
    AuthService().dioForTest = dio;
  });


  Future<void> pumpLogin(
    WidgetTester tester, {
    List<NavigatorObserver> navigatorObservers = const [],
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        navigatorObservers: navigatorObservers,
        home: const LoginScreen(),
      ),
    );
    // 等待 addPostFrameCallback + _loadQRCode 完成
    await tester.pumpAndSettle();
  }

  testWidgets('challenge 字段映射：auth_code 与 url 被读取并开始轮询', (tester) async {
    await pumpLogin(tester);

    expect(
      adapter.requestedPaths,
      contains('/x/passport-tv-login/qrcode/auth_code'),
    );
    expect(find.text('请使用 Bilibili 手机端扫码'), findsOneWidget);
    // poll 每 1.5 秒一次；首 tick 尚未发生
    expect(adapter.pollCallCount, 0);

    // 拆掉 widget 让 Timer 取消
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('poll 挂起时重复 tick 不发起并发请求（防重入）', (tester) async {
    await pumpLogin(tester);

    // 第一个 poll tick 发起并被挂起
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(adapter.pollCallCount, 1);
    expect(adapter.pending, hasLength(1));

    // 多个 tick 过去，仍只有 1 个在途请求
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    expect(adapter.pollCallCount, 1, reason: '上一次请求未完成不得发起新请求');

    adapter.completePendingWithSuccess();
    // 让 dio 内部 Future/timer 链条跑完，避免 pending timer
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      const SizedBox(),
    ); // dispose LoginScreen, cancel timer
  });

  testWidgets('轮询成功只保存一次凭据、只导航一次', (tester) async {
    adapter.pollResponder = () => {
      'code': 0,
      'data': {
        'token_info': {'refresh_token': 'REFRESH'},
        'cookie_info': {
          'cookies': [
            {'name': 'SESSDATA', 'value': 'sess-1'},
            {'name': 'bili_jct', 'value': 'jct-1'},
            {'name': 'DedeUserID', 'value': '12345'},
          ],
        },
      },
    };

    final navigatorObserver = _RecordingObserver();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        navigatorObservers: [navigatorObserver],
        home: const LoginScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // 凭据已保存
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('SESSDATA'), 'sess-1');
    expect(prefs.getString('uid'), '12345');
    expect(prefs.getBool('isLoggedIn'), isTrue);

    // 登录成功只导航一次：除初始 home 外只有一次 MaterialPageRoute push
    final navigationEvents = navigatorObserver.events
        .where((e) => e.startsWith('push:MaterialPageRoute'))
        .toList();
    expect(navigationEvents, hasLength(1));
  });

  testWidgets('已扫码未确认（86090）时提示用户到手机确认', (tester) async {
    adapter.pollResponder = () => {'code': 86090, 'data': null};
    await pumpLogin(tester);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('已扫码，请在手机上确认登录'), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // dispose, cancel timer
  });

  testWidgets('poll 请求超过看门狗时间后会发起新的请求', (tester) async {
    await pumpLogin(tester);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump();
    expect(adapter.pollCallCount, 1);
    expect(adapter.pending, hasLength(1));

    adapter.pollResponder = () => {'code': 86090, 'data': null};
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();

    expect(adapter.pollCallCount, 2);
    expect(find.text('已扫码，请在手机上确认登录'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('回到前台立即补轮询并丢弃旧 generation 响应', (tester) async {
    final navigatorObserver = _RecordingObserver();
    await pumpLogin(tester, navigatorObservers: [navigatorObserver]);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump();
    expect(adapter.pollCallCount, 1);
    expect(adapter.pending, hasLength(1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    await tester.pump();

    expect(adapter.pollCallCount, 2);
    expect(adapter.pending, hasLength(2));

    adapter.completePendingWithSuccess();
    await tester.pumpAndSettle();

    final navigationEvents = navigatorObserver.events
        .where((e) => e.startsWith('push:MaterialPageRoute'))
        .toList();
    expect(navigationEvents, hasLength(1));
    expect((await SharedPreferences.getInstance()).getBool('isLoggedIn'), isTrue);
  });

  testWidgets('二维码显示剩余时间并在180秒后自动过期', (tester) async {
    await pumpLogin(tester);

    expect(find.textContaining('二维码剩余'), findsOneWidget);

    await tester.pump(const Duration(seconds: 179));
    expect(find.textContaining('二维码剩余'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('二维码已过期'), findsOneWidget);
    expect(find.text('刷新二维码'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('二维码区域不提供本机 Bilibili App 入口', (tester) async {
    await pumpLogin(tester);

    expect(find.text('用本机哔哩哔哩 App 扫码'), findsNothing);
    expect(find.byIcon(Icons.open_in_new), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('二维码过期（86038）显示过期并可刷新', (tester) async {
    adapter.pollResponder = () => {'code': 86038, 'data': null};
    await pumpLogin(tester);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('二维码已过期'), findsOneWidget);
    expect(find.text('刷新二维码'), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // dispose, cancel timer
  });
}
