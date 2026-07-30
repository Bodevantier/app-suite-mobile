// Regenerates lib/app/build_info.dart from the current git state.
//
// Runs automatically after every commit via .git/hooks/post-commit. To run
// it by hand (e.g. to preview before committing):
//   dart run tool/generate_build_info.dart
//
// The output file is committed (not gitignored) so a fresh checkout still
// compiles without running this first — it just shows whatever revision it
// was last generated at until the next commit (or a manual run) updates it.
import 'dart:io';

String _dartString(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n');
  return "'$escaped'";
}

void main() {
  final hash = _git(['rev-parse', '--short', 'HEAD']) ?? 'unknown';
  final hashFull = _git(['rev-parse', 'HEAD']) ?? 'unknown';
  final subject = _git(['log', '-1', '--format=%s']) ?? '';
  final commitDate = _git(['log', '-1', '--format=%cI']) ?? '';
  final branch = _git(['rev-parse', '--abbrev-ref', 'HEAD']) ?? 'unknown';
  final describe =
      _git(['describe', '--tags', '--always', '--dirty']) ?? hash;
  final isDirty = (_run(['status', '--porcelain']) ?? '').trim().isNotEmpty;
  // Total commits reachable from HEAD — a simple, monotonically increasing
  // build counter that's easier to eyeball at a glance than a hash.
  final commitCount =
      int.tryParse(_git(['rev-list', '--count', 'HEAD']) ?? '') ?? 0;
  final generatedAt = DateTime.now().toUtc().toIso8601String();

  final buffer = StringBuffer()
    ..writeln('// GENERATED FILE — do not edit by hand.')
    ..writeln('// Regenerate with: dart run tool/generate_build_info.dart')
    ..writeln()
    ..writeln('/// Snapshot of the git state this app was built from, used by')
    ..writeln('/// the About page. Refreshed automatically by the post-commit')
    ..writeln('/// hook — see .git/hooks/post-commit.')
    ..writeln('class BuildInfo {')
    ..writeln('  static const int gitCommitCount = $commitCount;')
    ..writeln('  static const String gitCommit = ${_dartString(hash)};')
    ..writeln(
        '  static const String gitCommitFull = ${_dartString(hashFull)};')
    ..writeln(
        '  static const String gitCommitSubject = ${_dartString(subject)};')
    ..writeln(
        '  static const String gitCommitDate = ${_dartString(commitDate)};')
    ..writeln('  static const String gitBranch = ${_dartString(branch)};')
    ..writeln('  static const String gitDescribe = ${_dartString(describe)};')
    ..writeln('  static const bool gitDirty = $isDirty;')
    ..writeln(
        '  static const String generatedAt = ${_dartString(generatedAt)};')
    ..writeln('}');

  final file = File('lib/app/build_info.dart');
  file.writeAsStringSync(buffer.toString());
  stdout.writeln('Wrote ${file.path} (commit $hash${isDirty ? ', dirty' : ''})');
}

String? _run(List<String> args) {
  final result = Process.runSync('git', args);
  if (result.exitCode != 0) return null;
  return (result.stdout as String);
}

String? _git(List<String> args) => _run(args)?.trim();
