import 'dart:ui';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketr/window_startup.dart';

void main() {
  test('desktop builds should use maximized window startup by default', () {
    expect(
      shouldUseDesktopWindowMaximized(),
      equals(Platform.isWindows || Platform.isLinux || Platform.isMacOS),
    );
  });

  test('1366x768 and smaller startup displays maximize the window', () {
    expect(shouldMaximizeStartupWindow(const Size(1366, 768)), isTrue);
    expect(shouldMaximizeStartupWindow(const Size(1280, 720)), isTrue);
    expect(shouldMaximizeStartupWindow(const Size(1920, 1080)), isFalse);
    expect(shouldMaximizeStartupWindow(const Size(1600, 720)), isFalse);
  });

  test('startup window is centered on the primary display bounds', () {
    expect(
      primaryDisplayWindowPosition(
        displayPosition: const Offset(-1920, 0),
        displaySize: const Size(1920, 1080),
        windowSize: const Size(1459, 866),
      ),
      const Offset(-1689.5, 107),
    );
  });

  test('startup window stays inside a smaller primary display', () {
    expect(
      primaryDisplayWindowPosition(
        displayPosition: const Offset(1920, 0),
        displaySize: const Size(1280, 720),
        windowSize: const Size(1459, 866),
      ),
      const Offset(1920, 0),
    );
  });
}
