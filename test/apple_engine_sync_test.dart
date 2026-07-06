import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Apple **sync rule**: the AVFoundation engine
/// (`LightCompressor.swift`) and `extensions/Encodable.swift` must stay
/// **byte-identical** between `ios/` and `macos/`. The plugin files
/// (`SwiftLightCompressorPlugin.swift` vs `LightCompressorPlugin.swift`) are
/// per-platform and intentionally excluded.
///
/// When a case here fails you edited one copy without mirroring it: edit the
/// iOS copy, then copy it verbatim to the matching macOS path.
///
/// Runs under `flutter test` (so CI gates it). Paths are relative to the
/// package root, which is the working directory `flutter test` uses.
void main() {
  const iosRoot = 'ios/light_compressor_v2/Sources/light_compressor_v2';
  const macosRoot = 'macos/light_compressor_v2/Sources/light_compressor_v2';

  // Paths (under each platform's Sources root) that must be byte-identical.
  const syncedFiles = <String>[
    'LightCompressor.swift',
    'extensions/Encodable.swift',
  ];

  group('Apple engine sync rule (iOS <-> macOS byte-identical)', () {
    for (final relativePath in syncedFiles) {
      test('$relativePath is byte-identical across ios/ and macos/', () {
        final iosFile = File('$iosRoot/$relativePath');
        final macosFile = File('$macosRoot/$relativePath');

        expect(
          iosFile.existsSync(),
          isTrue,
          reason: 'Missing iOS copy: ${iosFile.path} '
              '(run `flutter test` from the package root).',
        );
        expect(
          macosFile.existsSync(),
          isTrue,
          reason: 'Missing macOS copy: ${macosFile.path} '
              '(run `flutter test` from the package root).',
        );

        final iosBytes = iosFile.readAsBytesSync();
        final macosBytes = macosFile.readAsBytesSync();

        expect(
          _firstDifference(iosBytes, macosBytes),
          isNull,
          reason: 'Apple sync rule violated: $relativePath differs between '
              'ios/ and macos/ (${iosBytes.length} vs ${macosBytes.length} '
              'bytes). These files must be byte-identical — edit the iOS copy, '
              'then copy it verbatim to the macOS path.',
        );
      });
    }
  });
}

/// Returns a human-readable locator for the first byte that differs (or where
/// one copy ends), or `null` when [a] and [b] are byte-identical.
String? _firstDifference(List<int> a, List<int> b) {
  final shorter = a.length < b.length ? a.length : b.length;
  var line = 1;
  var column = 1;
  for (var i = 0; i < shorter; i++) {
    if (a[i] != b[i]) {
      return 'first differ at line $line, column $column (byte $i)';
    }
    if (a[i] == 0x0a) {
      line++;
      column = 1;
    } else {
      column++;
    }
  }
  if (a.length != b.length) {
    return 'one copy is longer (diverges at line $line, byte $shorter)';
  }
  return null;
}
