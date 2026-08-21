/// 二维码登录协议的类型化模型。
///
/// 用于替代 `Map<String, dynamic>` 传递登录状态，让 JSON 字段漂移
/// 在编译期被发现（参考 OPT-006）。
class QrLoginChallenge {
  final Uri url;
  final String authCode;

  const QrLoginChallenge({required this.url, required this.authCode});

  factory QrLoginChallenge.fromJson(Map<String, dynamic> json) {
    final url = json['url'];
    final authCode = json['auth_code'];
    if (url is! String || url.isEmpty) {
      throw const FormatException('QR challenge missing url');
    }
    if (authCode is! String || authCode.isEmpty) {
      throw const FormatException('QR challenge missing auth_code');
    }
    return QrLoginChallenge(url: Uri.parse(url), authCode: authCode);
  }
}

/// 已解析的登录凭据（与 saveLoginInfo 写入的字段对应）。
class LoginCredentials {
  final String sessData;
  final String biliJct;
  final String uid;
  final String? refreshToken;

  const LoginCredentials({
    required this.sessData,
    required this.biliJct,
    required this.uid,
    this.refreshToken,
  });
}

/// 二维码轮询结果状态机。
sealed class QrLoginPollResult {
  const QrLoginPollResult();
}

/// 未扫码或已扫码未确认，继续轮询。
///
/// [code] 为 B 站返回的顶层业务码：
/// - 86039/86101：未扫码
/// - 86090：已扫码，等待手机确认
class QrLoginPending extends QrLoginPollResult {
  final int code;

  const QrLoginPending({this.code = 0});

  /// 是否已扫码（86090），UI 可据此提示“请在手机上确认”。
  bool get scanned => code == 86090;
}

/// 扫码确认成功。
class QrLoginConfirmed extends QrLoginPollResult {
  final LoginCredentials credentials;
  const QrLoginConfirmed(this.credentials);
}

/// 二维码已过期，需要刷新。
class QrLoginExpired extends QrLoginPollResult {
  const QrLoginExpired();
}
