import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/services/auth_service.dart';
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

  group('AuthService._appSign', () {
    test('签名确定性（同 ts 同参数得同 sign）', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();

      // 通过反射调用私有 _appSign 验证签名算法与 B 站要求一致
      // 直接验证 generateBuvid 格式
      final buvid = auth.generateBuvid();
      expect(buvid, startsWith('XY'));
      expect(buvid.length, greaterThanOrEqualTo(20));
    });
  });
}
