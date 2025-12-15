import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
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

  static const String _prefLockPassword = 'folder_lock_password';
  static const String _prefIsLocked = 'folder_is_locked';

  /// 检查是否设置了收藏夹锁定密码
  Future<bool> isFolderLockSet() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_prefLockPassword);
  }

  /// 设置收藏夹锁定密码 (SHA256加密)
  Future<void> setFolderLockPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    await prefs.setString(_prefLockPassword, digest.toString());
  }

  /// 校验收藏夹锁定密码
  Future<bool> checkFolderLockPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    final storedHash = prefs.getString(_prefLockPassword);
    if (storedHash == null) return false;
    
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return storedHash == digest.toString();
  }

  /// 检查收藏夹选择功能是否处于锁定状态
  Future<bool> isFolderSelectionLocked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefIsLocked) ?? false;
  }

  /// 设置收藏夹选择功能的锁定状态
  Future<void> setFolderSelectionLocked(bool locked) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefIsLocked, locked);
  }

  /// 生成 Bilibili 登录二维码
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

  /// 轮询二维码扫码状态
  /// 返回值: 
  /// null: 继续轮询
  /// Map: 登录成功，包含 url (内含 cookie)
  /// throw: 失败或过期
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

  /// 解析并保存 Cookie
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

  /// 检查是否已登录
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isLoggedIn') ?? false;
  }

  /// 注销登录并清除本地数据
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  /// 保存用户选择显示的收藏夹ID列表
  Future<void> saveVisibleFolderIds(List<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('visible_folder_ids', ids.map((e) => e.toString()).toList());
  }

  /// 获取用户选择显示的收藏夹ID列表
  Future<List<int>> getVisibleFolderIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('visible_folder_ids');
    if (list == null) return [];
    return list.map((e) => int.tryParse(e) ?? 0).where((e) => e != 0).toList();
  }

  /// 保存用户选择显示的合集ID列表
  Future<void> saveVisibleSeasonIds(List<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('visible_season_ids', ids.map((e) => e.toString()).toList());
  }

  /// 获取用户选择显示的合集ID列表
  Future<List<int>> getVisibleSeasonIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('visible_season_ids');
    if (list == null) return [];
    return list.map((e) => int.tryParse(e) ?? 0).where((e) => e != 0).toList();
  }

  /// 获取请求头需要的 Cookie 字符串
  Future<String> getCookieString() async {
    final prefs = await SharedPreferences.getInstance();
    final sessData = prefs.getString('SESSDATA') ?? '';
    final biliJct = prefs.getString('bili_jct') ?? '';
    return 'SESSDATA=$sessData; bili_jct=$biliJct'; 
  }

  /// 获取 CSRF Token (bili_jct)
  Future<String> getCsrfToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('bili_jct') ?? '';
  }
}
