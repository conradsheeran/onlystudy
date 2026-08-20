import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/qr_login.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://passport.bilibili.com',
    headers: {
      'User-Agent':
          'Mozilla/5.0 BiliDroid/2.0.1 (bbcallen@gmail.com) os/android model/android_hd mobi_app/android_hd build/2001100 channel/master innerVer/2001100 osVer/15 network/2',
      'Referer': 'https://www.bilibili.com/',
    },
  ));

  // HD 版登录接口使用的 appkey/appsec（与 PiliPlus 一致）
  static const String _appKey = 'dfca71928277209b';
  static const String _appSec = 'b5475a8825547a4fc26c7d518eaaa02e';

  /// 生成用于请求的 buvid（B 站客户端风控标识）
  String generateBuvid() {
    final random = Random.secure();
    final md5Str = md5
        .convert(List<int>.generate(16, (_) => random.nextInt(256)))
        .toString();
    return 'XY${md5Str[2]}${md5Str[12]}${md5Str[22]}$md5Str';
  }

  /// APP 端接口签名（appkey + ts + sign）。
  /// 提取为可测试的纯函数：给定固定参数和时间戳，签名结果确定。
  @visibleForTesting
  static Map<String, dynamic> appSign(
    Map<String, dynamic> params, {
    required int timestamp,
  }) {
    final signed = Map<String, dynamic>.from(params);
    signed['appkey'] = _appKey;
    signed['ts'] = timestamp.toString();
    final sortedKeys = signed.keys.toList()..sort();
    final query = sortedKeys
        .map((k) =>
            '${Uri.encodeComponent(k)}=${Uri.encodeComponent(signed[k].toString())}')
        .join('&');
    signed['sign'] =
        md5.convert(utf8.encode('$query$_appSec')).toString();
    return signed;
  }

  Map<String, dynamic> _appSign(Map<String, dynamic> params) {
    return appSign(
      params,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

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

  /// 生成 Bilibili 登录二维码（app 端 HD 版）
  Future<Map<String, dynamic>> generateQRCode() async {
    try {
      final params = _appSign({
        'local_id': '0',
        'platform': 'android',
        'mobi_app': 'android_hd',
      });
      final response = await _dio.post(
        '/x/passport-tv-login/qrcode/auth_code',
        queryParameters: params,
      );
      if (response.data['code'] == 0) {
        return response.data['data'];
      } else {
        throw Exception('无法获取二维码: ${response.data['message']}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 生成并解析为类型化二维码 challenge。
  Future<QrLoginChallenge> generateQrChallenge() async {
    final data = await generateQRCode();
    return QrLoginChallenge.fromJson(Map<String, dynamic>.from(data));
  }

  /// 轮询二维码扫码状态（app 端 HD 版）
  /// 返回值:
  /// null: 继续轮询
  /// Map: 登录成功，包含 token_info + cookie_info
  /// throw: 失败或过期
  Future<Map<String, dynamic>?> pollLoginStatus(String authCode) async {
    try {
      final params = _appSign({
        'auth_code': authCode,
        'local_id': '0',
      });
      final response = await _dio.post(
        '/x/passport-tv-login/qrcode/poll',
        queryParameters: params,
      );

      // 状态判断基于顶层 code（与 PiliPlus 一致）:
      // 0: 登录成功（data 内含 token_info + cookie_info）
      // 86038: 二维码过期
      // 其他(86039/86101 等): 未扫码或已扫码未确认，继续轮询
      final int topCode = response.data['code'] ?? -1;
      if (topCode == 0) {
        // 登录成功，返回 token_info + cookie_info
        return response.data['data'];
      } else if (topCode == 86038) {
        throw Exception('二维码已过期，请刷新');
      } else {
        return null;
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 类型化轮询：基于顶层 code 返回 sealed 结果，不再依赖异常字符串判断过期。
  Future<QrLoginPollResult> pollLoginTyped(String authCode) async {
    try {
      final params = _appSign({
        'auth_code': authCode,
        'local_id': '0',
      });
      final response = await _dio.post(
        '/x/passport-tv-login/qrcode/poll',
        queryParameters: params,
      );

      final int topCode = response.data['code'] ?? -1;
      if (topCode == 0) {
        return QrLoginConfirmed(
          parseLoginCredentials(Map<String, dynamic>.from(response.data['data'])),
        );
      } else if (topCode == 86038) {
        return const QrLoginExpired();
      } else {
        return const QrLoginPending();
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 从成功响应 data 解析登录凭据（不依赖具体 Map 字段）。
  @visibleForTesting
  static LoginCredentials parseLoginCredentials(Map<String, dynamic> data) {
    final cookieInfo = data['cookie_info'] ?? {};
    final cookies = (cookieInfo['cookies'] as List?) ?? [];
    String? sessData;
    String? biliJct;
    String? uid;
    for (final item in cookies) {
      if (item is! Map) continue;
      final name = item['name'];
      final value = item['value']?.toString();
      if (name == 'SESSDATA') {
        sessData = value;
      } else if (name == 'bili_jct') {
        biliJct = value;
      } else if (name == 'DedeUserID') {
        uid = value;
      }
    }

    final tokenInfo = data['token_info'] ?? {};
    final refreshToken = tokenInfo['refresh_token']?.toString();

    if (sessData == null || biliJct == null || uid == null) {
      throw const FormatException('登录失败: 未获取到完整 Cookie');
    }

    return LoginCredentials(
      sessData: sessData,
      biliJct: biliJct,
      uid: uid,
      refreshToken: refreshToken,
    );
  }

  /// 保存解析后的登录凭据。
  Future<void> saveLoginCredentials(LoginCredentials credentials) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('SESSDATA', credentials.sessData);
    await prefs.setString('bili_jct', credentials.biliJct);
    await prefs.setString('uid', credentials.uid);
    if (credentials.refreshToken != null) {
      await prefs.setString('refresh_token', credentials.refreshToken!);
    }
    await prefs.setBool('isLoggedIn', true);
  }

  /// 解析并保存登录凭据（cookie + token）
  Future<void> saveLoginInfo(Map<String, dynamic> data) async {
    final credentials = parseLoginCredentials(data);
    await saveLoginCredentials(credentials);
  }

  /// 检查是否已登录
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isLoggedIn') ?? false;
  }

  /// 注销登录：只删除账号凭据，保留设备级数据（设置、语言、
  /// 锁密码/锁状态、内容选择、本地历史、缓存时间戳）。
  /// 不再使用全局 `prefs.clear()`，避免注销抹掉用户偏好（OPT-005）。
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('SESSDATA');
    await prefs.remove('bili_jct');
    await prefs.remove('uid');
    await prefs.remove('refresh_token');
    await prefs.remove('isLoggedIn');
  }

  /// 保存用户选择显示的收藏夹ID列表
  Future<void> saveVisibleFolderIds(List<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'visible_folder_ids', ids.map((e) => e.toString()).toList());
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
    await prefs.setStringList(
        'visible_season_ids', ids.map((e) => e.toString()).toList());
  }

  /// 获取用户选择显示的合集ID列表
  Future<List<int>> getVisibleSeasonIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('visible_season_ids');
    if (list == null) return [];
    return list.map((e) => int.tryParse(e) ?? 0).where((e) => e != 0).toList();
  }

  /// 保存用户选择显示的 UP 主ID列表
  Future<void> saveVisibleUpIds(List<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'visible_up_ids', ids.map((e) => e.toString()).toList());
  }

  /// 获取用户选择显示的 UP 主ID列表
  Future<List<int>> getVisibleUpIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('visible_up_ids');
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
