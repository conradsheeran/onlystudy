import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/models/qr_login.dart';
import 'package:onlystudy/services/auth_service.dart';
import 'package:onlystudy/services/bili_failure.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService.saveLoginInfo', () {
    test('解析 cookie_info/token_info 并保存凭据', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();

      // 模拟 B 站 app 端扫码登录成功响应（data 字段）
      await auth.saveLoginInfo({
        'token_info': {
          'mid': 123456,
          'access_token': 'access_token_value',
          'refresh_token': 'refresh_token_value',
          'expires_in': 15552000,
        },
        'cookie_info': {
          'cookies': [
            {'name': 'SESSDATA', 'value': 'sess_value', 'http_only': 1},
            {'name': 'bili_jct', 'value': 'csrf_value', 'http_only': 0},
            {'name': 'DedeUserID', 'value': '123456', 'http_only': 0},
            {
              'name': 'DedeUserID__ckMd5',
              'value': 'ckmd5_value',
              'http_only': 0
            },
            {'name': 'sid', 'value': 'sid_value', 'http_only': 0},
          ],
          'domains': ['.bilibili.com'],
        },
        'sso': ['https://passport.bilibili.com/api/v2/sso'],
      });

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('SESSDATA'), 'sess_value');
      expect(prefs.getString('bili_jct'), 'csrf_value');
      expect(prefs.getString('uid'), '123456');
      expect(prefs.getString('refresh_token'), 'refresh_token_value');
      expect(prefs.getBool('isLoggedIn'), isTrue);
    });

    test('缺少关键 Cookie 时抛出异常', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();

      // 缺少 SESSDATA
      expect(
        () => auth.saveLoginInfo({
          'cookie_info': {
            'cookies': [
              {'name': 'bili_jct', 'value': 'csrf_value'},
              {'name': 'DedeUserID', 'value': '123456'},
            ],
          },
        }),
        throwsA(isA<Exception>()),
      );
    });

    test('cookies 为 null 或空时抛出异常', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();

      expect(
        () => auth.saveLoginInfo({
          'cookie_info': {'cookies': null}
        }),
        throwsA(isA<Exception>()),
      );
      expect(
        () => auth.saveLoginInfo({}),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('AuthService 凭据读取', () {
    test('保存后 getCookieString/getUserId/getCsrfToken 可读取', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();

      await auth.saveLoginInfo({
        'token_info': {'refresh_token': 'refresh_token_value'},
        'cookie_info': {
          'cookies': [
            {'name': 'SESSDATA', 'value': 'sess_value'},
            {'name': 'bili_jct', 'value': 'csrf_value'},
            {'name': 'DedeUserID', 'value': '987654'},
          ],
        },
      });

      final prefs = await SharedPreferences.getInstance();
      expect(await auth.getCookieString(),
          'SESSDATA=sess_value; bili_jct=csrf_value');
      expect(prefs.getString('uid'), '987654');
      expect(await auth.getCsrfToken(), 'csrf_value');
      expect(await auth.isLoggedIn(), isTrue);
    });

    test('未登录时 prefs 无 uid 且 isLoggedIn 为 false', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('uid'), isNull);
      expect(await auth.isLoggedIn(), isFalse);
    });
  });

  group('AuthService.logout', () {
    test('注销只清除账号凭据，保留设备级数据', () async {
      SharedPreferences.setMockInitialValues({
        'SESSDATA': 'sess_value',
        'bili_jct': 'csrf_value',
        'uid': '123456',
        'refresh_token': 'refresh_token_value',
        'isLoggedIn': true,
        // 设备级数据：语言、设置、锁、内容选择、历史、缓存时间戳
        'app_locale': 'zh',
        'default_resolution': 80,
        'folder_lock_password': 'hash',
        'folder_is_locked': true,
        'visible_folder_ids': ['1', '2'],
        'visible_season_ids': ['3'],
        'visible_up_ids': ['4'],
        'local_watch_history_entries': ['{}'],
        'last_cache_clear_timestamp': 12345,
      });
      final auth = AuthService();

      await auth.logout();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('SESSDATA'), isNull);
      expect(prefs.getString('bili_jct'), isNull);
      expect(prefs.getString('uid'), isNull);
      expect(prefs.getString('refresh_token'), isNull);
      expect(prefs.getBool('isLoggedIn'), isNull);
      expect(await auth.isLoggedIn(), isFalse);

      // 设备级数据必须保留
      expect(prefs.getString('app_locale'), 'zh');
      expect(prefs.getInt('default_resolution'), 80);
      expect(prefs.getString('folder_lock_password'), 'hash');
      expect(prefs.getBool('folder_is_locked'), isTrue);
      expect(prefs.getStringList('visible_folder_ids'), ['1', '2']);
      expect(prefs.getStringList('visible_season_ids'), ['3']);
      expect(prefs.getStringList('visible_up_ids'), ['4']);
      expect(prefs.getStringList('local_watch_history_entries'), ['{}']);
      expect(prefs.getInt('last_cache_clear_timestamp'), 12345);
    });

    test('未登录时 logout 不抛错', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();
      await auth.logout();
      expect(await auth.isLoggedIn(), isFalse);
    });
  });

  group('AuthService.appSign', () {
    test('固定参数和时间戳产生确定签名向量', () {
      final signed = AuthService.appSign({
        'local_id': '0',
        'platform': 'android',
        'mobi_app': 'android_hd',
      }, timestamp: 1700000000);

      expect(signed['appkey'], 'dfca71928277209b');
      expect(signed['ts'], '1700000000');
      // 已知签名向量（独立于 Dart 实现计算）
      expect(signed['sign'], 'dd272e45c74b628f1fb818a56127c4f1');
    });

    test('不修改传入参数', () {
      final input = {'local_id': '0'};
      AuthService.appSign(input, timestamp: 1700000000);
      expect(input.containsKey('appkey'), isFalse);
      expect(input.containsKey('sign'), isFalse);
    });

    test('buvid 格式', () {
      final auth = AuthService();
      final buvid = auth.generateBuvid();
      expect(buvid, startsWith('XY'));
      expect(buvid.length, greaterThanOrEqualTo(20));
    });

    test('getBuvid 首次生成并持久化到 prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();
      final buvid = await auth.getBuvid();
      expect(buvid, startsWith('XY'));

      // 已写入 prefs，供重启后复用
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('buvid'), buvid);

      // 同一实例内保持稳定
      expect(await auth.getBuvid(), buvid);
    });
  });

  group('QrLoginChallenge', () {
    test('解析完整 challenge', () {
      final challenge = QrLoginChallenge.fromJson({
        'url': 'https://passport.bilibili.com/x/passport-tv-login/h5/qrcode/scan?auth_code=abc',
        'auth_code': 'abc123',
      });
      expect(challenge.url.toString(), contains('auth_code=abc'));
      expect(challenge.authCode, 'abc123');
    });

    test('缺少 auth_code 时抛出解析失败', () {
      expect(
        () => QrLoginChallenge.fromJson({
          'url': 'https://example.com/qr',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('缺少 url 时抛出解析失败', () {
      expect(
        () => QrLoginChallenge.fromJson({
          'auth_code': 'abc123',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('QrLoginPollResult 类型判断', () {
    test('sealed 类型可被模式匹配区分', () {
      QrLoginPollResult result = const QrLoginPending();
      expect(result, isA<QrLoginPending>());
      expect(result, isNot(isA<QrLoginConfirmed>()));
      expect(result, isNot(isA<QrLoginExpired>()));
    });
  });
  group('AuthService 登录错误类型化（OPT-017）', () {
    test('parseLoginCredentials 缺 Cookie 抛 BiliFailure 而非中文 FormatException', () {
      expect(
        () => AuthService.parseLoginCredentials({
          'cookie_info': {
            'cookies': [
              {'name': 'bili_jct', 'value': 'csrf'},
              {'name': 'DedeUserID', 'value': '123'},
            ],
          },
        }),
        throwsA(
          isA<BiliFailure>().having((f) => f.kind, 'kind', BiliFailureKind.notFound),
        ),
      );
    });

    test('pollLoginStatus 二维码过期抛 BiliFailure(code 86038)', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();
      final adapter = _FixedResponseAdapter({'code': 86038, 'data': null});
      auth.dioForTest = Dio(BaseOptions(baseUrl: 'https://passport.bilibili.com'))
        ..httpClientAdapter = adapter;

      await expectLater(
        auth.pollLoginStatus('CODE'),
        throwsA(
          isA<BiliFailure>().having(
            (f) => f.code,
            'code',
            86038,
          ),
        ),
      );
    });
  });
}

/// 返回固定 JSON 响应的 Dio adapter（供 pollLoginStatus 等测试注入）。
class _FixedResponseAdapter implements HttpClientAdapter {
  _FixedResponseAdapter(this.body);

  final Map<String, dynamic> body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
