/// Bilibili 请求失败的类型化结果（OPT-007）。
///
/// 服务层抛 [BiliFailure] 而不是包含中文文案的 `Exception`，
/// UI 通过 [kind] 映射到本地化文案，避免英文界面出现中文错误。
class BiliFailure implements Exception {
  const BiliFailure(this.kind, {this.code, this.message});

  final BiliFailureKind kind;

  /// Bilibili 业务错误码（`response.data['code']`），可能为空。
  final int? code;

  /// 服务端返回的 message（仅用于调试日志，不直接展示给用户）。
  final String? message;

  /// 是否属于“未登录/凭据失效”，UI 可据此引导重新登录。
  bool get isUnauthorized => kind == BiliFailureKind.unauthorized;

  @override
  String toString() {
    final buf = StringBuffer('BiliFailure($kind');
    if (code != null) buf.write(', code=$code');
    if (message != null && message!.isNotEmpty) buf.write(', message=$message');
    buf.write(')');
    return buf.toString();
  }
}

enum BiliFailureKind {
  /// 未登录或凭据失效（如 SESSDATA 过期、uid 缺失）。
  unauthorized,

  /// Bilibili 业务 code != 0（如接口参数错误、风控拒绝）。
  bizError,

  /// 网络层失败（无网络、超时、连接被拒等）。
  network,

  /// 资源不存在或响应结构不符合预期。
  notFound,

  /// 其他未分类错误。
  unknown,
}
