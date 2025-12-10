import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  String? _qrUrl;
  String? _qrKey;
  String _statusText = '正在获取二维码...';
  Timer? _timer;
  bool _isExpired = false;

  @override
  void initState() {
    super.initState();
    _loadQRCode();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadQRCode() async {
    setState(() {
      _statusText = '正在加载...';
      _isExpired = false;
    });

    try {
      final data = await _authService.generateQRCode();
      if (mounted) {
        setState(() {
          _qrUrl = data['url'];
          _qrKey = data['qrcode_key'];
          _statusText = '请使用 Bilibili 手机端扫码';
        });
        _startPolling();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = '获取失败: $e';
        });
      }
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_qrKey == null || !mounted) return;

      try {
        final result = await _authService.pollLoginStatus(_qrKey!);
        if (result != null) {
          // 登录成功
          timer.cancel();
          if (mounted) {
            setState(() {
              _statusText = '登录成功! 正在跳转...';
            });
            
            // 保存登录信息
            await _authService.saveLoginInfo(result['url']);

            // 跳转到主页 (清空路由栈)
            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const HomeScreen()),
                (route) => false,
              );
            }
          }
        }
      } catch (e) {
        // 如果是过期或其他严重错误，停止轮询
        if (e.toString().contains('过期')) {
          timer.cancel();
          if (mounted) {
            setState(() {
              _isExpired = true;
              _statusText = '二维码已过期';
            });
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录 Bilibili')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'OnlyStudy',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
                label: const Text('刷新二维码'),
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
            color: _isExpired ? Colors.grey.withValues(alpha: 0.3) : Colors.black,
          ),
          dataModuleStyle: QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: _isExpired ? Colors.grey.withValues(alpha: 0.3) : Colors.black,
          ),
        ),
        if (_isExpired)
          const Icon(Icons.broken_image, size: 50, color: Colors.grey),
      ],
    );
  }
}
