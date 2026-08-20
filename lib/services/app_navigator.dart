import 'package:flutter/material.dart';

import '../models/bili_models.dart';
import '../models/history_entry.dart';
import '../screens/about_screen.dart';
import '../screens/download_screen.dart';
import '../screens/folder_content_screen.dart';
import '../screens/history_screen.dart';
import '../screens/login_screen.dart';
import '../screens/main_screen.dart';
import '../screens/season_content_screen.dart';
import '../screens/select_folders_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/up_space_screen.dart';
import '../screens/video_player_screen.dart';

/// 类型化导航模块（OPT-013）。
///
/// 页面通过静态方法表达“导航意图”，不再直接 import 目标页面文件并
/// 构造 `MaterialPageRoute`，从而消除页面间的导航环依赖
/// （MainScreen → SettingsScreen → LoginScreen → SelectFoldersScreen → Main）。
///
/// 不引入 GetX/go_router；当前页面数量下 Flutter 原生导航足够。
abstract final class AppNavigator {
  /// 前往登录页并清空导航栈。
  static void resetToLogin(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  /// 前往主界面并清空导航栈。
  static void resetToMain(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const MainScreen()),
      (route) => false,
    );
  }

  /// 首次登录后进入内容选择页并清空导航栈。
  static void resetToFolderSelection(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (context) => const SelectFoldersScreen(isFirstLogin: true)),
      (route) => false,
    );
  }

  /// 前往内容选择页（设置页入口）。
  static Future<void> toFolderSelection(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SelectFoldersScreen()),
    );
  }

  /// 前往关于页。
  static Future<void> toAbout(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AboutScreen()),
    );
  }

  /// 前往收藏夹内容页。
  static Future<void> toFolderContent(BuildContext context, Folder folder) {
    return Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => FolderContentScreen(folder: folder)),
    );
  }

  /// 前往合集内容页。
  static Future<void> toSeasonContent(BuildContext context, Season season) {
    return Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => SeasonContentScreen(season: season)),
    );
  }

  /// 前往 UP 主主页。
  static Future<void> toUpSpace(
    BuildContext context,
    int mid, {
    String? initialName,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) =>
              UpSpaceScreen(mid: mid, initialName: initialName)),
    );
  }

  /// 前往视频播放页。
  static Future<void> toVideoPlayer(
    BuildContext context, {
    required List<Video> playlist,
    required int initialIndex,
    String? localFilePath,
    HistoryEntry? initialHistoryEntry,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(
          playlist: playlist,
          initialIndex: initialIndex,
          localFilePath: localFilePath,
          initialHistoryEntry: initialHistoryEntry,
        ),
      ),
    );
  }

  /// 前往下载管理页。
  static Future<void> toDownloads(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DownloadScreen()),
    );
  }

  /// 前往观看历史页。
  static Future<void> toHistory(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const HistoryScreen()),
    );
  }

  /// 前往设置页。
  static Future<void> toSettings(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
  }
}
