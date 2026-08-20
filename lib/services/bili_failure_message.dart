import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import 'bili_failure.dart';

/// 把 [BiliFailure] 映射为面向用户的本地化文案（OPT-017）。
///
/// 服务层不再返回中文/英文异常文本；UI 根据 [BiliFailureKind]
/// 选择对应的 ARB key，避免英文界面出现中文错误。
extension BiliFailureMessage on Object {
  /// 转换为用户可见错误文案。
  ///
  /// - [BiliFailure] → 按 kind 映射；
  /// - 其他异常 → 通用“操作失败”，不展示 `Exception:` 前缀。
  String toUserMessage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (this is BiliFailure) {
      final failure = this as BiliFailure;
      return switch (failure.kind) {
        BiliFailureKind.unauthorized => l10n.unauthorizedError,
        BiliFailureKind.network => l10n.networkError,
        BiliFailureKind.notFound => l10n.bizError,
        BiliFailureKind.bizError =>
          failure.code != null
              ? l10n.bizErrorWithCode(failure.code!)
              : l10n.bizError,
        BiliFailureKind.unknown => l10n.bizError,
      };
    }
    return l10n.bizError;
  }
}
