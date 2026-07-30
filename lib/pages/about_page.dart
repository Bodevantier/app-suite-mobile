import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app/build_info.dart';

/// General info about the app itself — version and the git revision it was
/// built from. Separate from per-device settings (reached from each node's
/// page), which cover the boat's hardware rather than the app.
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _packageInfo = info);
    });
  }

  String _diagnosticsText() {
    final pkg = _packageInfo;
    final version = pkg == null ? 'unknown' : '${pkg.version}+${pkg.buildNumber}';
    return '''
${pkg?.appName ?? 'SDolve'} $version
Build: #${BuildInfo.gitCommitCount}
Commit: ${BuildInfo.gitCommit}${BuildInfo.gitDirty ? ' (with local changes)' : ''}
Branch: ${BuildInfo.gitBranch}
Commit date: ${BuildInfo.gitCommitDate}
"${BuildInfo.gitCommitSubject}"''';
  }

  void _copyDiagnostics() {
    Clipboard.setData(ClipboardData(text: _diagnosticsText()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pkg = _packageInfo;
    final version = pkg == null ? '…' : '${pkg.version} (build ${pkg.buildNumber})';

    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        actions: [
          IconButton(
            tooltip: 'Copy diagnostics',
            icon: const Icon(Icons.copy_outlined),
            onPressed: _copyDiagnostics,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.sailing_rounded, color: cs.primary, size: 36),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              pkg?.appName ?? 'SDolve',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Version $version  ·  Build #${BuildInfo.gitCommitCount}',
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
            ),
          ),
          const SizedBox(height: 24),
          _SectionCard(
            title: 'Software revision',
            children: [
              _InfoRow(
                label: 'Build',
                value: '#${BuildInfo.gitCommitCount}',
              ),
              _InfoRow(label: 'Commit', value: BuildInfo.gitCommit, monospace: true),
              _InfoRow(label: 'Branch', value: BuildInfo.gitBranch),
              _InfoRow(
                label: 'Commit date',
                value: _formatDate(BuildInfo.gitCommitDate),
              ),
              _InfoRow(label: 'Summary', value: BuildInfo.gitCommitSubject),
              if (BuildInfo.gitDirty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _DirtyBanner(),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'App',
            children: [
              _InfoRow(label: 'Package', value: pkg?.packageName ?? '…'),
              _InfoRow(
                label: 'Build number',
                value: pkg?.buildNumber ?? '…',
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatDate(String isoDate) {
    final parsed = DateTime.tryParse(isoDate);
    if (parsed == null) return isoDate;
    final local = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _DirtyBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: cs.onSurface.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Built with local changes not yet committed to git.',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontFamily: monospace ? 'monospace' : null,
                fontSize: monospace ? 13 : 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
