import 'dart:io';

import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

bool shouldUseDesktopWindowMaximized() =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

bool shouldMaximizeStartupWindow(Size displaySize) =>
    displaySize.width <= 1366 && displaySize.height <= 768;

Offset primaryDisplayWindowPosition({
  required Offset displayPosition,
  required Size displaySize,
  required Size windowSize,
}) {
  final x = ((displaySize.width - windowSize.width) / 2)
      .clamp(0.0, double.infinity)
      .toDouble();
  final y = ((displaySize.height - windowSize.height) / 2)
      .clamp(0.0, double.infinity)
      .toDouble();
  return displayPosition + Offset(x, y);
}

Future<bool> configureDesktopWindowStartup() async {
  if (!shouldUseDesktopWindowMaximized()) return false;

  await WindowManager.instance.ensureInitialized();
  if (await WindowManager.instance.isVisible()) {
    return !await WindowManager.instance.isMaximized() &&
        !await WindowManager.instance.isFullScreen() &&
        !await WindowManager.instance.isMinimized();
  }

  const windowSize = Size(1459, 866);
  final primaryDisplay = await ScreenRetriever.instance.getPrimaryDisplay();
  final displayPosition = primaryDisplay.visiblePosition ?? Offset.zero;
  final displaySize = primaryDisplay.visibleSize ?? primaryDisplay.size;
  final windowPosition = primaryDisplayWindowPosition(
    displayPosition: displayPosition,
    displaySize: displaySize,
    windowSize: windowSize,
  );

  await WindowManager.instance.waitUntilReadyToShow(
    const WindowOptions(size: windowSize, backgroundColor: Colors.transparent),
  );
  await WindowManager.instance.setAsFrameless();
  await WindowManager.instance.setResizable(false);
  if (shouldMaximizeStartupWindow(primaryDisplay.size)) {
    await WindowManager.instance.maximize();
  } else {
    await WindowManager.instance.setPosition(windowPosition);
  }
  return false;
}

void showDesktopWindowAfterFirstFrame({bool refreshVisibleWindow = false}) {
  if (!shouldUseDesktopWindowMaximized()) return;

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (refreshVisibleWindow) {
      final size = await WindowManager.instance.getSize();
      await WindowManager.instance.setSize(size + const Offset(1, 1));
      await WindowManager.instance.setSize(size);
    }
    await WindowManager.instance.show();
    await WindowManager.instance.focus();
  });
}
