import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import '../models/qr_login.dart';
import '../services/auth_service.dart';
import '../services/bili_failure_message.dart';
import 'select_folders_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  String? _qrUrl;
  String? _authCode;
  String _statusText = ''; // Will be set in initState
  Timer? _timer;
  bool _isExpired = false;
  bool _pollInFlight = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _statusText = AppLocalizations.of(context)!.fetchingQRCode;
      });
      _loadQRCode();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 加载并显示登录二维码
  Future<void> _loadQRCode() async {
    if (!mounted) return;
    setState(() {
      _statusText = AppLocalizations.of(context)!.fetchingQRCode;
      _isExpired = false;
    });

    try {
      final challenge = await _authService.generateQrChallenge();
      if (mounted) {
        setState(() {
          _qrUrl = challenge.url.toString();
          _authCode = challenge.authCode;
          _statusText = AppLocalizations.of(context)!.scanQRCode;
        });
        _startPolling();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = e.toUserMessage(context);
        });
      }
    }
  }

  /// 开始轮询二维码扫码状态
  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_authCode == null || !mounted) return;
      // 防重入：上一次请求未完成时不发起新请求
      if (_pollInFlight) return;

      _pollInFlight = true;
      try {
        final result = await _authService.pollLoginTyped(_authCode!);
        switch (result) {
          case QrLoginConfirmed(:final credentials):
            // 登录成功：只保存一次、只导航一次
            timer.cancel();
            if (mounted) {
              setState(() {
                _statusText = AppLocalizations.of(context)!.loginSuccess;
              });
            }
            await _authService.saveLoginCredentials(credentials);
            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                    builder: (context) =>
                        const SelectFoldersScreen(isFirstLogin: true)),
                (route) => false,
              );
            }
          case QrLoginExpired():
            timer.cancel();
            if (mounted) {
              setState(() {
                _isExpired = true;
                _statusText = AppLocalizations.of(context)!.qrCodeExpired;
              });
            }
          case QrLoginPending():
            // 继续轮询
            break;
        }
      } catch (e) {
        // 网络错误：不停止轮询，等待下一次 tick
        debugPrint('QR poll error: $e');
      } finally {
        _pollInFlight = false;
      }
    });
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
