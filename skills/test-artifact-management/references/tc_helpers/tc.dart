/// TC ID helper for Dart `test` and Flutter `flutter_test`.
///
/// Dart's `test()` runs the body inside a callback and does not expose the
/// currently-running test name to the body. We solve this by wrapping
/// `test()` and `testWidgets()` so the TC IDs are recorded at registration
/// time (keyed by the test description).
///
/// Usage (pure Dart / dart test):
/// ```dart
/// import 'tc.dart';
///
/// void main() {
///   tcTest(['TC-SY-001'], 'login success', () {
///     // ... assertions
///   });
/// }
/// ```
///
/// Usage (Flutter widget tests):
/// ```dart
/// import 'package:flutter_test/flutter_test.dart';
/// import 'tc.dart';
///
/// void main() {
///   tcTestWidgets(['TC-SY-001'], 'login form renders', (tester) async {
///     // ... pump + expect
///   });
/// }
/// ```
///
/// Sidecar path: `test/results/tc-map.jsonl` (override via TC_SIDECAR env).
/// The Makefile `test` target truncates the sidecar before each run.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

String _sidecarPath() =>
    Platform.environment['TC_SIDECAR'] ?? 'test/results/tc-map.jsonl';

/// Parse StackTrace.current to find the caller test file path.
/// Returns empty string when not derivable.
String _callerTestFile() {
  final lines = StackTrace.current.toString().split('\n');
  final cwd = Directory.current.path + Platform.pathSeparator;
  for (final raw in lines) {
    final line = raw.trim();
    // Skip own frames + dart sdk + package frames
    if (line.contains('tc.dart:') ||
        line.contains('tcTest ') ||
        line.contains('_record ') ||
        line.contains('_callerTestFile') ||
        line.contains('(dart:') ||      // SDK frames: "(dart:async/..."
        line.contains('(package:')) continue; // package frames
    // Match "<...> (FILE:line:col)" or "<...> FILE:line:col"
    final m = RegExp(r'(?:[(\s]|^)(?:file:\/\/)?([^():\s]+_test\.dart):\d+:\d+\)?').firstMatch(line);
    if (m != null) {
      var f = m.group(1)!;
      if (f.startsWith(cwd)) f = f.substring(cwd.length);
      return f;
    }
  }
  return '';
}

void _record(String description, List<String> ids) {
  if (ids.isEmpty) return;
  final strict = const ['1', 'true', 'yes']
      .contains((Platform.environment['TC_SIDECAR_STRICT'] ?? '').toLowerCase());
  try {
    final file = File(_sidecarPath());
    file.parent.createSync(recursive: true);
    final f = _callerTestFile();
    final testKey = f.isNotEmpty ? '$f::$description' : description;
    final line = jsonEncode({'test': testKey, 'tc_ids': ids});
    file.writeAsStringSync('$line\n',
        mode: FileMode.append, flush: true);
  } catch (e) {
    if (strict) rethrow;
    // best-effort fallback (default)
  }
}

/// Wrapper around `test()` that links the test to one or more TC IDs.
void tcTest(
  List<String> tcIds,
  String description,
  dynamic Function() body, {
  Timeout? timeout,
  dynamic skip,
  dynamic tags,
  Map<String, dynamic>? onPlatform,
  int? retry,
}) {
  _record(description, tcIds);
  test(description, body,
      timeout: timeout,
      skip: skip,
      tags: tags,
      onPlatform: onPlatform,
      retry: retry);
}

/// Flutter-only wrapper around `testWidgets`. Importable lazily; if the host
/// project does not depend on flutter_test, comment this out or move to a
/// separate file `tc_widgets.dart`.
//
// import 'package:flutter_test/flutter_test.dart';
//
// void tcTestWidgets(
//   List<String> tcIds,
//   String description,
//   WidgetTesterCallback body, {
//   bool? skip,
//   Timeout? timeout,
//   Duration? initialTimeout,
//   bool semanticsEnabled = true,
//   TestVariant<Object?> variant = const DefaultTestVariant(),
//   dynamic tags,
// }) {
//   _record(description, tcIds);
//   testWidgets(description, body,
//       skip: skip,
//       timeout: timeout,
//       semanticsEnabled: semanticsEnabled,
//       variant: variant,
//       tags: tags);
// }
