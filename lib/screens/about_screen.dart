import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
  }

  Future<void> _loadAppInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _version = info.version;
    });
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch $url')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.about),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildAvatar(
                'assets/images/logo.webp', 
                label: AppLocalizations.of(context)!.appName,
              ),
              const SizedBox(width: 32),
              _buildAvatar(
                'assets/images/conradsheeran.webp', 
                label: 'Yhe',
              ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              AppLocalizations.of(context)!.slogan,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '${AppLocalizations.of(context)!.version}: $_version',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 48),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(AppLocalizations.of(context)!.githubRepo),
            subtitle: const Text('https://github.com/conradsheeran/onlystudy'),
            onTap: () => _launchUrl('https://github.com/conradsheeran/onlystudy'),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(String assetPath, {required String label}) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              assetPath,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
