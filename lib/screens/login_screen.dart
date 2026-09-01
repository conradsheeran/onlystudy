import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import '../models/qr_login.dart';
import '../services/auth_service.dart';
import '../services/bili_failure_message.dart';
import '../services/app_navigator.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with WidgetsBindingObserver {
  static const _pollInterval = Duration(milliseconds: 1500);
  static const _pollStuckAfter = Duration(seconds: 15);
  static const _qrCodeValidity = Duration(seconds: 180);

  final AuthService _authService = AuthService();
  String? _qrUrl;
  String? _authCode;
  String _statusText = ''; // Will be set in initState
  Timer? _timer;
  Timer? _pollWatchdogTimer;
  Timer? _qrCountdownTimer;
  DateTime? _qrExpiresAt;
  int _qrCodeSecondsRemaining = 0;
  bool _isExpired = false;
  bool _loginCompleted = false;
  DateTime? _pollStartedAt;
  int _pollGeneration = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _statusText = AppLocalizations.of(context)!.fetchingQRCode;
      });
      _loadQRCode();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pollWatchdogTimer?.cancel();
    _qrCountdownTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 加载并显示登录二维码
  Future<void> _loadQRCode() async {
    if (!mounted) return;
    final requestGeneration = ++_pollGeneration;
    _timer?.cancel();
    _pollWatchdogTimer?.cancel();
    _qrCountdownTimer?.cancel();
    _pollStartedAt = null;
    _qrExpiresAt = null;
    _qrCodeSecondsRemaining = 0;
    _qrUrl = null;
    _authCode = null;
    _loginCompleted = false;
    setState(() {
      _statusText = AppLocalizations.of(context)!.fetchingQRCode;
      _isExpired = false;
    });

    try {
      final challenge = await _authService.generateQrChallenge();
      if (mounted && requestGeneration == _pollGeneration) {
        setState(() {
          _qrUrl = challenge.url.toString();
          _authCode = challenge.authCode;
          _statusText = AppLocalizations.of(context)!.scanQRCode;
        });
        _startQRCodeCountdown();
        _startPolling();
      }
    } catch (e) {
      if (mounted && requestGeneration == _pollGeneration) {
        setState(() {
          _statusText = e.toUserMessage(context);
        });
      }
    }
  }

  void _startQRCodeCountdown() {
    _qrCountdownTimer?.cancel();
    _qrExpiresAt = DateTime.now().add(_qrCodeValidity);
    _qrCodeSecondsRemaining = _qrCodeValidity.inSeconds;
    _qrCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _authCode == null) {
        timer.cancel();
        return;
      }
      final expiresAt = _qrExpiresAt;
      if (expiresAt == null) {
        timer.cancel();
        return;
      }

      final millisecondsRemaining =
          expiresAt.difference(DateTime.now()).inMilliseconds;
      final timestampRemaining = millisecondsRemaining <= 0
          ? 0
          : (millisecondsRemaining + 999) ~/ 1000;
      var remaining = _qrCodeSecondsRemaining - 1;
      if (timestampRemaining < remaining) remaining = timestampRemaining;
      if (remaining < 0) remaining = 0;
      if (remaining > _qrCodeValidity.inSeconds) {
        remaining = _qrCodeValidity.inSeconds;
      }
      if (remaining == 0) {
        _expireQRCode();
        return;
      }
      if (remaining != _qrCodeSecondsRemaining) {
        setState(() {
          _qrCodeSecondsRemaining = remaining;
        });
      }
    });
  }

  void _expireQRCode() {
    if (_isExpired) return;
    _qrCountdownTimer?.cancel();
    _pollGeneration++;
    _pollStartedAt = null;
    _pollWatchdogTimer?.cancel();
    _pollWatchdogTimer = null;
    _timer?.cancel();
    if (!mounted) return;
    setState(() {
      _qrCodeSecondsRemaining = 0;
      _isExpired = true;
      _statusText = AppLocalizations.of(context)!.qrCodeExpired;
    });
  }

  /// 开始轮询二维码扫码状态
  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) {
      unawaited(_pollOnce());
    });
  }

  Future<void> _pollOnce() async {
    if (!mounted || _authCode == null || _isExpired || _loginCompleted) return;

    final startedAt = _pollStartedAt;
    if (startedAt != null) {
      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed < _pollStuckAfter) return;
      _pollGeneration++;
      _pollWatchdogTimer?.cancel();
    }

    final generation = _pollGeneration;
    final authCode = _authCode!;
    final requestStartedAt = DateTime.now();
    _pollStartedAt = requestStartedAt;
    _pollWatchdogTimer?.cancel();
    _pollWatchdogTimer = Timer(_pollStuckAfter, () {
      if (!mounted ||
          generation != _pollGeneration ||
          _pollStartedAt != requestStartedAt) {
        return;
      }
      _pollGeneration++;
      _pollStartedAt = null;
      _pollWatchdogTimer = null;
      unawaited(_pollOnce());
    });

    try {
      final result = await _authService.pollLoginTyped(authCode);
      if (!mounted || generation != _pollGeneration) return;
      switch (result) {
        case QrLoginConfirmed(:final credentials):
          // 登录成功：只保存一次、只导航一次
          if (_loginCompleted) return;
          _loginCompleted = true;
          _pollGeneration++;
          _pollStartedAt = null;
          _pollWatchdogTimer?.cancel();
          _timer?.cancel();
          if (mounted) {
            setState(() {
              _statusText = AppLocalizations.of(context)!.loginSuccess;
            });
          }
          try {
            await _authService.saveLoginCredentials(credentials);
          } catch (e) {
            // 保存凭据失败：不导航，把安全的错误展示给用户
            if (mounted) {
              setState(() {
                _statusText = AppLocalizations.of(
                  context,
                )!.loginFailed(e.toUserMessage(context));
              });
            }
            debugPrint('QR credential save error type=${e.runtimeType}');
            break;
          }
          if (mounted) {
            AppNavigator.resetToFolderSelection(context);
          }
        case QrLoginExpired():
          _expireQRCode();
        case QrLoginPending(:final scanned):
          // 已扫码未确认时提示用户到手机上确认，避免“扫码后没反应”。
          if (scanned && mounted) {
            setState(() {
              _statusText = AppLocalizations.of(
                context,
              )!.scanDetectedConfirm;
            });
          }
          // 未扫码时保持提示继续轮询
          break;
      }
    } catch (e) {
      if (!mounted || generation != _pollGeneration) return;
      // 网络错误：不停止轮询，等待下一次 tick；但把错误展示给用户，
      // 避免“扫码后没反应”这类无反馈的失败。
      setState(() {
        _statusText = AppLocalizations.of(
          context,
        )!.qrPollFailed(e.toUserMessage(context));
      });
      final statusCode = e is DioException ? e.response?.statusCode : null;
      debugPrint('QR poll error type=${e.runtimeType} status=$statusCode');
    } finally {
      if (generation == _pollGeneration) {
        _pollStartedAt = null;
        _pollWatchdogTimer?.cancel();
        _pollWatchdogTimer = null;
      }
    }
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        !mounted ||
        _authCode == null ||
        _isExpired ||
        _loginCompleted) {
      return;
    }
    final expiresAt = _qrExpiresAt;
    if (expiresAt != null) {
      final millisecondsRemaining =
          expiresAt.difference(DateTime.now()).inMilliseconds;
      final remaining = millisecondsRemaining <= 0
          ? 0
          : (millisecondsRemaining + 999) ~/ 1000;
      if (remaining <= 0) {
        _expireQRCode();
        return;
      }
      if (remaining < _qrCodeSecondsRemaining) {
        setState(() {
          _qrCodeSecondsRemaining = remaining;
        });
      }
    }
    _pollGeneration++;
    _pollStartedAt = null;
    _pollWatchdogTimer?.cancel();
    _pollWatchdogTimer = null;
    unawaited(_pollOnce());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.loginBilibili)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              AppLocalizations.of(context)!.appName,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: _buildQRCodeArea(),
            ),
            const SizedBox(height: 24),
            if (_qrUrl != null && !_isExpired) ...[
              Text(
                AppLocalizations.of(context)!.qrCodeRemainingTime(
                  _qrCodeSecondsRemaining,
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
            ],
            Text(
              _statusText,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (_isExpired) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadQRCode,
                icon: const Icon(Icons.refresh),
                label: Text(AppLocalizations.of(context)!.refreshQRCode),
              )
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildQRCodeArea() {
    if (_qrUrl == null) {
      return const SizedBox(
        width: 200,
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        QrImageView(
          data: _qrUrl!,
          version: QrVersions.auto,
          size: 200.0,
          eyeStyle: QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color:
                _isExpired ? Colors.grey.withValues(alpha: 0.3) : Colors.black,
          ),
          dataModuleStyle: QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color:
                _isExpired ? Colors.grey.withValues(alpha: 0.3) : Colors.black,
          ),
        ),
        if (_isExpired)
          const Icon(Icons.broken_image, size: 50, color: Colors.grey),
      ],
    );
  }
}
