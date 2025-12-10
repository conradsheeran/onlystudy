import 'dart:async';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://passport.bilibili.com',
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Referer': 'https://www.bilibili.com/',
    },
  ));

  // 获取二维码数据
  Future<Map<String, dynamic>> generateQRCode() async {
    try {
      final response = await _dio.get('/x/passport-login/web/qrcode/generate');
      if (response.data['code'] == 0) {
        return response.data['data'];
      } else {
        throw Exception('无法获取二维码: ${response.data['message']}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // 轮询登录状态
  // 返回值: 
  // null: 继续轮询
  // Map: 登录成功，包含 url (内含 cookie)
  // throw: 失败或过期
  Future<Map<String, dynamic>?> pollLoginStatus(String qrcodeKey) async {
    try {
      final response = await _dio.get(
        '/x/passport-login/web/qrcode/poll',
        queryParameters: {'qrcode_key': qrcodeKey},
      );

      final data = response.data['data'];
      final int code = data['code'];

      /*
       code 字典:
       0: 成功
       86101: 未扫码
       86090: 已扫码，未确认
       86038: 二维码过期
      */

      if (code == 0) {
        // 登录成功
        return data;
      } else if (code == 86101 || code == 86090) {
        // 等待中
        return null; 
      } else if (code == 86038) {
        throw Exception('二维码已过期，请刷新');
      } else {
        throw Exception('登录失败: ${data['message']}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // 解析并保存 Cookie
  Future<void> saveLoginInfo(String url) async {
    final Uri uri = Uri.parse(url);
    final prefs = await SharedPreferences.getInstance();

    // 提取关键 Cookie 参数
    final sessData = uri.queryParameters['SESSDATA'];
    final biliJct = uri.queryParameters['bili_jct'];
    final uid = uri.queryParameters['DedeUserID'];

    if (sessData != null) {
      await prefs.setString('SESSDATA', sessData);
    }
    if (biliJct != null) {
      await prefs.setString('bili_jct', biliJct);
    }
    if (uid != null) {
      await prefs.setString('uid', uid);
    }
    
    // 设置登录标记
    await prefs.setBool('isLoggedIn', true);
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isLoggedIn') ?? false;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  // 获取请求头需要的 Cookie 字符串
  Future<String> getCookieString() async {
    final prefs = await SharedPreferences.getInstance();
    final sessData = prefs.getString('SESSDATA') ?? '';
    final biliJct = prefs.getString('bili_jct') ?? '';
    return 'SESSDATA=$sessData; bili_jct=$biliJct'; 
  }

  // 获取 CSRF Token (bili_jct)
  Future<String> getCsrfToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('bili_jct') ?? '';
  }
}
