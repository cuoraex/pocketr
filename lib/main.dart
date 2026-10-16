import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'app_localization.dart';
import 'backup.dart';
import 'data.dart';
import 'finance_database.dart';
import 'finance_excel.dart';
import 'hpp_import.dart';
import 'hpp_template.dart';
import 'local_file_archive.dart';
import 'manual_sales_import.dart';
import 'sales_template.dart';
import 'shopee_excel.dart';
import 'window_startup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final refreshVisibleWindow = await configureDesktopWindowStartup();
  runApp(const PocketRApp());
  showDesktopWindowAfterFirstFrame(refreshVisibleWindow: refreshVisibleWindow);
}

const _blue = Color(0xff2f7de1);
const _appVersion = '1.2.2';
const _ink = Color(0xff10202c);
const _muted = Color(0xff52697b);
const _green = Color(0xff1f8f4f);
const _red = Color(0xffe5534b);
const _orange = Color(0xffee9b36);
const _popupTintColor = Color(0xffcfe7f3);
const _popupTintOpacity = .96;
const _slideUpDuration = Duration(milliseconds: 420);
const _slideUpDistance = 10.0;
const _slideUpCurve = Curves.easeOutCubic;
const _slideUpStaggerMilliseconds = 40;
const _slideUpMaxStaggerRows = 5;
final _windowTransitionInProgress = ValueNotifier<bool>(false);
final _appNotification = ValueNotifier<_AppNotification?>(null);
final Future<Uint8List> _defaultBrandImageBytes = _loadDefaultBrandImageBytes();
const _windowStateChannel = MethodChannel('pocketr/window_state');

bool _isSqliteDatabase(Uint8List bytes) =>
    bytes.length >= 16 &&
    String.fromCharCodes(bytes.take(16)) == 'SQLite format 3\u0000';

Future<Uint8List> _loadDefaultBrandImageBytes() async {
  try {
    final data = await rootBundle.load('assets/images/pocketr_default.png');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (error, stackTrace) {
    debugPrint('Could not load the default profile image: $error\n$stackTrace');
    rethrow;
  }
}

bool _bytesEqual(Uint8List first, Uint8List second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

class _AppNotification {
  const _AppNotification({
    required this.message,
    required this.isError,
    required this.width,
  });

  final String message;
  final bool isError;
  final double? width;
}

class _BackupProgressStatus {
  const _BackupProgressStatus({
    this.message = '',
    this.isError = false,
    this.isLoading = false,
  });

  final String message;
  final bool isError;
  final bool isLoading;
}

Future<T> _withOutsideDismissedPicker<T>(
  Future<T> Function() showPicker,
) async {
  if (!Platform.isWindows) return showPicker();

  final hookInstalled =
      await _windowStateChannel.invokeMethod<bool>(
        'dismissDialogOnOutsideClick',
      ) ??
      false;
  if (!hookInstalled) {
    throw StateError('Gagal mengaktifkan penutup dialog file.');
  }
  try {
    return await showPicker();
  } finally {
    await _windowStateChannel.invokeMethod<void>('stopDismissDialog');
  }
}

class _ShopeeImportLine {
  const _ShopeeImportLine({
    required this.date,
    required this.product,
    required this.productName,
    required this.qty,
    required this.color,
    required this.size,
    required this.other,
    required this.weight,
  });

  final String date;
  final Product product;
  final String productName;
  final double qty;
  final String color;
  final String size;
  final String other;
  final double weight;
}

Widget _windowAwareBlur({
  required Widget child,
  required double sigmaX,
  double? sigmaY,
  bool enabled = true,
}) => ValueListenableBuilder<bool>(
  valueListenable: _windowTransitionInProgress,
  child: child,
  builder: (context, transitioning, content) {
    // Backdrop blur on many cards inside a scroll view flickers on phone GPUs.
    if (transitioning || !enabled || Platform.isAndroid) return content!;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigmaX, sigmaY: sigmaY ?? sigmaX),
      child: content,
    );
  },
);

ImageProvider<Object>? _imageFromData(String source) {
  if (source.isEmpty) return null;
  try {
    final separator = source.indexOf(',');
    return MemoryImage(
      base64Decode(separator < 0 ? source : source.substring(separator + 1)),
    );
  } on FormatException {
    return null;
  }
}

String _imageMimeFromName(String name) =>
    switch (p.extension(name).toLowerCase()) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.webp' => 'image/webp',
      _ => 'image/png',
    };

Widget _normalDialogTransition(Animation<double> animation, Widget child) {
  final transition = CurvedAnimation(
    parent: animation,
    curve: Curves.easeInOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  return FadeTransition(
    opacity: transition,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, .035),
        end: Offset.zero,
      ).animate(transition),
      child: RepaintBoundary(child: child),
    ),
  );
}

class PocketRApp extends StatelessWidget {
  const PocketRApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: appLanguageCode,
    builder: (context, languageCode, _) => MaterialApp(
      title: 'PocketR',
      locale: Locale(languageCode),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('id'), Locale('en')],
      debugShowCheckedModeBanner: false,
      builder: (context, child) => TooltipVisibility(
        visible: false,
        child: _AppNotificationLayer(child: child ?? const SizedBox.shrink()),
      ),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _blue,
          brightness: Brightness.light,
          surface: const Color(0xffeef6fb),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: _popupTintColor.withValues(alpha: _popupTintOpacity),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        scaffoldBackgroundColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        fontFamily: 'Inter',
        iconTheme: const IconThemeData(color: _ink),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: _ink,
            backgroundColor: Colors.white.withValues(alpha: .32),
            shape: const StadiumBorder(),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            iconColor: WidgetStatePropertyAll(_ink),
            backgroundColor: WidgetStatePropertyAll(
              Colors.white.withValues(alpha: .42),
            ),
            shape: WidgetStatePropertyAll(StadiumBorder()),
            side: WidgetStatePropertyAll(
              BorderSide(color: Colors.white.withValues(alpha: .58)),
            ),
            overlayColor: _pillFocusOverlay,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(
            iconColor: WidgetStatePropertyAll(_ink),
            backgroundColor: WidgetStatePropertyAll(
              Colors.white.withValues(alpha: .3),
            ),
            shape: WidgetStatePropertyAll(StadiumBorder()),
            side: WidgetStatePropertyAll(
              BorderSide(color: Colors.white.withValues(alpha: .58)),
            ),
            overlayColor: _pillFocusOverlay,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
            foregroundColor: WidgetStatePropertyAll(Colors.white),
            backgroundColor: WidgetStatePropertyAll(
              _blue.withValues(alpha: .88),
            ),
            shape: WidgetStatePropertyAll(StadiumBorder()),
            side: const WidgetStatePropertyAll(BorderSide.none),
            shadowColor: WidgetStatePropertyAll(_blue.withValues(alpha: .24)),
            overlayColor: _pillFocusOverlay,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(StadiumBorder()),
            side: _pillFocusSide,
            overlayColor: _pillFocusOverlay,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          constraints: const BoxConstraints(minHeight: 40),
          filled: true,
          fillColor: Colors.white.withValues(alpha: .55),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(99),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: .48)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(99),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: .48)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(99),
            borderSide: const BorderSide(color: _blue, width: 1.5),
          ),
          contentPadding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        ),
      ),
      home: const FinanceHome(),
    ),
  );
}

class _AppNotificationLayer extends StatelessWidget {
  const _AppNotificationLayer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      ValueListenableBuilder<_AppNotification?>(
        valueListenable: _appNotification,
        builder: (context, notification, _) {
          if (notification == null) return const SizedBox.shrink();
          final mediaQuery = MediaQuery.of(context);
          final messageSurface = _FrostedSurface(
            borderRadius: BorderRadius.circular(
              notification.message.length > 60 ? 22 : 99,
            ),
            tintColor: notification.isError ? _red : Colors.white,
            tintOpacity: notification.isError ? .28 : .52,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shadow: false,
            child: AppText(
              notification.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _ink,
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.35,
                decoration: TextDecoration.none,
              ),
            ),
          );
          return Positioned(
            left: 0,
            right: 0,
            bottom:
                mediaQuery.viewInsets.bottom + mediaQuery.padding.bottom + 16,
            child: IgnorePointer(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: notification.width ?? 560,
                    ),
                    child: notification.width == null
                        ? messageSurface
                        : SizedBox(
                            width: notification.width,
                            child: messageSurface,
                          ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ],
  );
}

class FinanceHome extends StatefulWidget {
  const FinanceHome({super.key});

  @override
  State<FinanceHome> createState() => _FinanceHomeState();
}

class _FinanceHomeState extends State<FinanceHome> with WindowListener {
  static const _storageKey = 'pocketr_v1';
  static const _legacyStorageKey = 'rochinku_v1';
  static const _selectedMonthStorageKey = 'pocketr_selected_month_v1';
  static const _autoSaveEnabledStorageKey = 'pocketr_auto_save_enabled_v1';
  static const _autoSaveIntervalStorageKey = 'pocketr_auto_save_interval_v1';
  static const _autoSaveDirectoryStorageKey = 'pocketr_auto_save_directory_v1';
  static const _autoSaveIntervals = [1, 2, 4, 5, 10, 15, 30, 60];
  final _pageNavigatorKey = GlobalKey<NavigatorState>();
  final _stockTitleKey = GlobalKey();
  final _navigationRefresh = ValueNotifier<int>(0);
  FinanceData _data = FinanceData();
  bool _loading = true;
  String? _loadError;
  String _month = monthKey(DateTime.now());
  String _tab = 'ringkasan';
  String _expenseTab = 'operasional';
  String _productTab = 'produk';
  String _productVariantTab = 'warna';
  String _languageCode = 'id';
  String? _selectedProductId;
  String _marketFilter = 'all';
  String _search = '';
  String _productSalesSortColumn = 'product';
  bool _productSalesSortAscending = true;
  String? _sidebarProfileImageData;
  ImageProvider<Object>? _sidebarProfileImage;
  bool _calculatorOpen = false;
  bool _calculatorMounted = false;
  bool _windowIsMaximized = false;
  bool _windowIsFullScreen = false;
  bool _fullScreenToggleInProgress = false;
  bool _windowWasMaximizedBeforeFullScreen = false;
  bool _autoSaveEnabled = false;
  int _autoSaveIntervalMinutes = 5;
  String? _autoSaveDirectory;
  bool _autoSaveInProgress = false;
  bool _autoSaveErrorNotified = false;
  DateTime? _autoSaveLastSavedAt;
  String? _autoSaveLastError;
  MemoryImage? _defaultBrandImageProvider;
  final _calculatorPosition = ValueNotifier<Offset?>(null);
  Offset? _calculatorGrabOffset;
  Timer? _calculatorCloseTimer;
  Timer? _autoSaveTimer;
  Timer? _notificationTimer;
  final _calculatorLayerKey = GlobalKey();
  final _calculatorButtonKey = GlobalKey();
  final Map<String, String> _productImageSources = {};
  final Map<String, ImageProvider<Object>> _productImageProviders = {};
  final _searchController = TextEditingController();
  final _salesScrollController = ScrollController();
  final _productPickerScrollController = ScrollController();
  final _productSearchController = TextEditingController();
  bool _productSearchOpen = false;
  TapDownDetails? _profileTapDetails;
  Timer? _windowTransitionResetTimer;
  final _slideUpEntranceOrder = _SlideUpEntranceOrder();

  bool get _isDesktop =>
      shouldUseDesktopWindowMaximized() ||
      MediaQuery.sizeOf(context).width >= 850;

  ImageProvider<Object>? _profileImage(String source) {
    if (source.isEmpty) return _defaultBrandImageProvider;
    if (_sidebarProfileImageData != source) {
      _sidebarProfileImageData = source;
      _sidebarProfileImage = _imageFromData(source);
    }
    return _sidebarProfileImage ?? _defaultBrandImageProvider;
  }

  ImageProvider<Object>? _productImage(Product product) {
    final source = product.img;
    if (source.isEmpty) {
      _productImageSources.remove(product.id);
      _productImageProviders.remove(product.id);
      return _defaultBrandImageProvider;
    }
    if (_productImageSources[product.id] != source) {
      _productImageSources[product.id] = source;
      final image = _imageFromData(source);
      if (image == null) {
        _productImageProviders.remove(product.id);
      } else {
        _productImageProviders[product.id] = image;
      }
    }
    return _productImageProviders[product.id] ?? _defaultBrandImageProvider;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_initializeDefaultBrandImage());
    if (shouldUseDesktopWindowMaximized()) {
      HardwareKeyboard.instance.addHandler(_handleGlobalShortcut);
      WindowManager.instance.addListener(this);
      unawaited(_refreshWindowMaximizedState());
    }
    _load();
  }

  Future<void> _initializeDefaultBrandImage() async {
    try {
      final bytes = await _defaultBrandImageBytes;
      if (!mounted) return;
      setState(() => _defaultBrandImageProvider = MemoryImage(bytes));
    } catch (error) {
      if (mounted) {
        _message('Logo PocketR gagal dimuat: $error', isError: true);
      }
    }
  }

  Future<void> _refreshWindowMaximizedState() async {
    final isMaximized = await WindowManager.instance.isMaximized();
    if (mounted && _windowIsMaximized != isMaximized) {
      setState(() => _windowIsMaximized = isMaximized);
    }
  }

  @override
  void onWindowRestore() {
    _beginWindowTransition();
    _finishWindowTransition();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _windowIsMaximized = true);
    _finishWindowTransition();
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _windowIsMaximized = false);
    _finishWindowTransition();
  }

  void _beginWindowTransition() {
    _windowTransitionResetTimer?.cancel();
    _windowTransitionInProgress.value = true;
    _windowTransitionResetTimer = Timer(
      const Duration(seconds: 1),
      _endWindowTransition,
    );
  }

  void _finishWindowTransition() {
    _windowTransitionResetTimer?.cancel();
    _windowTransitionResetTimer = Timer(
      const Duration(milliseconds: 400),
      _endWindowTransition,
    );
  }

  void _endWindowTransition() {
    _windowTransitionInProgress.value = false;
    _windowTransitionResetTimer = null;
  }

  bool _handleGlobalShortcut(KeyEvent event) {
    if (!shouldUseDesktopWindowMaximized() ||
        event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.f12) {
      return false;
    }
    unawaited(_toggleFullScreenWindow());
    return true;
  }

  Future<void> _toggleMaximizeWindow() async {
    if (_fullScreenToggleInProgress) return;
    if (_windowIsFullScreen) {
      _fullScreenToggleInProgress = true;
      _beginWindowTransition();
      try {
        if (Platform.isWindows) {
          await _windowStateChannel.invokeMethod<void>('setFullScreen', {
            'isFullScreen': false,
            'maximize': true,
          });
        } else {
          await WindowManager.instance.setFullScreen(false);
        }
        _windowIsFullScreen = false;
        _windowWasMaximizedBeforeFullScreen = false;
        if (mounted) setState(() => _windowIsMaximized = true);
      } on PlatformException catch (error) {
        debugPrint('Could not leave full screen for maximize: $error');
        _message('Gagal mengubah mode layar penuh', isError: true);
      } finally {
        _fullScreenToggleInProgress = false;
        _finishWindowTransition();
      }
      return;
    }
    _beginWindowTransition();
    try {
      if (await WindowManager.instance.isMaximized()) {
        await WindowManager.instance.unmaximize();
      } else {
        await WindowManager.instance.maximize();
      }
    } catch (_) {
      _windowTransitionResetTimer?.cancel();
      _endWindowTransition();
      rethrow;
    }
  }

  Future<void> _toggleFullScreenWindow() async {
    if (_fullScreenToggleInProgress) return;
    _fullScreenToggleInProgress = true;
    _beginWindowTransition();
    try {
      if (!Platform.isWindows) {
        final isFullScreen = !_windowIsFullScreen;
        await WindowManager.instance.setFullScreen(isFullScreen);
        _windowIsFullScreen = isFullScreen;
      } else {
        final isFullScreen = !_windowIsFullScreen;
        if (isFullScreen) {
          _windowWasMaximizedBeforeFullScreen = await WindowManager.instance
              .isMaximized();
        }
        await _windowStateChannel.invokeMethod<void>('setFullScreen', {
          'isFullScreen': isFullScreen,
          'maximize': !isFullScreen && _windowWasMaximizedBeforeFullScreen,
        });
        _windowIsFullScreen = isFullScreen;
        final maximizedAfterExit =
            !isFullScreen && _windowWasMaximizedBeforeFullScreen;
        if (!isFullScreen) _windowWasMaximizedBeforeFullScreen = false;
        if (mounted) {
          setState(() => _windowIsMaximized = maximizedAfterExit);
        }
      }
    } on PlatformException catch (error) {
      debugPrint('Could not toggle full screen: $error');
      _message('Gagal mengubah mode layar penuh', isError: true);
    } finally {
      _fullScreenToggleInProgress = false;
      _finishWindowTransition();
    }
  }

  Future<void> _minimizeWindow() async {
    await WindowManager.instance.minimize();
  }

  void _openCalculator() {
    _calculatorCloseTimer?.cancel();
    _calculatorCloseTimer = null;
    final layer = _calculatorLayerKey.currentContext?.findRenderObject();
    final button = _calculatorButtonKey.currentContext?.findRenderObject();
    if (layer is RenderBox && button is RenderBox) {
      final buttonPosition = layer.globalToLocal(
        button.localToGlobal(Offset.zero),
      );
      _calculatorPosition.value = Offset(
        buttonPosition.dx + button.size.width + 12,
        buttonPosition.dy + button.size.height / 2 - 220,
      );
    }
    setState(() {
      _calculatorMounted = true;
      _calculatorOpen = true;
    });
  }

  void _closeCalculator() {
    setState(() => _calculatorOpen = false);
    _calculatorCloseTimer?.cancel();
    _calculatorCloseTimer = Timer(const Duration(milliseconds: 220), () {
      if (mounted && !_calculatorOpen) {
        setState(() => _calculatorMounted = false);
      }
      _calculatorCloseTimer = null;
    });
  }

  @override
  void dispose() {
    if (shouldUseDesktopWindowMaximized()) {
      HardwareKeyboard.instance.removeHandler(_handleGlobalShortcut);
      WindowManager.instance.removeListener(this);
    }
    _windowTransitionResetTimer?.cancel();
    _calculatorCloseTimer?.cancel();
    _autoSaveTimer?.cancel();
    _dismissNotification();
    _windowTransitionInProgress.value = false;
    _navigationRefresh.dispose();
    _calculatorPosition.dispose();
    _searchController.dispose();
    _salesScrollController.dispose();
    _productPickerScrollController.dispose();
    _productSearchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedData = await FinanceSqliteStore.instance.load();
      if (savedData != null) {
        _data = savedData;
        await _hydrateApplicationImages(_data);
        await _archiveLegacyJsonStorage(prefs);
      } else {
        final stored =
            prefs.getString(_storageKey) ?? prefs.getString(_legacyStorageKey);
        if (stored != null) {
          _data = FinanceData.fromBackup(stored);
          await _hydrateApplicationImages(_data);
          await FinanceSqliteStore.instance.save(_data);
          final migratedData = await FinanceSqliteStore.instance.load();
          if (migratedData == null) {
            throw StateError('Migrasi penyimpanan lokal gagal diverifikasi.');
          }
          await _archiveLegacyJsonStorage(prefs);
        }
      }
      _languageCode = prefs.getString(appLanguagePreferenceKey) == 'en'
          ? 'en'
          : 'id';
      appLanguageCode.value = _languageCode;
      _autoSaveEnabled = prefs.getBool(_autoSaveEnabledStorageKey) ?? false;
      final savedAutoSaveInterval = prefs.getInt(_autoSaveIntervalStorageKey);
      if (_autoSaveIntervals.contains(savedAutoSaveInterval)) {
        _autoSaveIntervalMinutes = savedAutoSaveInterval!;
      }
      _autoSaveDirectory = prefs.getString(_autoSaveDirectoryStorageKey);
      final savedMonth = prefs.getString(_selectedMonthStorageKey);
      if (_isValidMonthKey(savedMonth)) {
        _month = savedMonth!;
      } else {
        String? latestSaleMonth;
        for (final sale in _data.sales) {
          if (sale.date.length < 7) continue;
          final saleMonth = sale.date.substring(0, 7);
          if (_isValidMonthKey(saleMonth) &&
              (latestSaleMonth == null ||
                  saleMonth.compareTo(latestSaleMonth) > 0)) {
            latestSaleMonth = saleMonth;
          }
        }
        if (latestSaleMonth != null) _month = latestSaleMonth;
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = null;
        });
        if (_autoSaveEnabled && (_autoSaveDirectory?.isNotEmpty ?? false)) {
          _configureAutoSaveTimer(saveImmediately: true);
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Data tidak bisa dibuka: $error';
        });
      }
    }
  }

  Future<void> _archiveLegacyJsonStorage(SharedPreferences prefs) async {
    final directory = Directory(
      p.join(
        (await FinanceSqliteStore.instance.supportDirectory()).path,
        'legacy_backup',
      ),
    );
    await directory.create(recursive: true);
    for (final key in [_storageKey, _legacyStorageKey]) {
      final source = prefs.getString(key);
      if (source == null) continue;
      final file = File(p.join(directory.path, '$key.json'));
      if (await file.exists() && await file.readAsString() != source) {
        throw FileSystemException(
          'Arsip JSON lama sudah ada dengan isi berbeda.',
          file.path,
        );
      }
      if (!await file.exists()) {
        await file.writeAsString(source, flush: true);
      }
      if (file.readAsStringSync() != source) {
        throw FileSystemException(
          'Verifikasi arsip JSON lama gagal.',
          file.path,
        );
      }
      final removed = await prefs.remove(key);
      if (!removed) {
        throw StateError('Penyimpanan JSON lama gagal dipindahkan ke arsip.');
      }
    }
  }

  bool _isValidMonthKey(String? value) {
    final match = value == null
        ? null
        : RegExp(r'^(\d{4})-(\d{2})$').firstMatch(value);
    if (match == null) return false;
    final year = int.tryParse(match[1]!);
    final month = int.tryParse(match[2]!);
    return year != null &&
        month != null &&
        month >= 1 &&
        month <= 12 &&
        monthKey(DateTime(year, month)) == value;
  }

  Future<void> _persistSelectedMonth(String month) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(_selectedMonthStorageKey, month);
      if (!saved) throw StateError('Bulan yang dipilih gagal disimpan.');
    } catch (error) {
      if (mounted) {
        _message('Bulan yang dipilih gagal disimpan: $error', isError: true);
      }
    }
  }

  void _setMonth(String month) {
    setState(() => _month = month);
    unawaited(_persistSelectedMonth(month));
  }

  Future<void> _downloadHppTemplate() async {
    try {
      final path = await _withOutsideDismissedPicker(
        () => FilePicker.platform.saveFile(
          dialogTitle: 'Simpan template impor HPP',
          fileName: 'pocketr-template-hpp.xlsx',
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
          bytes: Uint8List.fromList(createHppTemplateBytes()),
          lockParentWindow: true,
        ),
      );
      if (path != null) _message('Template HPP berhasil disimpan.');
    } catch (error) {
      _message('Template HPP gagal dibuat: $error', isError: true);
    }
  }

  Future<void> _showHppImportMenu() async {
    final action = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0x180f202c),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (dialogContext, animation, secondaryAnimation) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _FrostedSurface(
              borderRadius: BorderRadius.circular(26),
              tintColor: _popupTintColor,
              tintOpacity: _popupTintOpacity,
              padding: const EdgeInsets.all(22),
              blurSigma: 18,
              prominentShadow: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _blue.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(
                          Icons.inventory_2_outlined,
                          color: _blue,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppText(
                              'Impor HPP',
                              style: TextStyle(
                                color: _ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            SizedBox(height: 2),
                            AppText(
                              'Bahan baku dan ongkos per produk',
                              style: TextStyle(
                                color: _muted,
                                fontSize: 12,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _PopIconButton(
                        tooltip: localizeAppText('Tutup'),
                        onPressed: () => Navigator.pop(dialogContext),
                        style: IconButton.styleFrom(
                          foregroundColor: _muted,
                          backgroundColor: Colors.white.withValues(alpha: .5),
                          minimumSize: const Size(34, 34),
                          padding: EdgeInsets.zero,
                        ),
                        icon: const Icon(Icons.close, size: 17),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _HppImportAction(
                    icon: Icons.upload_file_outlined,
                    title: 'Impor dari Excel',
                    detail: 'Pilih file template yang sudah diisi',
                    primary: true,
                    onTap: () => Navigator.pop(dialogContext, 'import'),
                  ),
                  const SizedBox(height: 10),
                  _HppImportAction(
                    icon: Icons.download_outlined,
                    title: 'Unduh template Excel',
                    detail: 'Lihat format dan contoh pengisian HPP',
                    onTap: () => Navigator.pop(dialogContext, 'template'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          _normalDialogTransition(animation, child),
    );
    if (!mounted) return;
    if (action == 'import') {
      await _importHppExcel();
    } else if (action == 'template') {
      await _downloadHppTemplate();
    }
  }

  Future<void> _importHppExcel() async {
    try {
      final result = await _withOutsideDismissedPicker(
        () => FilePicker.platform.pickFiles(
          dialogTitle: 'Pilih file impor HPP',
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
          withData: true,
          lockParentWindow: true,
        ),
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes =
          file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null || bytes.isEmpty) {
        throw FormatException('Isi berkas "${file.name}" tidak terbaca.');
      }
      final rows = await compute(parseHppWorkbook, bytes);
      final rowsByProduct = <String, List<HppImportRow>>{};
      final productNames = <String, String>{};
      String normalize(String value) =>
          value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      for (final row in rows) {
        final key = normalize(row.productName);
        rowsByProduct.putIfAbsent(key, () => []).add(row);
        productNames.putIfAbsent(key, () => row.productName.trim());
      }

      final existingByName = <String, List<Product>>{};
      for (final product in _data.products) {
        existingByName
            .putIfAbsent(normalize(product.name), () => [])
            .add(product);
      }
      for (final key in rowsByProduct.keys) {
        if ((existingByName[key]?.length ?? 0) > 1) {
          throw FormatException(
            'Ada lebih dari satu produk bernama "${productNames[key]}". '
            'Ubah nama produk agar impor tidak salah sasaran.',
          );
        }
      }

      final newProducts = rowsByProduct.keys
          .where((key) => existingByName[key] == null)
          .length;
      final replaceProducts = rowsByProduct.length - newProducts;
      final newProductDetails = rowsByProduct.keys
          .where((key) => existingByName[key] == null)
          .map((key) => productNames[key]!)
          .toList();
      final replacedProductDetails = rowsByProduct.keys
          .where((key) => existingByName[key] != null)
          .map((key) {
            final itemCount = rowsByProduct[key]!.length;
            return '${productNames[key]} · $itemCount rincian HPP baru';
          })
          .toList();
      final confirmed = await _confirmHppImport(
        productCount: rowsByProduct.length,
        detailCount: rows.length,
        newProducts: newProducts,
        replaceProducts: replaceProducts,
        newProductDetails: newProductDetails,
        replacedProductDetails: replacedProductDetails,
      );
      if (!confirmed || !mounted) return;

      setState(() {
        for (final entry in rowsByProduct.entries) {
          final materials = entry.value
              .map(
                (row) => MaterialCost(
                  name: row.itemName,
                  qty: row.qty,
                  unit: row.unit,
                  price: row.price,
                  category: row.category,
                ),
              )
              .toList();
          final existing = existingByName[entry.key]?.singleOrNull;
          if (existing == null) {
            _data.products.add(
              Product(name: productNames[entry.key]!, materials: materials),
            );
          } else {
            existing.materials = materials;
          }
        }
      });
      if (!await _save()) return;
      _message(
        'Impor HPP berhasil: ${rowsByProduct.length} produk, ${rows.length} rincian.',
      );
    } catch (error) {
      _message('Impor HPP gagal: $error', isError: true);
    }
  }

  Future<bool> _confirmHppImport({
    required int productCount,
    required int detailCount,
    required int newProducts,
    required int replaceProducts,
    required List<String> newProductDetails,
    required List<String> replacedProductDetails,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        Future<void> showProductDetails(
          String title,
          List<String> details,
        ) async {
          await showDialog<void>(
            context: dialogContext,
            builder: (detailsContext) => AlertDialog(
              title: AppText(
                title,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  color: _ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              content: SizedBox(
                width: 360,
                child: details.isEmpty
                    ? const SizedBox(
                        height: 42,
                        child: Center(
                          child: AppText(
                            'Tidak ada produk pada bagian ini.',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: _muted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                    : ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight:
                              (MediaQuery.sizeOf(detailsContext).height * .48)
                                  .clamp(100.0, 420.0)
                                  .toDouble(),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: details.length,
                          physics: const ClampingScrollPhysics(),
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, index) => Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _blue.withValues(alpha: .07),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: SelectableText(
                              details[index],
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                color: _ink,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
              actions: [
                _PopTextButton(
                  onPressed: () => Navigator.pop(detailsContext),
                  child: const AppText(
                    'Tutup',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: _ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        Widget metricCard({
          required String label,
          required int value,
          required IconData icon,
          required List<String> details,
        }) => Expanded(
          child: SizedBox(
            height: 72,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(15),
              child: InkWell(
                onTap: () => showProductDetails(label, details),
                borderRadius: BorderRadius.circular(15),
                splashFactory: NoSplash.splashFactory,
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .42),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .6),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, color: _blue, size: 18),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppText(
                              '$value',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                color: _ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            AppText(
                              label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                color: _muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: _muted.withValues(alpha: .8),
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        return AlertDialog(
          title: const AppText('Konfirmasi impor HPP'),
          content: SizedBox(
            width: 420,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(dialogContext).height * .68,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: _blue.withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: _blue.withValues(alpha: .14)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _blue.withValues(alpha: .13),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.inventory_2_outlined,
                              color: _blue,
                              size: 21,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AppText(
                                  '$productCount produk · $detailCount rincian',
                                  style: const TextStyle(
                                    color: _ink,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                const AppText(
                                  'Siap ditambahkan dari file Excel.',
                                  style: TextStyle(color: _muted, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        metricCard(
                          label: 'Produk baru',
                          value: newProducts,
                          icon: Icons.add_box_outlined,
                          details: newProductDetails,
                        ),
                        const SizedBox(width: 8),
                        metricCard(
                          label: 'HPP diganti',
                          value: replaceProducts,
                          icon: Icons.edit_note_outlined,
                          details: replacedProductDetails,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _orange.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, color: _orange, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: AppText(
                              'Foto, varian, dan stok tetap. Rincian HPP produk yang sudah ada akan diganti; katalog bahan baku tidak berubah.',
                              style: TextStyle(
                                color: _ink,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            _PopTextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const AppText('Batal'),
            ),
            _PopFilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const AppText('Impor'),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  Future<bool> _save({bool rebuild = true}) async {
    try {
      await FinanceSqliteStore.instance.save(_data);
      await _persistSelectedMonth(_month);
      if (mounted && rebuild) setState(() {});
      return true;
    } catch (error) {
      _message('Gagal menyimpan data: $error', isError: true);
      return false;
    }
  }

  void _message(String message, {bool isError = false}) {
    if (!mounted) return;
    _dismissNotification();
    final isLongMessage = message.length > 60;
    final snackWidth = _isDesktop
        ? (isLongMessage
              ? (MediaQuery.sizeOf(context).width - 32)
                    .clamp(300.0, 560.0)
                    .toDouble()
              : 300.0)
        : null;
    _appNotification.value = _AppNotification(
      message: message,
      isError: isError,
      width: snackWidth,
    );
    _notificationTimer = Timer(
      const Duration(seconds: 4),
      _dismissNotification,
    );
  }

  void _dismissNotification() {
    _notificationTimer?.cancel();
    _notificationTimer = null;
    _appNotification.value = null;
  }

  Future<void> _copyOrderNumber(String orderNo) async {
    try {
      await Clipboard.setData(ClipboardData(text: orderNo));
      if (mounted) _message('Nomor pesanan disalin.');
    } catch (error) {
      if (mounted) {
        _message('Nomor pesanan gagal disalin: $error', isError: true);
      }
    }
  }

  Future<bool> _confirm(
    String title,
    String body, {
    bool translateBody = true,
    String confirmLabel = 'Hapus',
    bool confirmBlue = false,
  }) async =>
      await showGeneralDialog<bool>(
        context: context,
        barrierDismissible: true,
        barrierLabel: MaterialLocalizations.of(context)
            .modalBarrierDismissLabel,
        barrierColor: const Color(0x180f202c),
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (context, animation, secondaryAnimation) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _FrostedSurface(
              borderRadius: BorderRadius.circular(26),
              tintColor: _popupTintColor,
              tintOpacity: _popupTintOpacity,
              padding: const EdgeInsets.all(24),
              blurSigma: 18,
              prominentShadow: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    title,
                    style: TextStyle(
                      color: _ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  translateBody
                      ? AppText(
                          body,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 14,
                            height: 1.45,
                          ),
                        )
                      : AppText.raw(
                          body,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _ImportDialogPill(
                        label: 'Batal',
                        labelOffset: -1,
                        onPressed: () => Navigator.pop(context, false),
                      ),
                      const SizedBox(width: 4),
                      _ImportDialogPill(
                        label: confirmLabel,
                        blue: confirmBlue,
                        danger: !confirmBlue,
                        labelOffset: -1,
                        onPressed: () => Navigator.pop(context, true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        transitionBuilder: (context, animation, secondaryAnimation, child) =>
            _normalDialogTransition(animation, child),
      ) ??
      false;

  String _backupDateStamp(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}-'
      '${date.hour.toString().padLeft(2, '0')}'
      '${date.minute.toString().padLeft(2, '0')}'
      '${date.second.toString().padLeft(2, '0')}-'
      '${date.millisecond.toString().padLeft(3, '0')}';

  Future<void> _backup() async {
    try {
      final path = await _withOutsideDismissedPicker(
        () => FilePicker.platform.saveFile(
          dialogTitle: localizeAppText('Simpan cadangan PocketR'),
          fileName: 'pocketr-${_backupDateStamp(DateTime.now())}.pcktr',
          type: FileType.custom,
          allowedExtensions: ['pcktr', 'db'],
          lockParentWindow: true,
        ),
      );
      if (path == null) return;
      final bytes = await _createBackupBytes();
      await writeTimestampedBackup(path, bytes, prefix: 'pocketr-');
      _message('Cadangan berhasil disimpan.');
    } catch (error) {
      _message('Cadangan gagal dibuat: $error', isError: true);
    }
  }

  Future<void> _backupAllData({
    void Function(String message, {bool isError, bool isLoading})? onStatus,
  }) async {
    try {
      final path = await _withOutsideDismissedPicker(
        () => FilePicker.platform.saveFile(
          dialogTitle: localizeAppText('Simpan cadangan lengkap PocketR'),
          fileName: 'pocketr-lengkap-${_backupDateStamp(DateTime.now())}.pcktr',
          type: FileType.custom,
          allowedExtensions: ['pcktr', 'db'],
          lockParentWindow: true,
        ),
      );
      if (path == null) return;
      onStatus?.call('Membuat cadangan lengkap PocketR...', isLoading: true);
      _message('Membuat cadangan lengkap PocketR...');
      final files = await LocalFileArchive.instance.listFiles(
        includeRestoredBackups: false,
      );
      final bytes = createFullBackupBytes(_data, files);
      await writeTimestampedBackup(path, bytes, prefix: 'pocketr-lengkap-');
      onStatus?.call(
        'Cadangan lengkap beserta foto berhasil disimpan.',
        isLoading: false,
      );
      _message('Cadangan lengkap beserta foto berhasil disimpan.');
    } catch (error) {
      onStatus?.call(
        'Cadangan lengkap gagal dibuat: $error',
        isError: true,
        isLoading: false,
      );
      _message('Cadangan lengkap gagal dibuat: $error', isError: true);
    }
  }

  Future<Uint8List> _createBackupBytes() async {
    return createBackupBytes(_data);
  }

  void _configureAutoSaveTimer({bool saveImmediately = false}) {
    _autoSaveTimer?.cancel();
    final directory = _autoSaveDirectory;
    if (!mounted ||
        !_autoSaveEnabled ||
        directory == null ||
        directory.isEmpty) {
      return;
    }
    if (saveImmediately) unawaited(_runAutoSave());
    _autoSaveTimer = Timer.periodic(
      Duration(minutes: _autoSaveIntervalMinutes),
      (_) => unawaited(_runAutoSave()),
    );
  }

  Future<void> _runAutoSave() async {
    final directoryPath = _autoSaveDirectory;
    if (!mounted ||
        !_autoSaveEnabled ||
        _autoSaveInProgress ||
        directoryPath == null ||
        directoryPath.isEmpty) {
      return;
    }
    _autoSaveInProgress = true;
    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        throw FileSystemException(
          'Direktori auto-save tidak ditemukan.',
          directoryPath,
        );
      }
      final bytes = await _createBackupBytes();
      if (!mounted ||
          !_autoSaveEnabled ||
          _autoSaveDirectory != directoryPath) {
        return;
      }
      await writeOverwriteBackup(
        p.join(directoryPath, 'pocketr-autosave.pcktr'),
        bytes,
      );
      _autoSaveErrorNotified = false;
      if (mounted) {
        setState(() {
          _autoSaveLastSavedAt = DateTime.now();
          _autoSaveLastError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _autoSaveLastError = error.toString());
        if (!_autoSaveErrorNotified) {
          _message('Auto-save gagal: $error', isError: true);
        }
      }
      _autoSaveErrorNotified = true;
    } finally {
      _autoSaveInProgress = false;
    }
  }

  Future<void> _selectAutoSaveDirectory() async {
    try {
      // A missing folder makes the native picker fail, so start from the
      // nearest existing ancestor instead.
      String? initialDirectory = _autoSaveDirectory;
      if (initialDirectory != null && initialDirectory.isNotEmpty) {
        var current = Directory(initialDirectory);
        while (!current.existsSync() && current.parent.path != current.path) {
          current = current.parent;
        }
        initialDirectory = current.existsSync() ? current.path : null;
      } else {
        initialDirectory = null;
      }
      final directory = await _withOutsideDismissedPicker(
        () => FilePicker.platform.getDirectoryPath(
          dialogTitle: localizeAppText('Pilih direktori auto-save PocketR'),
          initialDirectory: initialDirectory,
          lockParentWindow: true,
        ),
      );
      if (directory == null) return;
      if (directory.isEmpty || !await Directory(directory).exists()) {
        throw FileSystemException(
          'Direktori yang dipilih tidak dapat diakses.',
          directory,
        );
      }
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(_autoSaveDirectoryStorageKey, directory)) {
        throw StateError('Direktori auto-save gagal disimpan.');
      }
      if (!mounted) return;
      setState(() {
        _autoSaveDirectory = directory;
        _autoSaveLastError = null;
      });
      _autoSaveErrorNotified = false;
      if (_autoSaveEnabled) {
        _configureAutoSaveTimer();
        await _runAutoSave();
      }
    } catch (error) {
      _message('Direktori auto-save gagal dipilih: $error', isError: true);
    }
  }

  Future<void> _setAutoSaveEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setBool(_autoSaveEnabledStorageKey, enabled)) {
        throw StateError('Pengaturan auto-save gagal disimpan.');
      }
      if (!mounted) return;
      setState(() {
        _autoSaveEnabled = enabled;
        if (!enabled) _autoSaveLastError = null;
      });
      if (enabled) {
        _autoSaveErrorNotified = false;
        _configureAutoSaveTimer();
        await _runAutoSave();
      } else {
        _autoSaveTimer?.cancel();
        _autoSaveTimer = null;
      }
    } catch (error) {
      _message('Pengaturan auto-save gagal diubah: $error', isError: true);
    }
  }

  Future<void> _setAutoSaveInterval(int minutes) async {
    if (!_autoSaveIntervals.contains(minutes)) {
      throw ArgumentError.value(minutes, 'minutes', 'Interval tidak tersedia.');
    }
    final previousInterval = _autoSaveIntervalMinutes;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setInt(_autoSaveIntervalStorageKey, minutes)) {
        throw StateError('Interval auto-save gagal disimpan.');
      }
      if (!mounted) return;
      setState(() => _autoSaveIntervalMinutes = minutes);
      if (_autoSaveEnabled) _configureAutoSaveTimer();
    } catch (error) {
      if (mounted) setState(() => _autoSaveIntervalMinutes = previousInterval);
      _message('Interval auto-save gagal diubah: $error', isError: true);
    }
  }

  Future<void> _setLanguageCode(String languageCode) async {
    if (languageCode != 'id' && languageCode != 'en') {
      throw ArgumentError.value(languageCode, 'languageCode');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(appLanguagePreferenceKey, languageCode)) {
        throw StateError('Bahasa aplikasi gagal disimpan.');
      }
      if (!mounted) return;
      setState(() => _languageCode = languageCode);
      appLanguageCode.value = languageCode;
    } catch (error) {
      _message('Bahasa aplikasi gagal disimpan: $error', isError: true);
    }
  }

  Future<void> _archiveLegacyJsonBackup(String name, Uint8List bytes) async {
    final directory = Directory(
      p.join(
        (await FinanceSqliteStore.instance.supportDirectory()).path,
        'legacy_backup',
      ),
    );
    await directory.create(recursive: true);
    final basename = p.basenameWithoutExtension(name);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final archivedFile = File(p.join(directory.path, '$basename-$stamp.json'));
    await archivedFile.writeAsBytes(bytes, flush: true);
    final archivedBytes = archivedFile.readAsBytesSync();
    if (!_bytesEqual(archivedBytes, bytes)) {
      throw FileSystemException(
        'Verifikasi arsip JSON lama gagal.',
        archivedFile.path,
      );
    }
  }

  Future<void> _saveApplicationImage(
    String key,
    String source,
    Uint8List? bytes,
  ) async {
    if (bytes == null) {
      await LocalFileArchive.instance.deleteApplicationImage(key);
      return;
    }
    final separator = source.indexOf(',');
    final mimeEnd = source.indexOf(';');
    if (!source.startsWith('data:') ||
        separator < 0 ||
        mimeEnd < 5 ||
        mimeEnd > separator) {
      throw const FormatException('Format foto internal tidak valid.');
    }
    final mime = source.substring(5, mimeEnd);
    await LocalFileArchive.instance.saveApplicationImage(
      key: key,
      mime: mime,
      bytes: bytes,
    );
  }

  Future<void> _hydrateApplicationImages(FinanceData data) async {
    Future<String> restoreImage(String key, String source) async {
      if (source.startsWith('data:')) {
        final separator = source.indexOf(',');
        final mimeEnd = source.indexOf(';');
        if (separator < 0 || mimeEnd < 5 || mimeEnd > separator) {
          throw const FormatException('Format foto tersimpan tidak valid.');
        }
        final bytes = base64Decode(source.substring(separator + 1));
        await LocalFileArchive.instance.saveApplicationImage(
          key: key,
          mime: source.substring(5, mimeEnd),
          bytes: bytes,
        );
        return source;
      }
      final image = await LocalFileArchive.instance.applicationImage(key);
      return image == null
          ? ''
          : 'data:${image.mime};base64,${base64Encode(image.bytes)}';
    }

    data.logo = await restoreImage('profile_logo', data.logo);
    for (final product in data.products) {
      product.img = await restoreImage('product:${product.id}', product.img);
    }
  }

  List<ArchivedFile> _archivedFilesFromBackup(Object? decoded) {
    if (decoded is! Map<String, dynamic> || decoded['files'] == null) {
      return [];
    }
    final files = decoded['files'];
    if (files is! List) {
      throw const FormatException('Daftar berkas cadangan tidak valid.');
    }
    return files.map((file) {
      if (file is! Map) {
        throw const FormatException('Metadata berkas cadangan tidak valid.');
      }
      return ArchivedFile.fromJson(Map<String, dynamic>.from(file));
    }).toList();
  }

  Future<void> _restore({bool closeSettingsOnSuccess = false}) async {
    try {
      final result = await _withOutsideDismissedPicker(
        () => FilePicker.platform.pickFiles(
          dialogTitle: localizeAppText('Pilih berkas cadangan PocketR'),
          type: FileType.custom,
          allowedExtensions: ['pcktr', 'db', 'json'],
          withData: true,
          lockParentWindow: true,
        ),
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.single.bytes;
      if (bytes == null) {
        throw const FormatException('Isi berkas tidak terbaca.');
      }
      final SqliteBackupContents? sqliteBackup = _isSqliteDatabase(bytes)
          ? await FinanceSqliteStore.readBackupBytes(bytes)
          : null;
      final FinanceData restored;
      final List<ArchivedFile> restoredFiles;
      if (sqliteBackup != null) {
        restored = sqliteBackup.data;
        restoredFiles = sqliteBackup.files;
      } else {
        final backupSource = utf8.decode(bytes, allowMalformed: false);
        final decodedBackup = jsonDecode(backupSource);
        restored = FinanceData.fromBackup(backupSource);
        restoredFiles = _archivedFilesFromBackup(decodedBackup);
        await _archiveLegacyJsonBackup(result.files.single.name, bytes);
      }
      await _hydrateApplicationImages(restored);
      if (!mounted) return;
      setState(() {
        _data = restored;
        _selectedProductId = null;
      });
      await LocalFileArchive.instance.addRestoredFiles(restoredFiles);
      if (!await _save()) return;
      if (closeSettingsOnSuccess && mounted) Navigator.of(context).pop();
      _message('Berkas berhasil dibuka.');
    } catch (error) {
      _message('Pemulihan cadangan gagal: $error', isError: true);
    }
  }

  Future<void> _showSalesImportDialog() async {
    final selectedShopeeFiles = await showGeneralDialog<List<PlatformFile>>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0x180f202c),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (dialogContext, animation, secondaryAnimation) =>
          StatefulBuilder(
            builder: (context, _) {
              Future<void> pickShopeeFiles() async {
                try {
                  _beginWindowTransition();
                  final FilePickerResult? result;
                  try {
                    result = await _withOutsideDismissedPicker(
                      () => FilePicker.platform.pickFiles(
                        dialogTitle: localizeAppText(
                          'Pilih dua berkas ekspor Shopee',
                        ),
                        type: FileType.custom,
                        allowedExtensions: ['xlsx'],
                        allowMultiple: true,
                        withData: true,
                        withReadStream: true,
                        lockParentWindow: true,
                      ),
                    );
                  } finally {
                    _finishWindowTransition();
                  }
                  if (result == null || result.files.isEmpty) return;
                  final pickedFiles = result.files;
                  if (pickedFiles.length != 2) {
                    _message(
                      'Pilih tepat 2 berkas: rincian pesanan selesai dan laporan saldo Shopee.',
                      isError: true,
                    );
                    return;
                  }
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext, pickedFiles);
                } catch (error) {
                  _message(
                    'Berkas Excel Shopee gagal dipilih: $error',
                    isError: true,
                  );
                }
              }

              return Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 760,
                    maxHeight: (MediaQuery.sizeOf(context).height - 48)
                        .clamp(320.0, 900.0)
                        .toDouble(),
                  ),
                  child: _FrostedSurface(
                    borderRadius: BorderRadius.circular(28),
                    tintColor: _popupTintColor,
                    tintOpacity: _popupTintOpacity,
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
                    blurSigma: 12,
                    prominentShadow: true,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Expanded(
                                child: AppText(
                                  'Impor penjualan dari Excel',
                                  style: TextStyle(
                                    color: _ink,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              _PopIconButton(
                                tooltip: localizeAppText('Tutup'),
                                onPressed: () => Navigator.pop(dialogContext),
                                style: IconButton.styleFrom(
                                  foregroundColor: _muted,
                                  backgroundColor: Colors.white.withValues(
                                    alpha: .5,
                                  ),
                                  minimumSize: const Size(32, 32),
                                  padding: EdgeInsets.zero,
                                ),
                                icon: const Icon(Icons.close, size: 17),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          const AppText(
                            'Pilih platform penjualan untuk impor. Saat ini format Shopee tersedia; '
                            'platform lain akan menyusul karena format Excel berbeda.',
                            style: TextStyle(
                              color: _muted,
                              fontSize: 13,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 15),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final columns = constraints.maxWidth >= 520
                                  ? 2
                                  : 1;
                              final gap = 12.0;
                              final cardWidth =
                                  (constraints.maxWidth - gap * (columns - 1)) /
                                  columns;
                              return Wrap(
                                spacing: gap,
                                runSpacing: gap,
                                children: [
                                  SizedBox(
                                    width: cardWidth,
                                    height: 210,
                                    child: _SalesPlatformCard(
                                      title: 'Shopee',
                                      description: 'Pilih dua berkas ekspor: rincian pesanan selesai dan laporan saldo.',
                                      icon: Icons.shopping_bag_outlined,
                                      available: true,
                                      accent: const Color(0xffee6f35),
                                      action: _ImportDialogPill(
                                        icon: Icons.folder_open_outlined,
                                        label: 'Pilih 2 berkas',
                                        labelOffset: 0,
                                        onPressed: pickShopeeFiles,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: cardWidth,
                                    height: 210,
                                    child: _SalesPlatformCard(
                                      title: 'TikTok Shop',
                                      description: 'Format ekspor TikTok berbeda dan dukungan impor sedang disiapkan.',
                                      icon: Icons.music_note_rounded,
                                      available: false,
                                      accent: _ink,
                                      action: const _ImportDialogPill(
                                        icon: Icons.schedule_outlined,
                                        label: 'Segera hadir',
                                        labelOffset: 0,
                                        onPressed: null,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: cardWidth,
                                    height: 210,
                                    child: _SalesPlatformCard(
                                      title: 'Tokopedia',
                                      description: 'Format berkas Tokopedia berbeda dan dukungan impor sedang disiapkan.',
                                      icon: Icons.storefront_outlined,
                                      available: false,
                                      accent: _green,
                                      action: const _ImportDialogPill(
                                        icon: Icons.schedule_outlined,
                                        label: 'Segera hadir',
                                        labelOffset: 0,
                                        onPressed: null,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: cardWidth,
                                    height: 210,
                                    child: _SalesPlatformCard(
                                      title: 'Lazada',
                                      description: 'Format berkas Lazada berbeda dan dukungan impor sedang disiapkan.',
                                      icon: Icons.local_mall_outlined,
                                      available: false,
                                      accent: _orange,
                                      action: const _ImportDialogPill(
                                        icon: Icons.schedule_outlined,
                                        label: 'Segera hadir',
                                        labelOffset: 0,
                                        onPressed: null,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .34),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .58),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.table_view_outlined,
                                  color: _blue,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      AppText(
                                        'Template input manual',
                                        style: TextStyle(
                                          color: _ink,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      AppText(
                                        'Lembar pencatatan umum, bukan format ekspor platform.',
                                        style: TextStyle(
                                          color: _muted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.end,
                                  children: [
                                    _ImportDialogPill(
                                      icon: Icons.download_outlined,
                                      label: 'Unduh template',
                                      labelOffset: 0,
                                      onPressed: _downloadSalesTemplate,
                                    ),
                                    _ImportDialogPill(
                                      icon: Icons.upload_file_outlined,
                                      label: 'Impor Excel',
                                      labelOffset: 0,
                                      blue: true,
                                      onPressed: () =>
                                          _importManualSalesExcel(context),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          _normalDialogTransition(animation, child),
    );
    if (!mounted || selectedShopeeFiles == null) return;
    await _importShopeeSalesExcel(selectedShopeeFiles);
  }

  Future<void> _downloadSalesTemplate() async {
    try {
      final path = await _withOutsideDismissedPicker(
        () => FilePicker.platform.saveFile(
          dialogTitle: localizeAppText('Simpan templat impor Excel'),
          fileName: 'pocketr-template-penjualan.xlsx',
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
          bytes: Uint8List.fromList(
            createSalesTemplateBytes(languageCode: appLanguageCode.value),
          ),
          lockParentWindow: true,
        ),
      );
      if (path != null) _message('Template Excel berhasil disimpan.');
    } catch (error) {
      _message('Template Excel gagal dibuat: $error', isError: true);
    }
  }

  Future<void> _importManualSalesExcel(
    BuildContext salesImportDialogContext,
  ) async {
    try {
      final result = await _withOutsideDismissedPicker(
        () => FilePicker.platform.pickFiles(
          dialogTitle: localizeAppText('Pilih template penjualan manual'),
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
          withData: true,
          lockParentWindow: true,
        ),
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes =
          file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null || bytes.isEmpty) {
        throw FormatException('Isi berkas "${file.name}" tidak terbaca.');
      }

      final importedRows = await compute(parseManualSalesWorkbook, bytes);
      String normalizeProductName(String value) =>
          value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      final productsByName = <String, Product>{};
      final existingProductIds = <String>{};
      for (final product in _data.products) {
        productsByName.putIfAbsent(
          normalizeProductName(product.name),
          () => Product.fromJson(product.toJson()),
        );
        existingProductIds.add(product.id);
      }
      final newProductIds = <String>{};
      final newProductDetails = <String>[];
      final newVariantDetails = <String>[];
      for (final row in importedRows) {
        final productKey = normalizeProductName(row.productName);
        var product = productsByName[productKey];
        if (product == null) {
          product = Product(name: row.productName);
          productsByName[productKey] = product;
          newProductIds.add(product.id);
          newProductDetails.add(product.name);
        }
        for (final entry
            in row.variant
                .split('/')
                .map((part) => part.trim())
                .where((part) => part.isNotEmpty)
                .indexed) {
          final variant = entry.$2;
          final normalizedVariant = variant.toLowerCase();
          if (product.colors.any(
                (color) => color.toLowerCase() == normalizedVariant,
              ) ||
              product.sizes.any(
                (size) => size.toLowerCase() == normalizedVariant,
              ) ||
              product.variants.any(
                (item) => item.toLowerCase() == normalizedVariant,
              )) {
            continue;
          }
          switch (entry.$1) {
            case 0:
              product.colors.add(variant);
            case 1:
              product.sizes.add(variant);
            default:
              product.variants.add(variant);
          }
          newVariantDetails.add('${product.name} · $variant');
        }
      }

      String saleKey(Sale sale) =>
          '${sale.platform}|${sale.orderNo}|${sale.productId}|'
          '${sale.variant}|${sale.date}';
      final known = <String>{
        for (final sale in _data.sales)
          if (sale.orderNo.trim().isNotEmpty) saleKey(sale),
      };
      final additions = <Sale>[];
      final duplicateDetails = <String>[];
      var duplicates = 0;
      for (final row in importedRows) {
        final product = productsByName[normalizeProductName(row.productName)]!;
        final variantParts = row.variant
            .split('/')
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .toList();
        final sale = Sale(
          date: row.date,
          platform: row.platform,
          productId: product.id,
          productName: product.name,
          qty: row.qty,
          orderNo: row.orderNo,
          received: row.amountReceived,
          hpp: row.hppPerUnit ?? _data.productHpp(product),
          color: variantParts.isEmpty ? '' : variantParts.first,
          size: variantParts.length < 2 ? '' : variantParts[1],
          other: variantParts.length < 3
              ? ''
              : variantParts.skip(2).join(' / '),
        );
        if (sale.orderNo.trim().isNotEmpty && !known.add(saleKey(sale))) {
          duplicates++;
          duplicateDetails.add(
            'Pesanan ${sale.orderNo}\n'
            '${sale.productName}${sale.variant.isEmpty ? '' : ' · ${sale.variant}'}'
            ' · Qty ${formatNumber(sale.qty)}',
          );
          continue;
        }
        additions.add(sale);
      }
      final hasCatalogChanges =
          newProductIds.isNotEmpty || newVariantDetails.isNotEmpty;
      if (additions.isEmpty && !hasCatalogChanges) {
        _message(
          duplicates > 0
              ? 'Semua baris sudah tercatat; $duplicates duplikat dilewati.'
              : 'Tidak ada penjualan baru untuk diimpor.',
        );
        return;
      }

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        barrierColor: const Color(0x180f202c),
        builder: (context) {
          final dialogWidth = (MediaQuery.sizeOf(context).width - 48)
              .clamp(280.0, 620.0)
              .toDouble();
          final metricColumns = dialogWidth >= 520
              ? 3
              : dialogWidth >= 360
              ? 2
              : 1;
          final metricWidth =
              (dialogWidth - 8 * (metricColumns - 1)) / metricColumns;
          final addedSaleDetails = additions.map((sale) {
            final variant = sale.variant.isEmpty ? '' : ' · ${sale.variant}';
            return '${sale.productName}$variant · Qty ${formatNumber(sale.qty)}'
                ' · ${sale.date} · ${formatMoney(sale.received)}';
          }).toList();
          final importNote = newProductDetails.isEmpty
              ? ''
              : 'Produk baru belum memiliki bahan/HPP. HPP penjualan awal Rp0; '
                    'lengkapi HPP di katalog setelah impor.';

          Future<void> showImportDetails(
            String title,
            String description,
            List<String> entries,
          ) async {
            final detailsWidth = (dialogWidth - 40)
                .clamp(220.0, 520.0)
                .toDouble();
            final detailsHeight = (MediaQuery.sizeOf(context).height * .48)
                .clamp(140.0, 420.0)
                .toDouble();
            await showDialog<void>(
              context: context,
              barrierColor: const Color(0x180f202c),
              builder: (detailsContext) => AlertDialog(
                title: AppText(title),
                content: SizedBox(
                  width: detailsWidth,
                  height: detailsHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        description,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: entries.isEmpty
                            ? const Center(
                                child: AppText(
                                  'Tidak ada data pada bagian ini.',
                                  style: TextStyle(color: _muted),
                                ),
                              )
                            : ListView.separated(
                                itemCount: entries.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 6),
                                itemBuilder: (context, index) => Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: _blue.withValues(alpha: .07),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: SelectableText(
                                    entries[index],
                                    style: const TextStyle(
                                      color: _ink,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  _PopTextButton(
                    onPressed: () => Navigator.pop(detailsContext),
                    child: const AppText('Tutup'),
                  ),
                ],
              ),
            );
          }

          Widget metricCard(
            String label,
            int value,
            IconData icon, {
            Color color = _blue,
            required VoidCallback onTap,
          }) => SizedBox(
            width: metricWidth,
            height: 68,
            child: Tooltip(
              message: localizeAppText('Klik untuk melihat detail: $label'),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .38),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .62),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(icon, color: color, size: 19),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppText(
                                '$value',
                                style: TextStyle(
                                  color: color,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              AppText(
                                label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 11,
                                  height: 1.25,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );

          return AlertDialog(
            title: const AppText('Konfirmasi impor manual'),
            content: SizedBox(
              width: dialogWidth,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .68,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Tooltip(
                        message: localizeAppText(
                          'Klik untuk melihat daftar penjualan',
                        ),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => showImportDetails(
                              'Penjualan siap diimpor',
                              'Rincian setiap baris penjualan yang akan ditambahkan.',
                              addedSaleDetails,
                            ),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(15),
                              decoration: BoxDecoration(
                                color: _blue.withValues(alpha: .09),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: _blue.withValues(alpha: .14),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: _blue.withValues(alpha: .13),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.receipt_long_outlined,
                                      color: _blue,
                                      size: 21,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        AppText(
                                          '${additions.length} baris penjualan',
                                          style: const TextStyle(
                                            color: _ink,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        const AppText(
                                          'Siap ditambahkan dari template manual.',
                                          style: TextStyle(
                                            color: _muted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          metricCard(
                            'Produk baru',
                            newProductDetails.length,
                            Icons.inventory_2_outlined,
                            onTap: () => showImportDetails(
                              'Produk baru',
                              'Produk dari Excel yang belum ada di katalog dan akan ditambahkan.',
                              newProductDetails,
                            ),
                          ),
                          metricCard(
                            'Varian baru',
                            newVariantDetails.length,
                            Icons.palette_outlined,
                            onTap: () => showImportDetails(
                              'Varian baru',
                              'Varian dari Excel yang belum ada di katalog dan akan ditambahkan.',
                              newVariantDetails,
                            ),
                          ),
                          metricCard(
                            'Duplikat',
                            duplicates,
                            Icons.content_copy_outlined,
                            color: duplicates > 0 ? _orange : _muted,
                            onTap: () => showImportDetails(
                              'Duplikat',
                              'Baris berikut sudah tercatat sebelumnya dan tidak akan ditambahkan lagi.',
                              duplicateDetails,
                            ),
                          ),
                        ],
                      ),
                      if (importNote.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _orange.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline,
                                color: _orange,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: AppText(
                                  importNote,
                                  style: const TextStyle(
                                    color: _ink,
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              _PopTextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const AppText('Batal'),
              ),
              _PopFilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const AppText('Impor'),
              ),
            ],
          );
        },
      );
      if (!mounted || confirmed != true) return;
      final productsToAdd = productsByName.values
          .where((product) => newProductIds.contains(product.id))
          .toList();
      final productUpdates = <(Product, Product)>[];
      for (final product in productsByName.values) {
        if (newProductIds.contains(product.id)) continue;
        if (!existingProductIds.contains(product.id)) {
          throw StateError('Produk "${product.name}" tidak lagi tersedia.');
        }
        final existingProduct = _data.products
            .where((item) => item.id == product.id)
            .firstOrNull;
        if (existingProduct == null) {
          throw StateError('Produk "${product.name}" tidak lagi tersedia.');
        }
        productUpdates.add((existingProduct, product));
      }
      setState(() {
        for (final update in productUpdates) {
          update.$1.colors
            ..clear()
            ..addAll(update.$2.colors);
          update.$1.sizes
            ..clear()
            ..addAll(update.$2.sizes);
          update.$1.variants
            ..clear()
            ..addAll(update.$2.variants);
        }
        _data.products.addAll(productsToAdd);
        _data.sales.addAll(additions);
        if (additions.isNotEmpty) {
          _month = additions.last.date.substring(0, 7);
        }
      });
      _resetProductPickerAfterImport();
      if (!await _save()) return;
      if (!mounted) return;
      if (salesImportDialogContext.mounted) {
        Navigator.pop(salesImportDialogContext);
      }
      if (additions.isEmpty) {
        _message('Katalog produk berhasil diperbarui.');
      } else {
        final importDetails = <String>[
          if (newProductDetails.isNotEmpty)
            '${newProductDetails.length} produk baru ditambahkan.',
          if (newVariantDetails.isNotEmpty)
            '${newVariantDetails.length} varian baru ditambahkan.',
          if (newProductDetails.isNotEmpty)
            'HPP produk baru Rp0; lengkapi di katalog.',
          if (duplicates > 0) '$duplicates duplikat dilewati.',
        ];
        _message(
          '${additions.length} penjualan manual berhasil diimpor.'
          '${importDetails.isEmpty ? '' : ' ${importDetails.join(' ')}'}',
        );
      }
    } catch (error) {
      _message('Impor Excel manual gagal: $error', isError: true);
    }
  }

  Future<void> _exportExcel() async {
    try {
      final bytes = createFinanceExcelBytes(
        _data,
        _month,
        languageCode: appLanguageCode.value,
      );
      final path = await _withOutsideDismissedPicker(
        () => FilePicker.platform.saveFile(
          dialogTitle: localizeAppText('Ekspor data PocketR ke Excel'),
          fileName: 'pocketr-data-$_month.xlsx',
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
          bytes: Uint8List.fromList(bytes),
          lockParentWindow: true,
        ),
      );
      if (path != null) _message('Data Excel berhasil diekspor.');
    } catch (error) {
      _message('Ekspor Excel gagal: $error', isError: true);
    }
  }

  Future<void> _importShopeeSalesExcel(List<PlatformFile> files) async {
    try {
      if (files.length != 2) {
        throw const FormatException('Pilih kedua berkas ekspor Shopee.');
      }

      Future<List<List<List<String>>>> readSheets(PlatformFile file) async {
        final selectedBytes = file.bytes;
        final readStream = file.readStream;
        if (selectedBytes == null && readStream == null) {
          throw FormatException('Isi berkas "${file.name}" tidak terbaca.');
        }
        late final Uint8List bytes;
        if (selectedBytes != null) {
          bytes = Uint8List.fromList(selectedBytes);
        } else {
          final stream = readStream;
          if (stream == null) {
            throw FormatException('Isi berkas "${file.name}" tidak terbaca.');
          }
          bytes = Uint8List.fromList(
            await stream.fold<List<int>>(
              <int>[],
              (allBytes, chunk) => allBytes..addAll(chunk),
            ),
          );
        }
        return decodeShopeeWorkbookRows(bytes);
      }

      String normalize(String value) => value
          .replaceAll('\ufeff', '')
          .toLowerCase()
          .replaceAll(RegExp('[^a-z0-9]'), '');
      String normalizeProductName(String value) =>
          value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

      final loadedSheets = <List<List<List<String>>>>[];
      for (final file in files) {
        loadedSheets.add(await readSheets(file));
      }

      ({List<List<String>> rows, int headerIndex})? findTable(
        List<String> requiredHeaders,
      ) {
        for (final sheets in loadedSheets) {
          for (final rows in sheets) {
            for (var index = 0; index < rows.length; index++) {
              final header = rows[index].map(normalize).toSet();
              if (requiredHeaders.every(header.contains)) {
                return (rows: rows, headerIndex: index);
              }
            }
          }
        }
        return null;
      }

      final orderTable = findTable([
        'nopesanan',
        'statuspesanan',
        'jumlah',
        'subtotalpesanan',
      ]);
      if (orderTable == null) {
        throw const FormatException(
          'Tidak menemukan lembar rincian pesanan selesai Shopee.',
        );
      }
      final balanceTable = findTable([
        'tipetransaksi',
        'nopesanan',
        'jenistransaksi',
        'jumlah',
        'status',
      ]);
      if (balanceTable == null) {
        throw const FormatException(
          'Tidak menemukan lembar laporan saldo Shopee.',
        );
      }

      Map<String, int> columnsFor(
        List<String> header, {
        required Map<String, List<String>> aliases,
      }) {
        final columns = <String, int>{};
        final normalizedHeader = header.map(normalize).toList();
        for (final entry in aliases.entries) {
          final index = normalizedHeader.indexWhere(
            (value) => entry.value.contains(value),
          );
          if (index >= 0) columns[entry.key] = index;
        }
        return columns;
      }

      final orderHeader = orderTable.rows[orderTable.headerIndex];
      final orderColumns = columnsFor(
        orderHeader,
        aliases: const {
          'order': ['nopesanan'],
          'status': ['statuspesanan'],
          'sku': ['sku', 'nomorreferensisku', 'referencesku', 'productsku'],
          'parentSku': ['skuinduk', 'parentsku'],
          'variant': ['namavariasi'],
          'qty': ['jumlah'],
          'returned': ['returnedquantity'],
          'subtotal': ['subtotalpesanan'],
        },
      );
      if (!orderColumns.containsKey('sku') &&
          !orderColumns.containsKey('parentSku')) {
        throw const FormatException(
          'Kolom SKU atau SKU Induk tidak ditemukan di berkas rincian pesanan selesai.',
        );
      }
      final dateColumnIndex = findShopeeOrderDateColumnIndex(orderHeader);
      if (dateColumnIndex == null) {
        throw const FormatException(
          'Kolom Waktu Pesanan Dibuat atau Waktu Pembayaran Dilakukan '
          'tidak ditemukan.',
        );
      }
      orderColumns['date'] = dateColumnIndex;
      final balanceHeader = balanceTable.rows[balanceTable.headerIndex];
      final balanceColumns = columnsFor(
        balanceHeader,
        aliases: const {
          'transaction': ['tipetransaksi'],
          'order': ['nopesanan'],
          'direction': ['jenistransaksi'],
          'amount': ['jumlah'],
          'status': ['status'],
        },
      );

      String cell(List<String> row, Map<String, int> columns, String key) {
        final index = columns[key];
        return index == null || index >= row.length ? '' : row[index].trim();
      }

      String productTitleFromSku(List<String> row) {
        final sku = cell(row, orderColumns, 'sku');
        return sku.isNotEmpty ? sku : cell(row, orderColumns, 'parentSku');
      }

      double? parseAmount(String value) {
        var input = value.replaceAll(RegExp(r'[^0-9,.\-]'), '');
        if (input.isEmpty || input == '-') return null;
        final lastComma = input.lastIndexOf(',');
        final lastDot = input.lastIndexOf('.');
        if (lastComma >= 0 && lastDot >= 0) {
          if (lastComma > lastDot) {
            input = input.replaceAll('.', '').replaceFirst(',', '.');
          } else {
            input = input.replaceAll(',', '');
          }
        } else if (lastComma >= 0) {
          final decimals = input.length - lastComma - 1;
          input = decimals == 1 || decimals == 2
              ? input.replaceFirst(',', '.')
              : input.replaceAll(',', '');
        } else if (lastDot >= 0) {
          final decimals = input.length - lastDot - 1;
          input = decimals == 1 || decimals == 2
              ? input
              : input.replaceAll('.', '');
        }
        return double.tryParse(input);
      }

      double parseQuantity(String value) =>
          double.tryParse(value.replaceAll(',', '.')) ?? 0;

      String? parseDate(String value) {
        final dateInput = value.trim().split(RegExp(r'[ T]')).first;
        final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$')
            .firstMatch(dateInput);
        final local = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$')
            .firstMatch(dateInput);
        List<int>? parts;
        if (iso != null) {
          final year = iso[1];
          final month = iso[2];
          final day = iso[3];
          if (year == null || month == null || day == null) return null;
          parts = [int.parse(year), int.parse(month), int.parse(day)];
        } else if (local != null) {
          final day = local[1];
          final month = local[2];
          final year = local[3];
          if (year == null || month == null || day == null) return null;
          parts = [int.parse(year), int.parse(month), int.parse(day)];
        }
        if (parts == null) return null;
        final date = DateTime(parts[0], parts[1], parts[2]);
        if (date.year != parts[0] ||
            date.month != parts[1] ||
            date.day != parts[2]) {
          return null;
        }
        return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      }

      final productNamesByTitle = <String, String>{};
      final variantsByTitle = <String, Map<String, String>>{};
      final orderRows = orderTable.rows;
      for (
        var index = orderTable.headerIndex + 1;
        index < orderRows.length;
        index++
      ) {
        final row = orderRows[index];
        if (cell(row, orderColumns, 'order').isEmpty ||
            normalize(cell(row, orderColumns, 'status')) != 'selesai') {
          continue;
        }
        final qty =
            parseQuantity(cell(row, orderColumns, 'qty')) -
            parseQuantity(cell(row, orderColumns, 'returned'));
        final productTitle = productTitleFromSku(row);
        if (qty <= 0 || productTitle.isEmpty) continue;
        final titleKey = normalizeProductName(productTitle);
        productNamesByTitle.putIfAbsent(titleKey, () => productTitle);
        final productVariants = variantsByTitle.putIfAbsent(titleKey, () => {});
        final variants = cell(row, orderColumns, 'variant')
            .split('/')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList();
        for (final variant in variants) {
          productVariants.putIfAbsent(variant.toLowerCase(), () => variant);
        }
      }

      var newlyAddedProducts = 0;
      var newlyAddedColors = 0;
      final newProductDetails = <String>[];
      final newColorDetails = <String>[];
      final productsByTitle = <String, Product>{};
      final newProductIds = <String>{};
      for (final entry in productNamesByTitle.entries) {
        final existingProduct =
            _data.products
                .where((item) => normalizeProductName(item.name) == entry.key)
                .firstOrNull ??
            _data.products
                .where(
                  (item) =>
                      normalizeProductName(item.name) ==
                      normalizeProductName(entry.value),
                )
                .firstOrNull;
        final product = existingProduct == null
            ? Product(name: entry.value)
            : Product.fromJson(existingProduct.toJson());
        if (existingProduct == null) {
          newProductIds.add(product.id);
          newlyAddedProducts++;
          newProductDetails.add(product.name);
        }
        productsByTitle[entry.key] = product;
        for (final variant
            in variantsByTitle[entry.key]?.values ?? const <String>[]) {
          final lowerVariant = variant.toLowerCase();
          if (product.colors.any(
                (color) => color.toLowerCase() == lowerVariant,
              ) ||
              product.sizes.any((size) => size.toLowerCase() == lowerVariant)) {
            continue;
          }
          product.variants.removeWhere(
            (value) => value.toLowerCase() == lowerVariant,
          );
          product.colors.add(variant);
          newlyAddedColors++;
          newColorDetails.add('${product.name} · $variant');
        }
      }

      final incomeByOrder = <String, double>{};
      final balanceRows = balanceTable.rows;
      for (
        var index = balanceTable.headerIndex + 1;
        index < balanceRows.length;
        index++
      ) {
        final row = balanceRows[index];
        if (normalize(cell(row, balanceColumns, 'transaction')) !=
                'penghasilandaripesanan' ||
            normalize(cell(row, balanceColumns, 'direction')) !=
                'transaksimasuk' ||
            normalize(cell(row, balanceColumns, 'status')) !=
                'transaksiselesai') {
          continue;
        }
        final orderNo = cell(row, balanceColumns, 'order');
        final amount = parseAmount(cell(row, balanceColumns, 'amount'));
        if (orderNo.isEmpty || amount == null) continue;
        incomeByOrder.update(
          orderNo,
          (total) => total + amount,
          ifAbsent: () => amount,
        );
      }

      final linesByOrder = <String, List<_ShopeeImportLine>>{};
      final invalidOrders = <String>{};
      final invalidOrderDetails = <String, List<String>>{};
      final issues = <String>[];
      final ignoredStatusDetails = <String>[];
      final returnedDetails = <String>[];
      var ignoredStatuses = 0;
      var returnedRows = 0;
      for (
        var index = orderTable.headerIndex + 1;
        index < orderRows.length;
        index++
      ) {
        final row = orderRows[index];
        final orderNo = cell(row, orderColumns, 'order');
        if (orderNo.isEmpty) continue;
        final status = cell(row, orderColumns, 'status');
        if (normalize(status) != 'selesai') {
          ignoredStatuses++;
          ignoredStatusDetails.add(
            'Pesanan $orderNo · status ${status.isEmpty ? '(kosong)' : status}\n'
            '${productTitleFromSku(row)} · '
            'Qty ${cell(row, orderColumns, 'qty')}',
          );
          continue;
        }

        final excelRow = index + 1;
        final date = parseDate(cell(row, orderColumns, 'date'));
        final soldQty = parseQuantity(cell(row, orderColumns, 'qty'));
        final returnedQty = parseQuantity(cell(row, orderColumns, 'returned'));
        final qty = soldQty - returnedQty;
        if (qty <= 0) {
          returnedRows++;
          returnedDetails.add(
            'Pesanan $orderNo\n'
            '${productTitleFromSku(row)} · '
            'Terjual ${formatNumber(soldQty)} · Dikembalikan ${formatNumber(returnedQty)}',
          );
          continue;
        }
        final productTitle = productTitleFromSku(row);
        final product = productsByTitle[normalizeProductName(productTitle)];
        if (date == null ||
            soldQty <= 0 ||
            productTitle.isEmpty ||
            product == null) {
          invalidOrders.add(orderNo);
          final problem = date == null
              ? 'tanggal selesai tidak valid'
              : soldQty <= 0
              ? 'jumlah tidak valid'
              : productTitle.isEmpty
              ? 'SKU produk kosong'
              : 'SKU "$productTitle" tidak bisa ditambahkan ke katalog';
          invalidOrderDetails
              .putIfAbsent(orderNo, () => [])
              .add('Baris $excelRow: $problem.');
          if (issues.length < 8) {
            issues.add('Baris $excelRow: $problem.');
          }
          continue;
        }

        var color = '';
        var size = '';
        var other = '';
        final variant = cell(row, orderColumns, 'variant');
        var invalidVariant = false;
        for (final part in variant.split('/').map((value) => value.trim())) {
          if (part.isEmpty) continue;
          final colorMatch = product.colors
              .where((value) => value.toLowerCase() == part.toLowerCase())
              .firstOrNull;
          final sizeMatch = product.sizes
              .where((value) => value.toLowerCase() == part.toLowerCase())
              .firstOrNull;
          final otherMatch = product.variants
              .where((value) => value.toLowerCase() == part.toLowerCase())
              .firstOrNull;
          if (colorMatch != null) {
            color = colorMatch;
          } else if (sizeMatch != null) {
            size = sizeMatch;
          } else if (otherMatch != null) {
            other = otherMatch;
          } else {
            invalidVariant = true;
            final detail =
                'Baris $excelRow: varian "$part" belum ada di katalog.';
            invalidOrderDetails.putIfAbsent(orderNo, () => []).add(detail);
            if (issues.length < 8) {
              issues.add(detail);
            }
          }
        }
        if (invalidVariant) {
          invalidOrders.add(orderNo);
          continue;
        }

        final subtotal =
            parseAmount(cell(row, orderColumns, 'subtotal')) ?? 0.0;
        final weight = soldQty > 0
            ? (subtotal > 0 ? subtotal : qty) * qty / soldQty
            : 0.0;
        linesByOrder
            .putIfAbsent(orderNo, () => [])
            .add(
              _ShopeeImportLine(
                date: date,
                product: product,
                productName: productTitle,
                qty: qty,
                color: color,
                size: size,
                other: other,
                weight: weight,
              ),
            );
      }

      final known = _data.sales
          .map(
            (sale) =>
                '${sale.platform}|${sale.orderNo}|${sale.productId}|${sale.variant}|${sale.date}',
          )
          .toSet();
      final additionsByKey = <String, Sale>{};
      var missingBalanceOrders = 0;
      var duplicates = 0;
      var skippedInvalidOrders = invalidOrders.length;
      final missingBalanceDetails = <String>[];
      final duplicateDetails = <String>[];
      final skippedDetails = invalidOrderDetails.entries
          .map((entry) => 'Pesanan ${entry.key}\n${entry.value.join('\n')}')
          .toList();

      String describeLine(_ShopeeImportLine line) {
        final variant = [
          line.color,
          line.size,
          line.other,
        ].where((value) => value.isNotEmpty).join(' / ');
        return '${line.productName}'
            '${variant.isEmpty ? '' : ' · $variant'}'
            ' · Qty ${formatNumber(line.qty)}';
      }

      for (final entry in linesByOrder.entries) {
        final orderNo = entry.key;
        final lines = entry.value;
        final orderIncome = incomeByOrder[orderNo];
        if (orderIncome == null) {
          missingBalanceOrders++;
          missingBalanceDetails.add(
            'Pesanan $orderNo\n${lines.map(describeLine).join('\n')}',
          );
          continue;
        }
        if (invalidOrders.contains(orderNo)) {
          continue;
        }
        final totalWeight = lines.fold<double>(
          0,
          (total, line) => total + line.weight,
        );
        if (totalWeight <= 0) {
          skippedInvalidOrders++;
          skippedDetails.add('Pesanan $orderNo: subtotal produk tidak valid.');
          if (issues.length < 8) {
            issues.add('Pesanan $orderNo: subtotal produk tidak valid.');
          }
          continue;
        }

        var remainingAmount = orderIncome;
        for (var index = 0; index < lines.length; index++) {
          final line = lines[index];
          final amount = index == lines.length - 1
              ? remainingAmount
              : (orderIncome * line.weight / totalWeight).roundToDouble();
          remainingAmount -= amount;
          final sale = Sale(
            date: line.date,
            platform: 'shopee',
            productId: line.product.id,
            productName: line.productName,
            qty: line.qty,
            orderNo: orderNo,
            received: amount,
            hpp: _data.productHpp(line.product),
            color: line.color,
            size: line.size,
            other: line.other,
          );
          final key =
              '${sale.platform}|${sale.orderNo}|${sale.productId}|${sale.variant}|${sale.date}';
          final existing = additionsByKey[key];
          if (existing != null) {
            existing
              ..qty += sale.qty
              ..received += sale.received;
            continue;
          }
          if (known.contains(key)) {
            duplicates++;
            final variant = sale.variant.isEmpty ? '' : ' · ${sale.variant}';
            duplicateDetails.add(
              'Pesanan ${sale.orderNo}\n'
              '${sale.productName}$variant · Qty ${formatNumber(sale.qty)}',
            );
            continue;
          }
          additionsByKey[key] = sale;
          known.add(key);
        }
      }

      final additions = additionsByKey.values.toList();
      final addedSaleDetails = additions.map((sale) {
        final variant = sale.variant.isEmpty ? '' : ' · ${sale.variant}';
        return 'Pesanan ${sale.orderNo}\n'
            '${sale.productName}$variant · Qty ${formatNumber(sale.qty)} · '
            '${sale.date} · ${formatMoney(sale.received)}';
      }).toList();
      if (additions.isEmpty) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          barrierColor: const Color(0x180f202c),
          builder: (context) => AlertDialog(
            title: const AppText('Tidak ada penjualan yang bisa diimpor'),
            content: AppText(
              'Tidak ada baris penjualan yang bisa ditambahkan. '
              '${newlyAddedProducts > 0 || newlyAddedColors > 0 ? '$newlyAddedProducts produk baru dan $newlyAddedColors warna dari Excel tetap disimpan. HPP produk baru Rp0; lengkapi di katalog. ' : ''}'
              '${missingBalanceOrders > 0 ? '$missingBalanceOrders pesanan belum ditemukan di laporan saldo. ' : ''}'
              '${skippedInvalidOrders > 0 ? '$skippedInvalidOrders pesanan dilewati karena data produk/varian. ' : ''}'
              '${duplicates > 0 ? '$duplicates duplikat dilewati. ' : ''}'
              '${issues.isEmpty ? '' : '\n\n${issues.take(5).join('\n')}'}',
            ),
            actions: [
              _PopTextButton(
                onPressed: () => Navigator.pop(context),
                child: const AppText('Tutup'),
              ),
            ],
          ),
        );
        return;
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        barrierColor: const Color(0x180f202c),
        builder: (context) {
          final dialogWidth = (MediaQuery.sizeOf(context).width - 48)
              .clamp(280.0, 620.0)
              .toDouble();
          final metricColumns = dialogWidth >= 520
              ? 3
              : dialogWidth >= 360
              ? 2
              : 1;
          final metricWidth =
              (dialogWidth - 8 * (metricColumns - 1)) / metricColumns;
          final importNotes = [
            if (returnedRows > 0)
              '$returnedRows baris dengan semua qty dikembalikan akan diabaikan.',
            if (newlyAddedProducts > 0)
              'Produk baru belum memiliki bahan/HPP. HPP penjualan awal Rp0; '
                  'lengkapi HPP di katalog setelah impor.',
          ].join(' ');

          Future<void> showImportDetails(
            String title,
            String description,
            List<String> entries,
          ) async {
            final detailsWidth = (dialogWidth - 40)
                .clamp(220.0, 520.0)
                .toDouble();
            final detailsHeight = (MediaQuery.sizeOf(context).height * .48)
                .clamp(140.0, 420.0)
                .toDouble();
            await showDialog<void>(
              context: context,
              barrierColor: const Color(0x180f202c),
              builder: (detailsContext) => AlertDialog(
                title: AppText(title),
                content: SizedBox(
                  width: detailsWidth,
                  height: detailsHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        description,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: entries.isEmpty
                            ? const Center(
                                child: AppText(
                                  'Tidak ada data pada bagian ini.',
                                  style: TextStyle(color: _muted),
                                ),
                              )
                            : ListView.separated(
                                itemCount: entries.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 6),
                                itemBuilder: (context, index) => Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: _blue.withValues(alpha: .07),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ValueListenableBuilder<String>(
                                    valueListenable: appLanguageCode,
                                    builder: (context, languageCode, _) =>
                                        SelectableText(
                                          localizeShopeeImportDetail(
                                            entries[index],
                                            languageCode: languageCode,
                                          ),
                                          style: const TextStyle(
                                            color: _ink,
                                            fontSize: 12,
                                            height: 1.4,
                                          ),
                                        ),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  _PopTextButton(
                    onPressed: () => Navigator.pop(detailsContext),
                    child: const AppText('Tutup'),
                  ),
                ],
              ),
            );
          }

          Widget metricCard(
            String label,
            int value,
            IconData icon, {
            Color color = _blue,
            required VoidCallback onTap,
          }) => SizedBox(
            width: metricWidth,
            height: 68,
            child: Tooltip(
              message: localizeAppText('Klik untuk melihat detail: $label'),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .38),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .62),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(icon, color: color, size: 19),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppText(
                                '$value',
                                style: TextStyle(
                                  color: color,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              AppText(
                                label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 11,
                                  height: 1.25,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );

          return AlertDialog(
            title: const AppText('Konfirmasi impor Shopee'),
            content: SizedBox(
              width: dialogWidth,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .68,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Tooltip(
                        message: localizeAppText(
                          'Klik untuk melihat daftar penjualan',
                        ),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => showImportDetails(
                              'Penjualan siap diimpor',
                              'Rincian setiap baris penjualan yang akan ditambahkan.',
                              addedSaleDetails,
                            ),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(15),
                              decoration: BoxDecoration(
                                color: _blue.withValues(alpha: .09),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: _blue.withValues(alpha: .14),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: _blue.withValues(alpha: .13),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.receipt_long_outlined,
                                      color: _blue,
                                      size: 21,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        AppText(
                                          '${additions.length} baris penjualan',
                                          style: const TextStyle(
                                            color: _ink,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        const AppText(
                                          'Siap ditambahkan dari berkas Shopee.',
                                          style: TextStyle(
                                            color: _muted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          metricCard(
                            'Produk baru',
                            newlyAddedProducts,
                            Icons.inventory_2_outlined,
                            onTap: () => showImportDetails(
                              'Produk baru',
                              'Produk dari Excel yang belum ada di katalog dan akan ditambahkan.',
                              newProductDetails,
                            ),
                          ),
                          metricCard(
                            'Warna baru',
                            newlyAddedColors,
                            Icons.palette_outlined,
                            onTap: () => showImportDetails(
                              'Warna baru',
                              'Varian warna yang akan ditambahkan ke produk terkait.',
                              newColorDetails,
                            ),
                          ),
                          metricCard(
                            'Tidak ada di laporan saldo',
                            missingBalanceOrders,
                            Icons.receipt_outlined,
                            color: missingBalanceOrders > 0 ? _orange : _muted,
                            onTap: () => showImportDetails(
                              'Tidak ada di laporan saldo',
                              'Pesanan ditemukan di rincian pesanan selesai, tetapi tidak ada transaksi masuk yang cocok di laporan saldo.',
                              missingBalanceDetails,
                            ),
                          ),
                          metricCard(
                            'Produk/varian dilewati',
                            skippedInvalidOrders,
                            Icons.warning_amber_rounded,
                            color: skippedInvalidOrders > 0 ? _red : _muted,
                            onTap: () => showImportDetails(
                              'Produk/varian dilewati',
                              'Pesanan yang tidak diimpor karena data produk, varian, tanggal, jumlah, atau subtotal bermasalah.',
                              skippedDetails,
                            ),
                          ),
                          metricCard(
                            'Duplikat',
                            duplicates,
                            Icons.content_copy_outlined,
                            color: duplicates > 0 ? _orange : _muted,
                            onTap: () => showImportDetails(
                              'Duplikat',
                              'Baris berikut sudah tercatat sebelumnya dan tidak akan ditambahkan lagi.',
                              duplicateDetails,
                            ),
                          ),
                          metricCard(
                            'Status belum selesai',
                            ignoredStatuses,
                            Icons.pending_outlined,
                            onTap: () => showImportDetails(
                              'Status belum selesai',
                              'Baris ini diabaikan karena status pesanan belum selesai.',
                              ignoredStatusDetails,
                            ),
                          ),
                        ],
                      ),
                      if (importNotes.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Tooltip(
                          message: localizeAppText(
                            'Klik untuk melihat detail catatan impor',
                          ),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: () => showImportDetails(
                                'Catatan impor',
                                importNotes,
                                [
                                  ...returnedDetails,
                                  if (newProductDetails.isNotEmpty)
                                    'Produk baru belum memiliki bahan/HPP. '
                                        'HPP penjualan awal Rp0; lengkapi HPP di katalog.',
                                  ...newProductDetails,
                                ],
                              ),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _orange.withValues(alpha: .1),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.info_outline,
                                      color: _orange,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: AppText(
                                        importNotes,
                                        style: const TextStyle(
                                          color: _ink,
                                          fontSize: 12,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (issues.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        AppText(
                          'Contoh data yang perlu diperiksa',
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final issue in issues.take(5))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: AppText(
                              '• $issue',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 11,
                                height: 1.35,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              _PopTextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const AppText('Batal'),
              ),
              _PopFilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const AppText('Impor'),
              ),
            ],
          );
        },
      );
      if (!mounted || confirmed != true) return;
      final productsToAdd = <Product>[];
      final productUpdates = <(Product, Product)>[];
      for (final product in productsByTitle.values) {
        if (newProductIds.contains(product.id)) {
          productsToAdd.add(product);
          continue;
        }
        final existingProduct = _data.products
            .where((item) => item.id == product.id)
            .firstOrNull;
        if (existingProduct == null) {
          throw StateError('Produk "${product.name}" tidak lagi tersedia.');
        }
        productUpdates.add((existingProduct, product));
      }
      setState(() {
        for (final update in productUpdates) {
          update.$1.colors
            ..clear()
            ..addAll(update.$2.colors);
          update.$1.variants
            ..clear()
            ..addAll(update.$2.variants);
        }
        _data.products.addAll(productsToAdd);
        _data.sales.addAll(additions);
        _month = additions.last.date.substring(0, 7);
      });
      _resetProductPickerAfterImport();
      if (!await _save()) return;
      _message(
        '${additions.length} penjualan Shopee berhasil diimpor.'
        '${newlyAddedProducts > 0 || newlyAddedColors > 0 ? ' $newlyAddedProducts produk baru dan $newlyAddedColors warna ditambahkan. Lengkapi HPP produk baru di katalog.' : ''}',
      );
    } catch (error) {
      _message('Impor Excel Shopee gagal: $error', isError: true);
    }
  }

  void _resetProductPickerAfterImport() {
    _selectedProductId = null;
    if (_productPickerScrollController.hasClients) {
      _productPickerScrollController.jumpTo(0);
    }
  }

  Future<void> _reset() async {
    final ok = await _confirm(
      'Hapus semua data?',
      'Produk, bahan, penjualan, pengeluaran, dan pengaturan akan dihapus permanen.',
    );
    if (!ok) return;
    if (_data.logo.isNotEmpty) {
      try {
        await LocalFileArchive.instance.deleteApplicationImage('profile_logo');
      } catch (error) {
        _message('Foto profil gagal dihapus saat reset: $error', isError: true);
        return;
      }
    }
    try {
      await FinanceSqliteStore.instance.clearData();
      await _persistSelectedMonth(_month);
    } catch (error) {
      _message('Data gagal dihapus: $error', isError: true);
      return;
    }
    setState(() {
      _data = FinanceData();
      _selectedProductId = null;
      _sidebarProfileImageData = null;
      _sidebarProfileImage = null;
      _productImageSources.clear();
      _productImageProviders.clear();
    });
    _message('Semua data telah dihapus.');
  }

  void _navigate(String tab) {
    final navigator = _pageNavigatorKey.currentState;
    if (tab == _tab || navigator == null) return;

    _tab = tab;
    _search = '';
    _searchController.clear();
    _slideUpEntranceOrder.reset();
    _navigationRefresh.value++;
    unawaited(navigator.pushReplacement<void, void>(_pageRoute(tab)));
  }

  Future<void> _editSidebarProfile() async {
    final business = TextEditingController(text: _data.businessName);
    final tagline = TextEditingController(text: _data.tagline);
    final navigator = Navigator.of(context);
    var saveScheduled = false;
    void submitProfile() {
      if (saveScheduled) return;
      saveScheduled = true;
      FocusManager.instance.primaryFocus?.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted) navigator.pop(true);
      });
    }

    var selectedLogo = _data.logo;
    Uint8List? pendingLogoBytes;
    String? pendingLogoMime;
    final tapDetails = _profileTapDetails;
    _profileTapDetails = null;
    final viewportSize = MediaQuery.sizeOf(context);
    final profilePosition = tapDetails == null
        ? null
        : tapDetails.globalPosition - tapDetails.localPosition;
    const profileButtonSize = 30.0;
    const popupGap = 8.0;
    final popupLeft = profilePosition == null
        ? 0.0
        : profilePosition.dx.clamp(16.0, viewportSize.width - 456);
    final popupTop = profilePosition == null
        ? 0.0
        : (profilePosition.dy + profileButtonSize + popupGap).clamp(
            16.0,
            (viewportSize.height - 636).clamp(16.0, double.infinity),
          );
    final ok = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0x180f202c),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final scale = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final dialog = Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: profilePosition == null
              ? const EdgeInsets.all(24)
              : EdgeInsets.zero,
          child: StatefulBuilder(
            builder: (context, setDialogState) => ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440, maxHeight: 620),
              child: SizedBox(
                width: 440,
                child: _FrostedSurface(
                  borderRadius: BorderRadius.circular(28),
                  tintColor: _popupTintColor,
                  tintOpacity: _popupTintOpacity,
                  padding: const EdgeInsets.all(24),
                  blurSigma: 10,
                  prominentShadow: true,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: AppText(
                                'Profil bisnis',
                                style: TextStyle(
                                  color: _ink,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            _PopIconButton(
                              tooltip: localizeAppText('Tutup'),
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white.withValues(
                                  alpha: .42,
                                ),
                                foregroundColor: _muted,
                                minimumSize: const Size(32, 32),
                                padding: EdgeInsets.zero,
                              ),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _ProfileAvatar(
                              image:
                                  _imageFromData(selectedLogo) ??
                                  _defaultBrandImageProvider,
                              size: 68,
                              framed: false,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _ButtonPop(
                                    intensity: .5,
                                    child: _FrostedSurface(
                                      borderRadius: BorderRadius.circular(99),
                                      tintColor: Colors.white,
                                      tintOpacity: .48,
                                      blurSigma: 14,
                                      shadow: false,
                                      child: TextButton.icon(
                                        onPressed: () async {
                                          try {
                                            final picked =
                                                await _withOutsideDismissedPicker(
                                                  () => FilePicker.platform
                                                      .pickFiles(
                                                        dialogTitle:
                                                            localizeAppText(
                                                              'Pilih logo usaha',
                                                            ),
                                                        type: FileType.custom,
                                                        allowedExtensions: [
                                                          'png',
                                                          'jpg',
                                                          'jpeg',
                                                          'webp',
                                                        ],
                                                        withData: true,
                                                        lockParentWindow: true,
                                                      ),
                                                );
                                            if (picked == null ||
                                                picked.files.isEmpty) {
                                              return;
                                            }
                                            final file = picked.files.single;
                                            final bytes = file.bytes;
                                            if (bytes == null) {
                                              throw const FormatException(
                                                'Isi berkas foto tidak terbaca.',
                                              );
                                            }
                                            final mime = _imageMimeFromName(
                                              file.name,
                                            );
                                            final logo =
                                                'data:$mime;base64,${base64Encode(bytes)}';
                                            setDialogState(() {
                                              selectedLogo = logo;
                                              pendingLogoBytes = bytes;
                                              pendingLogoMime = mime;
                                            });
                                          } catch (error) {
                                            _message(
                                              'Foto profil tidak bisa dibuka: $error',
                                              isError: true,
                                            );
                                          }
                                        },
                                        style: TextButton.styleFrom(
                                          foregroundColor: _ink,
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 9,
                                          ),
                                          shape: const StadiumBorder(),
                                          textStyle: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.image_outlined,
                                          size: 16,
                                        ),
                                        label: const AppText(
                                          'Pilih logo dari komputer',
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (selectedLogo.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: _ButtonPop(
                                        intensity: .5,
                                        child: _FrostedSurface(
                                          borderRadius: BorderRadius.circular(
                                            99,
                                          ),
                                          tintColor: Colors.white,
                                          tintOpacity: .48,
                                          blurSigma: 14,
                                          shadow: false,
                                          child: TextButton.icon(
                                            onPressed: () async {
                                              setDialogState(() {
                                                selectedLogo = '';
                                                pendingLogoBytes = null;
                                                pendingLogoMime = null;
                                              });
                                            },
                                            style: TextButton.styleFrom(
                                              foregroundColor: _red,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 9,
                                                  ),
                                              shape: const StadiumBorder(),
                                              textStyle: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              size: 16,
                                            ),
                                            label: const AppText('Hapus logo'),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _profileDialogField(
                          business,
                          'Nama bisnis',
                          onSubmitted: (_) => submitProfile(),
                        ),
                        const SizedBox(height: 12),
                        _profileDialogField(
                          tagline,
                          'Tulisan di bawah nama',
                          onSubmitted: (_) => submitProfile(),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _ImportDialogPill(
                              label: 'Batal',
                              labelOffset: -1,
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                            ),
                            const SizedBox(width: 8),
                            _ImportDialogPill(
                              label: 'Simpan',
                              blue: true,
                              labelOffset: -1,
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final animatedDialog = FadeTransition(
          opacity: Tween<double>(begin: .92, end: 1).animate(scale),
          child: ScaleTransition(
            scale: Tween<double>(begin: .9, end: 1).animate(scale),
            alignment: Alignment.topLeft,
            child: RepaintBoundary(child: dialog),
          ),
        );
        if (profilePosition == null) return animatedDialog;
        return Stack(
          children: [
            Positioned(left: popupLeft, top: popupTop, child: animatedDialog),
          ],
        );
      },
    );
    if (ok == true) {
      if (pendingLogoBytes != null && pendingLogoMime != null) {
        try {
          await LocalFileArchive.instance.saveApplicationImage(
            key: 'profile_logo',
            mime: pendingLogoMime!,
            bytes: pendingLogoBytes!,
          );
        } catch (error) {
          _message('Foto profil tidak bisa disimpan: $error', isError: true);
          business.dispose();
          tagline.dispose();
          return;
        }
      }
      setState(() {
        _data
          ..businessName = business.text.trim().isEmpty
              ? 'PocketR'
              : business.text.trim()
          ..tagline = tagline.text.trim()
          ..logo = selectedLogo;
      });
      if (selectedLogo.isEmpty && pendingLogoBytes == null) {
        await _saveApplicationImage('profile_logo', '', null);
      }
      await _save();
      _message('Profil berhasil diperbarui.');
    }
    Future<void>.delayed(const Duration(milliseconds: 260), () {
      business.dispose();
      tagline.dispose();
    });
  }

  Widget _profileDialogField(
    TextEditingController controller,
    String label, {
    TextInputType? keyboard,
    bool percentage = false,
    bool showLabel = true,
    ValueChanged<String>? onSubmitted,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (showLabel)
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 5),
          child: AppText(
            label,
            style: const TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        )
      else
        const SizedBox.shrink(),
      DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1421423a),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: _windowAwareBlur(
            sigmaX: 18,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: .72),
                    const Color(0xffe6f4fb).withValues(alpha: .68),
                  ],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: .48)),
              ),
              child: SizedBox(
                height: 40,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Transform.translate(
                    offset: const Offset(0, 11),
                    child: TextField(
                      controller: controller,
                      textInputAction: onSubmitted == null
                          ? null
                          : TextInputAction.done,
                      onSubmitted: onSubmitted,
                      keyboardType: percentage
                          ? TextInputType.number
                          : keyboard,
                      textAlign: percentage
                          ? TextAlign.center
                          : TextAlign.start,
                      textAlignVertical: TextAlignVertical.center,
                      inputFormatters: percentage
                          ? [FilteringTextInputFormatter.digitsOnly]
                          : keyboard == null
                          ? null
                          : [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,]'),
                              ),
                            ],
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 13,
                        height: 1,
                      ),
                      decoration: InputDecoration(
                        filled: false,
                        isCollapsed: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        suffix: percentage
                            ? Transform.translate(
                                offset: const Offset(0, -2),
                                child: const AppText(
                                  '%',
                                  style: TextStyle(
                                    color: _muted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Future<void> _showSettings() async {
    final navigator = Navigator.of(context);
    var closeScheduled = false;
    final backupStatus = ValueNotifier(const _BackupProgressStatus());
    void closeSettings() {
      if (closeScheduled) return;
      closeScheduled = true;
      FocusManager.instance.primaryFocus?.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted) navigator.pop();
      });
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0x180f202c),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, animation, secondaryAnimation) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: MediaQuery.sizeOf(context).height * .85,
          ),
          child: Focus(
            canRequestFocus: false,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                closeSettings();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: _FrostedSurface(
              borderRadius: BorderRadius.circular(28),
              tintColor: _popupTintColor,
              tintOpacity: _popupTintOpacity,
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
              blurSigma: 12,
              prominentShadow: true,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context)
                    .copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: AppText(
                              'Pengaturan',
                              style: TextStyle(
                                color: _ink,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          _PopIconButton(
                            tooltip: localizeAppText('Tutup'),
                            onPressed: closeSettings,
                            style: IconButton.styleFrom(
                              foregroundColor: _muted,
                              backgroundColor: Colors.white.withValues(
                                alpha: .5,
                              ),
                              minimumSize: const Size(32, 32),
                              padding: EdgeInsets.zero,
                            ),
                            icon: const Icon(Icons.close, size: 17),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _languageSettingsCard(),
                      const SizedBox(height: 14),
                      _autoSaveSettingsCard(),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .48),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .78),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const AppText(
                              'Backup seluruh data',
                              style: TextStyle(
                                color: _ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            AppText(
                              'Simpan data, foto profil dan produk, serta berkas impor agar bisa dipulihkan di perangkat lain.',
                              style: TextStyle(
                                color: _muted,
                                fontSize: 12,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ValueListenableBuilder<_BackupProgressStatus>(
                              valueListenable: backupStatus,
                              builder: (context, status, _) => Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Wrap(
                                      alignment: WrapAlignment.end,
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _ImportDialogPill(
                                          icon: Icons.restore_outlined,
                                          label: 'Restore Settings',
                                          labelOffset: -1,
                                          onPressed: () => unawaited(
                                            _restore(
                                              closeSettingsOnSuccess: true,
                                            ),
                                          ),
                                        ),
                                        _ImportDialogPill(
                                          icon: Icons.backup_outlined,
                                          label: 'Backup Settings',
                                          blue: true,
                                          labelOffset: -1,
                                          onPressed: status.isLoading
                                              ? null
                                              : () => unawaited(
                                                  _backupAllData(
                                                    onStatus:
                                                        (
                                                          message, {
                                                          isError = false,
                                                          isLoading = false,
                                                        }) {
                                                          if (!context
                                                              .mounted) {
                                                            return;
                                                          }
                                                          backupStatus.value =
                                                              _BackupProgressStatus(
                                                                message:
                                                                    message,
                                                                isError:
                                                                    isError,
                                                                isLoading:
                                                                    isLoading,
                                                              );
                                                        },
                                                  ),
                                                ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (status.message.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        if (status.isLoading) ...[
                                          const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: _blue,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Flexible(
                                          child: AppText(
                                            status.message,
                                            style: TextStyle(
                                              color: status.isError
                                                  ? _red
                                                  : const Color(0xff188a53),
                                              fontSize: 11,
                                              height: 1.4,
                                            ),
                                            textAlign: TextAlign.right,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _resetWarningCard(
                        onReset: () {
                          closeSettings();
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) unawaited(_reset());
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          _normalDialogTransition(animation, child),
    );
  }

  Future<void> _showAbout() async {
    final navigator = Navigator.of(context);
    var closeScheduled = false;
    void closeAbout() {
      if (closeScheduled) return;
      closeScheduled = true;
      FocusManager.instance.primaryFocus?.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted) navigator.pop();
      });
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0x180f202c),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, animation, secondaryAnimation) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 960,
            maxHeight: MediaQuery.sizeOf(context).height * .9,
          ),
          child: Focus(
            canRequestFocus: false,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                closeAbout();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: _FrostedSurface(
              borderRadius: BorderRadius.circular(28),
              tintColor: _popupTintColor,
              tintOpacity: _popupTintOpacity,
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 22),
              blurSigma: 12,
              prominentShadow: true,
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: AppText(
                          'Tentang PocketR',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _PopIconButton(
                        tooltip: localizeAppText('Tutup'),
                        onPressed: closeAbout,
                        style: IconButton.styleFrom(
                          foregroundColor: _muted,
                          backgroundColor: Colors.white.withValues(alpha: .5),
                          minimumSize: const Size(32, 32),
                          padding: EdgeInsets.zero,
                        ),
                        icon: const Icon(Icons.close, size: 17),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(child: SingleChildScrollView(child: _aboutPage())),
                ],
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          _normalDialogTransition(animation, child),
    );
  }

  Widget _languageSettingsCard() => StatefulBuilder(
    builder: (context, setCardState) {
      Future<void> selectLanguage(String languageCode) async {
        await _setLanguageCode(languageCode);
        if (context.mounted) setCardState(() {});
      }

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .48),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: .78)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _blue.withValues(alpha: .1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.language_rounded,
                    color: _blue,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppText(
                        'Bahasa aplikasi',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      AppText(
                        'Pilih bahasa untuk seluruh tampilan aplikasi.',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            Row(
              children: [
                Expanded(
                  child: _frostedChoicePill(
                    label: _languageCode == 'en'
                        ? 'Indonesian'
                        : 'Bahasa Indonesia',
                    selected: _languageCode == 'id',
                    fontSize: 12,
                    onPressed: () => unawaited(selectLanguage('id')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _frostedChoicePill(
                    label: 'English',
                    selected: _languageCode == 'en',
                    fontSize: 12,
                    onPressed: () => unawaited(selectLanguage('en')),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  Widget _resetWarningCard({required VoidCallback onReset}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _red.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _red.withValues(alpha: .24)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _red.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: Transform.translate(
                offset: const Offset(0, -1),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: _red,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 11),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    'Peringatan',
                    style: TextStyle(
                      color: _red,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  SizedBox(height: 4),
                  AppText(
                    'Atur ulang akan menghapus ringkasan, penjualan, '
                    'pengeluaran, produk, bahan baku/HPP, dan '
                    'pengaturan secara permanen. Pastikan data '
                    'yang masih dibutuhkan sudah dicadangkan.',
                    style: TextStyle(color: _ink, fontSize: 12, height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: _ImportDialogPill(
            icon: Icons.delete_outline,
            label: 'Atur ulang semua data',
            labelOffset: 0,
            danger: true,
            onPressed: onReset,
          ),
        ),
      ],
    ),
  );

  Widget _autoSaveSettingsCard() => StatefulBuilder(
    builder: (context, setCardState) {
      final directory = _autoSaveDirectory;
      final lastSavedAt = _autoSaveLastSavedAt;
      final savedTime = lastSavedAt == null
          ? null
          : '${lastSavedAt.hour.toString().padLeft(2, '0')}:'
                '${lastSavedAt.minute.toString().padLeft(2, '0')}';
      final status = _autoSaveLastError != null
          ? 'Gagal: $_autoSaveLastError'
          : !_autoSaveEnabled
          ? 'Auto-save nonaktif'
          : directory?.isNotEmpty != true
          ? 'Pilih folder untuk memulai auto-save'
          : savedTime == null
          ? 'Auto-save aktif · menunggu pencadangan pertama'
          : 'File terakhir diperbarui pukul $savedTime';
      final statusColor = _autoSaveLastError != null
          ? _red
          : _autoSaveEnabled && directory?.isNotEmpty != true
          ? _red
          : _autoSaveEnabled
          ? _green
          : _muted;
      final intervalRows = <List<int>>[
        for (var start = 0; start < _autoSaveIntervals.length; start += 4)
          _autoSaveIntervals.sublist(
            start,
            start + 4 < _autoSaveIntervals.length
                ? start + 4
                : _autoSaveIntervals.length,
          ),
      ];

      Future<void> toggleAutoSave() async {
        await _setAutoSaveEnabled(!_autoSaveEnabled);
        if (context.mounted) setCardState(() {});
      }

      Future<void> selectAutoSaveDirectory() async {
        await _selectAutoSaveDirectory();
        if (context.mounted) setCardState(() {});
      }

      Future<void> selectAutoSaveInterval(int minutes) async {
        await _setAutoSaveInterval(minutes);
        if (context.mounted) setCardState(() {});
      }

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .48),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: .78)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: AppText(
                    'Auto-save lokal',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _frostedAutoSaveToggle(
                  onPressed: () => unawaited(toggleAutoSave()),
                ),
              ],
            ),
            const SizedBox(height: 1),
            AppText(
              'Satu file cadangan akan ditimpa setiap interval.',
              style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 14),
            const AppText(
              'Interval',
              style: TextStyle(
                color: _ink,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 8.0;
                final pillWidth = (constraints.maxWidth - spacing * 3) / 4;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (
                      var rowIndex = 0;
                      rowIndex < intervalRows.length;
                      rowIndex++
                    )
                      Padding(
                        padding: EdgeInsets.only(top: rowIndex == 0 ? 0 : 6),
                        child: Wrap(
                          spacing: spacing,
                          children: [
                            for (final minutes in intervalRows[rowIndex])
                              SizedBox(
                                width: pillWidth,
                                child: _frostedChoicePill(
                                  label: minutes == 60
                                      ? '1 jam'
                                      : '$minutes mnt',
                                  selected: _autoSaveIntervalMinutes == minutes,
                                  onPressed: () => unawaited(
                                    selectAutoSaveInterval(minutes),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.folder_outlined, color: _muted, size: 18),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppText(
                        'Direktori penyimpanan',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      AppText(
                        directory ?? 'Belum dipilih',
                        translate: directory == null,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _muted,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _ImportDialogPill(
                  label: 'Pilih folder',
                  icon: Icons.folder_open_rounded,
                  labelOffset: -1,
                  onPressed: () => unawaited(selectAutoSaveDirectory()),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  _autoSaveLastError != null
                      ? Icons.error_outline_rounded
                      : _autoSaveEnabled && directory?.isNotEmpty == true
                      ? Icons.check_circle_outline_rounded
                      : Icons.info_outline_rounded,
                  color: statusColor,
                  size: 15,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: AppText(
                    status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (_autoSaveEnabled && directory?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              AppText(
                'File: pocketr-autosave.pcktr',
                style: TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ],
        ),
      );
    },
  );

  Widget _frostedAutoSaveToggle({required VoidCallback onPressed}) {
    final enabled = _autoSaveEnabled;
    const radius = BorderRadius.all(Radius.circular(99));
    return Semantics(
      button: true,
      toggled: enabled,
      label: 'Auto-save lokal',
      child: Tooltip(
        message: localizeAppText(
          enabled ? 'Nonaktifkan auto-save' : 'Aktifkan auto-save',
        ),
        child: _ButtonPop(
          intensity: 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: enabled
                      ? _blue.withValues(alpha: .22)
                      : const Color(0x1821425b),
                  blurRadius: 9,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPressed,
                borderRadius: radius,
                splashFactory: NoSplash.splashFactory,
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                child: SizedBox(
                  width: 50,
                  height: 30,
                  child: ClipRRect(
                    borderRadius: radius,
                    clipBehavior: Clip.antiAliasWithSaveLayer,
                    child: _windowAwareBlur(
                      sigmaX: 12,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: enabled
                                ? [
                                    _blue.withValues(alpha: .58),
                                    _blue.withValues(alpha: .38),
                                  ]
                                : [
                                    Colors.white.withValues(alpha: .7),
                                    const Color(0xffe6f0f8)
                                        .withValues(alpha: .54),
                                  ],
                          ),
                          border: Border.all(
                            color: enabled
                                ? _blue.withValues(alpha: .45)
                                : Colors.white.withValues(alpha: .88),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: AnimatedAlign(
                            alignment: enabled
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x2421425b),
                                    blurRadius: 5,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                clipBehavior: Clip.antiAliasWithSaveLayer,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.white.withValues(alpha: .98),
                                        Colors.white.withValues(alpha: .78),
                                      ],
                                    ),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: .94,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _frostedChoicePill({
    required String label,
    required bool selected,
    required VoidCallback onPressed,
    double fontSize = 11,
  }) {
    const radius = BorderRadius.all(Radius.circular(99));
    return _ButtonPop(
      intensity: .55,
      child: _PillFocusIndicator(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: selected
                    ? _blue.withValues(alpha: .13)
                    : const Color(0x1021425b),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: _windowAwareBlur(
              sigmaX: 10,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onPressed,
                  borderRadius: radius,
                  splashFactory: NoSplash.splashFactory,
                  overlayColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: selected
                            ? [
                                _blue.withValues(alpha: .2),
                                _blue.withValues(alpha: .11),
                              ]
                            : [
                                Colors.white.withValues(alpha: .7),
                                const Color(0xfff5faff).withValues(alpha: .58),
                              ],
                      ),
                      border: Border.all(
                        color: selected
                            ? _blue.withValues(alpha: .34)
                            : Colors.white.withValues(alpha: .86),
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (selected) ...[
                            Icon(Icons.check_rounded, color: _blue, size: 13),
                            const SizedBox(width: 4),
                          ],
                          AppText(
                            label,
                            style: TextStyle(
                              color: selected ? _blue : _ink,
                              fontSize: fontSize,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editOwners() async {
    final owners = _data.owners
        .map((owner) => Owner(id: owner.id, name: owner.name, pct: owner.pct))
        .toList();
    final nameControllers = owners
        .map((owner) => TextEditingController(text: owner.name))
        .toList();
    final pctControllers = owners
        .map(
          (owner) => TextEditingController(
            text: owner.pct.toString().replaceAll('.', ','),
          ),
        )
        .toList();
    String? error;
    try {
      final updatedOwners = await showDialog<List<Owner>>(
        context: context,
        barrierColor: const Color(0x180f202c),
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            var totalPct = 0.0;
            for (final controller in pctControllers) {
              totalPct +=
                  double.tryParse(
                    controller.text.trim().replaceAll(',', '.'),
                  ) ??
                  0;
            }
            final canSave = (totalPct - 100).abs() < .0001;
            String nextOwnerName() {
              final names = nameControllers
                  .map((controller) => controller.text.trim().toLowerCase())
                  .toSet();
              var number = 1;
              while (names.contains('pemilik $number')) {
                number++;
              }
              return 'Pemilik $number';
            }

            void submitOwners() {
              if (!canSave) {
                setDialogState(
                  () => error =
                      'Total pembagian harus tepat 100% untuk menyimpan.',
                );
                return;
              }
              final updated = <Owner>[];
              for (var index = 0; index < owners.length; index++) {
                final name = nameControllers[index].text.trim();
                final pct = double.tryParse(
                  pctControllers[index].text.trim().replaceAll(',', '.'),
                );
                if (name.isEmpty) {
                  setDialogState(
                    () =>
                        error = 'Nama pemilik ${index + 1} tidak boleh kosong.',
                  );
                  return;
                }
                if (pct == null || pct < 0 || pct > 100) {
                  setDialogState(
                    () => error =
                        'Persentase harus berupa angka antara 0 sampai 100.',
                  );
                  return;
                }
                updated.add(Owner(id: owners[index].id, name: name, pct: pct));
              }
              Navigator.pop(dialogContext, updated);
            }

            Widget ownerInput({
              required TextEditingController controller,
              required bool percentage,
              required VoidCallback onChanged,
            }) => SizedBox(
              height: 35,
              child: _liquidInputSurface(
                minHeight: 35,
                verticalPadding: 0,
                child: Transform.translate(
                  offset: const Offset(0, 5),
                  child: TextField(
                    controller: controller,
                    keyboardType: percentage
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.text,
                    textInputAction: percentage
                        ? TextInputAction.done
                        : TextInputAction.done,
                    textAlign: percentage ? TextAlign.center : TextAlign.start,
                    textAlignVertical: TextAlignVertical.center,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 13,
                      height: 1,
                    ),
                    decoration: InputDecoration(
                      filled: false,
                      isCollapsed: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: percentage
                          ? null
                          : localizeAppText('Nama pemilik'),
                      hintStyle: const TextStyle(
                        color: Color(0xff8da0ae),
                        fontSize: 13,
                      ),
                      suffixText: percentage ? '%' : null,
                      suffixStyle: const TextStyle(color: _muted, fontSize: 12),
                    ),
                    onChanged: (_) => onChanged(),
                    onSubmitted: (_) => submitOwners(),
                  ),
                ),
              ),
            );

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 480,
                  maxHeight: MediaQuery.sizeOf(context).height * .82,
                ),
                child: _FrostedSurface(
                  borderRadius: BorderRadius.circular(26),
                  tintColor: _popupTintColor,
                  tintOpacity: _popupTintOpacity,
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
                  blurSigma: 18,
                  prominentShadow: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: AppText(
                              'Ubah pemilik',
                              style: TextStyle(
                                color: _ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          _PopIconButton(
                            tooltip: localizeAppText('Tutup'),
                            onPressed: () => Navigator.pop(dialogContext),
                            style: IconButton.styleFrom(
                              foregroundColor: _muted,
                              backgroundColor: Colors.white.withValues(
                                alpha: .5,
                              ),
                              minimumSize: const Size(32, 32),
                              padding: EdgeInsets.zero,
                            ),
                            icon: const Icon(Icons.close, size: 17),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const AppText(
                        'Atur nama dan porsi pembagian untuk setiap pemilik.',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _ImportDialogPill(
                          icon: Icons.person_add_alt_1_outlined,
                          label: 'Tambah pemilik',
                          labelOffset: 0,
                          onPressed: () {
                            setDialogState(() {
                              final name = nextOwnerName();
                              owners.add(
                                Owner(id: makeId(), name: name, pct: 0),
                              );
                              nameControllers.add(
                                TextEditingController(text: name),
                              );
                              pctControllers.add(
                                TextEditingController(text: '0'),
                              );
                              error = null;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (owners.isNotEmpty)
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(8, 0, 0, 6),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: AppText(
                                          'Nama pemilik',
                                          style: TextStyle(
                                            color: _muted,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 10),
                                      Expanded(
                                        child: AppText(
                                          'Persentase',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: _muted,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 4),
                                      SizedBox(width: 35),
                                    ],
                                  ),
                                ),
                              for (
                                var index = 0;
                                index < owners.length;
                                index++
                              )
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: ownerInput(
                                          controller: nameControllers[index],
                                          percentage: false,
                                          onChanged: () {
                                            if (error != null) {
                                              setDialogState(
                                                () => error = null,
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: ownerInput(
                                          controller: pctControllers[index],
                                          percentage: true,
                                          onChanged: () {
                                            setDialogState(() => error = null);
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      SizedBox(
                                        width: 35,
                                        height: 35,
                                        child: Tooltip(
                                          message: localizeAppText(
                                            'Hapus pemilik ${index + 1}',
                                          ),
                                          child: _ButtonPop(
                                            intensity: 1.5,
                                            child: Material(
                                              color: Colors.transparent,
                                              shape: const CircleBorder(),
                                              child: InkWell(
                                                customBorder:
                                                    const CircleBorder(),
                                                onTap: () {
                                                  final nameController =
                                                      nameControllers[index];
                                                  final pctController =
                                                      pctControllers[index];
                                                  setDialogState(() {
                                                    owners.removeAt(index);
                                                    nameControllers.removeAt(
                                                      index,
                                                    );
                                                    pctControllers.removeAt(
                                                      index,
                                                    );
                                                    error = null;
                                                  });
                                                  nameController.dispose();
                                                  pctController.dispose();
                                                },
                                                child: _FrostedSurface(
                                                  borderRadius:
                                                      BorderRadius.circular(99),
                                                  tintColor: const Color(
                                                    0xffffe8e6,
                                                  ),
                                                  tintOpacity: .9,
                                                  padding: const EdgeInsets.all(
                                                    7,
                                                  ),
                                                  shadow: false,
                                                  blurSigma: 14,
                                                  child: const Center(
                                                    child: Icon(
                                                      Icons.close_rounded,
                                                      color: _red,
                                                      size: 17,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: AppText(
                          'Total pembagian ${formatNumber(totalPct, decimals: 2)}%'
                          '${canSave ? ' · sudah 100%' : ' · harus 100% untuk menyimpan'}',
                          style: TextStyle(
                            color: canSave ? _green : _orange,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 8),
                        AppText(
                          error!,
                          style: const TextStyle(color: _red, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _ImportDialogPill(
                            label: 'Batal',
                            labelOffset: 0,
                            onPressed: () => Navigator.pop(dialogContext),
                          ),
                          const SizedBox(width: 8),
                          _ImportDialogPill(
                            label: 'Simpan',
                            labelOffset: 0,
                            blue: true,
                            onPressed: canSave ? submitOwners : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
      if (updatedOwners == null || !mounted) return;
      setState(() => _data.owners = updatedOwners);
      if (await _save()) _message('Data pemilik berhasil diperbarui.');
    } finally {
      // Dialog masih beranimasi tutup; tunggu sebelum dispose controller.
      final controllers = [...nameControllers, ...pctControllers];
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        for (final controller in controllers) {
          controller.dispose();
        }
      });
    }
  }

  Future<void> _addSale([Sale? existing]) async {
    if (_data.products.isEmpty) {
      _message('Tambahkan produk dulu di menu Produk dan HPP.');
      return;
    }
    final initialPlatform =
        existing?.platform ?? (_marketFilter == 'all' ? null : _marketFilter);
    final result = await showGeneralDialog<Sale>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0x180f202c),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, animation, secondaryAnimation) => _SaleDialog(
        data: _data,
        initial: existing,
        initialPlatform: initialPlatform,
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          _normalDialogTransition(animation, child),
    );
    if (result == null) return;
    final oldMonth = _month;
    final index = _data.sales.indexWhere((sale) => sale.id == result.id);
    setState(() {
      if (index < 0) {
        _data.sales.add(result);
      } else {
        _data.sales[index] = result;
      }
      _month = result.date.substring(0, 7);
    });
    await _save();
    var message = existing == null
        ? 'Penjualan tersimpan.'
        : 'Penjualan diperbarui.';
    if (oldMonth != _month) {
      message += ' Periode ${monthLabel(_month)}.';
    }
    _message(message);
  }

  Future<void> _deleteSale(Sale sale) async {
    if (!await _confirm(
      'Hapus penjualan?',
      'Catatan penjualan ini akan dihapus.',
    )) {
      return;
    }
    setState(() => _data.sales.removeWhere((item) => item.id == sale.id));
    await _save();
  }

  Future<void> _addExpense(String category, [Expense? existing]) async {
    Future<bool> saveExpense(Expense result) async {
      final index = _data.expenses.indexWhere(
        (expense) => expense.id == result.id,
      );
      setState(() {
        if (index < 0) {
          _data.expenses.add(result);
        } else {
          _data.expenses[index] = result;
        }
        if (category == 'thr') _month = result.month;
      });
      return _save();
    }

    final result = await showGeneralDialog<Expense>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0x180f202c),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, animation, secondaryAnimation) => _ExpenseDialog(
        category: category,
        products: _data.products,
        ppnPct: _data.ppnPct,
        month: _month,
        isWindowMaximized: _windowIsMaximized,
        initial: existing,
        onSaveAndAdd: saveExpense,
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          _normalDialogTransition(animation, child),
    );
    if (result == null) return;
    if (!await saveExpense(result)) return;
    _message('Pengeluaran tersimpan.');
  }

  Future<void> _deleteExpense(Expense expense) async {
    if (!await _confirm('Hapus data?', 'Catatan ini akan dihapus.')) return;
    setState(() => _data.expenses.removeWhere((item) => item.id == expense.id));
    await _save();
  }

  Future<void> _addProduct([Product? existing]) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0x180f202c),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, animation, secondaryAnimation) =>
          _ProductDialog(initial: existing, onSave: _saveProduct),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          _normalDialogTransition(animation, child),
    );
  }

  Future<void> _saveProduct(Product product) async {
    final index = _data.products.indexWhere((item) => item.id == product.id);
    setState(() {
      if (index < 0) {
        _data.products.add(product);
      } else {
        _data.products[index] = product;
      }
      _selectedProductId = product.id;
    });
    await _save();
    _message('Produk tersimpan.');
  }

  Future<void> _deleteProduct(Product product) async {
    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0x180f202c),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (dialogContext, animation, secondaryAnimation) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _FrostedSurface(
              borderRadius: BorderRadius.circular(26),
              tintColor: _popupTintColor,
              tintOpacity: _popupTintOpacity,
              padding: const EdgeInsets.all(24),
              blurSigma: 18,
              prominentShadow: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _red.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          color: _red,
                          size: 21,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: AppText(
                          'Hapus produk?',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      _PopIconButton(
                        tooltip: localizeAppText('Tutup'),
                        onPressed: () => Navigator.pop(dialogContext, false),
                        style: IconButton.styleFrom(
                          foregroundColor: _muted,
                          backgroundColor: Colors.white.withValues(alpha: .44),
                          minimumSize: const Size(32, 32),
                          padding: EdgeInsets.zero,
                        ),
                        icon: const Icon(Icons.close, size: 17),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  AppText(
                    '“${product.name}” akan dihapus. Riwayat penjualan produk tetap tersimpan.',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 13,
                      height: 1.5,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _ImportDialogPill(
                        label: 'Batal',
                        labelOffset: 0,
                        onPressed: () => Navigator.pop(dialogContext, false),
                      ),
                      const SizedBox(width: 8),
                      _ImportDialogPill(
                        label: 'Hapus',
                        danger: true,
                        labelOffset: 0,
                        onPressed: () => Navigator.pop(dialogContext, true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          _normalDialogTransition(animation, child),
    );
    if (confirmed != true) {
      return;
    }
    setState(() {
      _data.products.removeWhere((item) => item.id == product.id);
      _productImageSources.remove(product.id);
      _productImageProviders.remove(product.id);
      _selectedProductId = _data.products.firstOrNull?.id;
    });
    await _saveApplicationImage('product:${product.id}', '', null);
    await _save();
  }

  Future<void> _removeProductImage(Product product) async {
    setState(() {
      product.img = '';
      _productImageSources.remove(product.id);
      _productImageProviders.remove(product.id);
    });
    await _saveApplicationImage('product:${product.id}', '', null);
    await _save(rebuild: false);
  }

  Future<void> _pickProductImage(Product product) async {
    try {
      final picked = await _withOutsideDismissedPicker(
        () => FilePicker.platform.pickFiles(
          dialogTitle: localizeAppText('Pilih gambar produk'),
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
          withData: true,
          lockParentWindow: true,
        ),
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw const FormatException('Isi berkas foto tidak terbaca.');
      }
      final mime = _imageMimeFromName(file.name);
      await LocalFileArchive.instance.saveApplicationImage(
        key: 'product:${product.id}',
        mime: mime,
        bytes: bytes,
      );
      setState(() => product.img = 'data:$mime;base64,${base64Encode(bytes)}');
      await _save(rebuild: false);
    } catch (error) {
      _message('Foto produk tidak bisa dibuka: $error', isError: true);
    }
  }

  Future<void> _addProductMaterial(
    Product product, [
    MaterialCost? existing,
  ]) async {
    final result = await showGeneralDialog<MaterialCost>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0x180f202c),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, animation, secondaryAnimation) =>
          _MaterialDialog(initial: existing, catalog: _data.materials),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          _normalDialogTransition(animation, child),
    );
    if (result == null) return;
    await _saveProductMaterial(product, result);
  }

  Future<void> _saveProductMaterial(
    Product product,
    MaterialCost result,
  ) async {
    final index = product.materials.indexWhere((item) => item.id == result.id);
    setState(() {
      if (index < 0) {
        product.materials.add(result);
      } else {
        product.materials[index] = result;
      }
    });
    await _save();
  }

  Future<void> _addCatalogMaterial({
    MaterialCost? existing,
    MaterialCategory category = MaterialCategory.bahanBaku,
  }) async {
    final result = await showGeneralDialog<MaterialCost>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0x180f202c),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, animation, secondaryAnimation) => _MaterialDialog(
        initial: existing,
        category: existing?.category ?? category,
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          _normalDialogTransition(animation, child),
    );
    if (result == null) return;
    final index = _data.materials.indexWhere((item) => item.id == result.id);
    setState(() {
      if (index < 0) {
        _data.materials.add(result);
      } else {
        _data.materials[index] = result;
      }
    });
    await _save();
  }

  Future<void> _deleteCatalogMaterial(MaterialCost material) async {
    if (!await _confirm(
      'Hapus bahan baku?',
      material.name,
      translateBody: false,
    )) {
      return;
    }
    setState(() {
      for (final product in _data.products) {
        for (final item in product.materials) {
          if (item.ref == material.id) {
            item
              ..name = material.name
              ..unit = material.unit
              ..price = material.price
              ..category = material.category
              ..ref = null;
          }
        }
      }
      _data.materials.removeWhere((item) => item.id == material.id);
    });
    await _save();
  }

  Future<void> _editStock(
    Product product, {
    bool editCurrentBalance = false,
  }) async {
    final result = await showGeneralDialog<_StockDialogResult>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0x180f202c),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (dialogContext, animation, secondaryAnimation) => Center(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _StockDialog(
              products: _data.products,
              initialProduct: product,
              editCurrentBalance: editCurrentBalance,
              initialBalances: editCurrentBalance
                  ? _data.stockByColor(product)
                  : const {},
              onSaveAndAdd: _saveStockEntry,
            ),
          ),
        ),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          _normalDialogTransition(animation, child),
    );
    if (result == null) return;
    await _saveStockEntry(result);
  }

  Future<void> _saveStockEntry(_StockDialogResult result) async {
    final selectedProduct = _data.products
        .where((item) => item.id == result.productId)
        .firstOrNull;
    if (selectedProduct == null) {
      _message('Produk stok tidak ditemukan.', isError: true);
      return;
    }
    setState(() {
      selectedProduct.stock = result.stock;
      _selectedProductId = selectedProduct.id;
      _productTab = 'produk';
    });
    await _save();
    _message('Stok tersimpan.');
  }

  void _changeMonth(int amount) => _setMonth(shiftMonth(_month, amount));

  Future<void> _selectMonth(Rect? anchorRect) async {
    final current = _month.split('-');
    final screenSize = MediaQuery.sizeOf(context);
    final pickerWidth = (screenSize.width - 32).clamp(0.0, 340.0);
    final pickerLeft = anchorRect == null
        ? (screenSize.width - pickerWidth) / 2
        : (anchorRect.center.dx - pickerWidth / 2).clamp(
            16.0,
            screenSize.width - pickerWidth - 16,
          );
    const estimatedPickerHeight = 390.0;
    final pickerTop = anchorRect == null
        ? MediaQuery.paddingOf(context).top + 72
        : (anchorRect.bottom + 8).clamp(
            12.0,
            (screenSize.height - estimatedPickerHeight - 12).clamp(
              12.0,
              double.infinity,
            ),
          );
    final result = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0x180f202c),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        var year = int.parse(current[0]);
        var selectedMonth = int.parse(current[1]);
        final pickerAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Stack(
              children: [
                Positioned(
                  left: pickerLeft,
                  top: pickerTop,
                  width: pickerWidth,
                  child: FadeTransition(
                    opacity: Tween<double>(
                      begin: .92,
                      end: 1,
                    ).animate(pickerAnimation),
                    child: ScaleTransition(
                      alignment: Alignment.topCenter,
                      scale: Tween<double>(
                        begin: .96,
                        end: 1,
                      ).animate(pickerAnimation),
                      child: RepaintBoundary(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: 340,
                            maxHeight: screenSize.height * .62,
                          ),
                          child: _FrostedSurface(
                            borderRadius: BorderRadius.circular(28),
                            tintColor: _popupTintColor,
                            tintOpacity: _popupTintOpacity,
                            padding: const EdgeInsets.all(16),
                            blurSigma: 10,
                            prominentShadow: true,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    const Expanded(
                                      child: AppText(
                                        'Pilih bulan',
                                        style: TextStyle(
                                          color: _ink,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                    ),
                                    _PopIconButton(
                                      tooltip: localizeAppText('Tutup'),
                                      onPressed: () =>
                                          Navigator.pop(dialogContext),
                                      style: IconButton.styleFrom(
                                        foregroundColor: _muted,
                                        backgroundColor: Colors.white
                                            .withValues(alpha: .44),
                                        minimumSize: const Size(32, 32),
                                        padding: EdgeInsets.zero,
                                      ),
                                      icon: const Icon(Icons.close, size: 17),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _FrostedSurface(
                                  borderRadius: BorderRadius.circular(99),
                                  tintColor: Colors.white,
                                  tintOpacity: .54,
                                  blurSigma: 12,
                                  shadow: false,
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      _AnimatedMonthArrow(
                                        icon: Icons.chevron_left,
                                        onPressed: () =>
                                            setDialogState(() => year--),
                                      ),
                                      AppText(
                                        '$year',
                                        style: const TextStyle(
                                          color: _ink,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                      _AnimatedMonthArrow(
                                        icon: Icons.chevron_right,
                                        onPressed: () =>
                                            setDialogState(() => year++),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 22),
                                _PocketRMonthGrid(
                                  year: year,
                                  selectedMonth: selectedMonth,
                                  columns: pickerWidth < 300 ? 2 : 3,
                                  onSelected: (month) => Navigator.pop(
                                    dialogContext,
                                    '$year-${month.toString().padLeft(2, '0')}',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (result != null) {
      _setMonth(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: _blue)),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 42),
                const SizedBox(height: 12),
                AppText(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 14),
                _PocketRActionButton(
                  icon: null,
                  blue: true,
                  label: 'Coba lagi',
                  onPressed: _load,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      extendBody: true,
      body: DecoratedBox(
        decoration: BoxDecoration(
          color: _isDesktop ? const Color(0xffc8e0e8) : null,
          gradient: _isDesktop
              ? null
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xffb8ddf4),
                    Color(0xff76c7d8),
                    Color(0xffa7d6df),
                  ],
                ),
        ),
        child: RepaintBoundary(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final calculatorWidth = 320.0;
              final calculatorHeight = 440.0;
              const desktopSidebarWidth = 230.0;
              final maxLeft = (constraints.maxWidth - calculatorWidth).clamp(
                0.0,
                constraints.maxWidth,
              );
              final maxTop = (constraints.maxHeight - calculatorHeight).clamp(
                0.0,
                constraints.maxHeight,
              );
              Offset calculatorLocalPosition(Offset globalPosition) {
                final renderObject = _calculatorLayerKey.currentContext
                    ?.findRenderObject();
                if (renderObject is! RenderBox) return globalPosition;
                return renderObject.globalToLocal(globalPosition);
              }

              return Stack(
                key: _calculatorLayerKey,
                children: [
                  const Positioned(
                    top: -110,
                    left: -80,
                    child: _Glow(color: Color(0x66e6f6ff), size: 360),
                  ),
                  const Positioned(
                    bottom: -170,
                    right: -100,
                    child: _Glow(color: Color(0x6678a8d6), size: 420),
                  ),
                  SafeArea(
                    child: _isDesktop
                        ? Row(
                            children: [
                              SizedBox(
                                width: desktopSidebarWidth,
                                child: Container(
                                  color: Colors.white.withValues(alpha: .1),
                                  child: _sidebar(),
                                ),
                              ),
                              Container(
                                width: 1,
                                color: _ink.withValues(alpha: .08),
                              ),
                              Expanded(
                                child: Container(
                                  color: Colors.white.withValues(alpha: .08),
                                  child: _page(),
                                ),
                              ),
                            ],
                          )
                        : _page(),
                  ),
                  if (_isDesktop)
                    Positioned(
                      top: 0,
                      left: desktopSidebarWidth + 1,
                      right: 0,
                      child: Center(child: _desktopDragZone()),
                    ),
                  if (!_isDesktop)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _bottomNavigation(),
                    ),
                  if (_calculatorMounted)
                    ValueListenableBuilder<Offset?>(
                      valueListenable: _calculatorPosition,
                      builder: (context, savedPosition, _) {
                        final calculatorPosition =
                            savedPosition ??
                            Offset(
                              260,
                              (constraints.maxHeight - calculatorHeight) / 2,
                            );
                        final visibleCalculatorPosition = Offset(
                          calculatorPosition.dx.clamp(0.0, maxLeft),
                          calculatorPosition.dy.clamp(0.0, maxTop),
                        );
                        return Positioned(
                          left: 0,
                          top: 0,
                          child: Transform.translate(
                            offset: Offset(
                              visibleCalculatorPosition.dx,
                              visibleCalculatorPosition.dy,
                            ),
                            child: IgnorePointer(
                              ignoring: !_calculatorOpen,
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(
                                  begin: 0,
                                  end: _calculatorOpen ? 1 : 0,
                                ),
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                builder: (context, progress, child) => Opacity(
                                  opacity: progress,
                                  child: Transform.scale(
                                    scale: .9 + (.1 * progress),
                                    alignment: Alignment.centerLeft,
                                    child: child,
                                  ),
                                ),
                                child: RepaintBoundary(
                                  child: _CalculatorWindow(
                                    onClose: _closeCalculator,
                                    onDragStart: (globalPosition) {
                                      _calculatorGrabOffset =
                                          calculatorLocalPosition(
                                            globalPosition,
                                          ) -
                                          visibleCalculatorPosition;
                                    },
                                    onDrag: (globalPosition) {
                                      final grabOffset =
                                          _calculatorGrabOffset ?? Offset.zero;
                                      final position =
                                          calculatorLocalPosition(
                                            globalPosition,
                                          ) -
                                          grabOffset;
                                      _calculatorPosition.value = Offset(
                                        position.dx.clamp(0.0, maxLeft),
                                        position.dy.clamp(0.0, maxTop),
                                      );
                                    },
                                    onDragEnd: () =>
                                        _calculatorGrabOffset = null,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _sidebar() => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 14, top: 8, bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _MacTrafficLights(
              onMinimize: _minimizeWindow,
              onToggleMaximize: _toggleMaximizeWindow,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _SidebarProfile(
          businessName: _data.businessName,
          image: _profileImage(_data.logo),
          subtitle: _data.tagline,
          onTap: _editSidebarProfile,
          onTapDown: (details) => _profileTapDetails = details,
        ),
        const SizedBox(height: 18),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: ValueListenableBuilder<int>(
              valueListenable: _navigationRefresh,
              builder: (context, _, _) => _NavMenu(
                items: _navigation,
                utilityItems: _sidebarUtilities,
                calculatorButtonKey: _calculatorButtonKey,
                selectedValue: _tab,
                onSelected: _navigate,
                onUtilitySelected: (action) {
                  if (action == 'open-file') _restore();
                  if (action == 'save-file') _backup();
                  if (action == 'export-excel') _exportExcel();
                  if (action == 'calculator') {
                    _openCalculator();
                  }
                  if (action == 'settings') _showSettings();
                  if (action == 'about') _showAbout();
                },
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _bottomNavigation() => SafeArea(
    top: false,
    child: Material(
      type: MaterialType.transparency,
      color: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: SizedBox(
          height: 64,
          child: ValueListenableBuilder<int>(
            valueListenable: _navigationRefresh,
            builder: (context, _, _) => LayoutBuilder(
              builder: (context, constraints) {
                final selectedIndex = _navigation.indexWhere(
                  (item) => item.$1 == _tab,
                );
                final itemWidth = constraints.maxWidth / _navigation.length;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1421425b),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: _windowAwareBlur(
                      sigmaX: 18,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(
                                alpha: Platform.isAndroid ? .82 : .3,
                              ),
                              const Color(
                                0xffd8edf4,
                              ).withValues(alpha: Platform.isAndroid ? .8 : .3),
                            ],
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .34),
                          ),
                        ),
                        child: Stack(
                          children: [
                            if (selectedIndex >= 0)
                              AnimatedPositioned(
                                duration: const Duration(milliseconds: 480),
                                curve: Curves.easeInOutCubicEmphasized,
                                left: selectedIndex * itemWidth + 3,
                                top: 4,
                                bottom: 4,
                                width: itemWidth - 6,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(99),
                                  child: _windowAwareBlur(
                                    sigmaX: 12,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(99),
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Colors.white.withValues(alpha: .8),
                                            const Color(0xfff5faff)
                                                .withValues(alpha: .72),
                                          ],
                                        ),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: .62,
                                          ),
                                        ),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Color(0x1821425b),
                                            blurRadius: 7,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Row(
                              children: [
                                for (final item in _navigation)
                                  Expanded(
                                    child: Material(
                                      color: Colors.transparent,
                                      child: _ButtonPop(
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            99,
                                          ),
                                          splashFactory: NoSplash.splashFactory,
                                          overlayColor:
                                              const WidgetStatePropertyAll(
                                                Colors.transparent,
                                              ),
                                          onTap: () => _navigate(item.$1),
                                          child: Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  item.$3,
                                                  size: 21,
                                                  color: _tab == item.$1
                                                      ? _blue
                                                      : _ink,
                                                ),
                                                const SizedBox(height: 10),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 3,
                                                      ),
                                                  child: FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: AppText(
                                                      item.$2,
                                                      maxLines: 1,
                                                      style: TextStyle(
                                                        color: _tab == item.$1
                                                            ? _blue
                                                            : _muted,
                                                        fontSize: 8.5,
                                                        fontWeight:
                                                            _tab == item.$1
                                                            ? FontWeight.w700
                                                            : FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );

  static const _navigation = <(String, String, IconData)>[
    ('ringkasan', 'Ringkasan', Icons.bar_chart_outlined),
    ('penjualan', 'Penjualan', Icons.shopping_bag_outlined),
    ('pengeluaran', 'Pengeluaran', Icons.account_balance_wallet_outlined),
    ('produk', 'Produk dan HPP', Icons.inventory_2_outlined),
  ];
  static const _sidebarUtilities = <(String, String, IconData)>[
    ('open-file', 'Buka berkas', Icons.folder_open_outlined),
    ('save-file', 'Simpan berkas', Icons.save_outlined),
    ('calculator', 'Kalkulator', Icons.calculate_outlined),
    ('export-excel', 'Ekspor Excel', Icons.table_view_outlined),
    ('settings', 'Pengaturan', Icons.settings_outlined),
    ('about', 'Tentang', Icons.info_outline),
  ];

  PageRouteBuilder<void> _pageRoute(String tab) => PageRouteBuilder<void>(
    settings: RouteSettings(name: tab),
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) =>
        _pageRouteSurface(_pageContent(tab)),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        child,
  );

  Widget _pageRouteSurface(Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      color: _isDesktop ? const Color(0xffcbe2e9) : null,
      gradient: _isDesktop
          ? null
          : const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xffb8ddf4), Color(0xff76c7d8), Color(0xffa7d6df)],
            ),
    ),
    child: child,
  );

  Widget _page() => Stack(
    children: [
      Positioned.fill(
        child: Navigator(
          key: _pageNavigatorKey,
          initialRoute: _tab,
          onGenerateInitialRoutes: (navigator, initialRoute) => [
            _pageRoute(initialRoute),
          ],
          onGenerateRoute: (settings) =>
              _pageRoute(settings.name ?? 'ringkasan'),
        ),
      ),
      if (_isDesktop)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ValueListenableBuilder<int>(
            valueListenable: _navigationRefresh,
            builder: (context, _, _) => _desktopPageHeader(_tab),
          ),
        ),
    ],
  );

  Widget _pageContent(String tab) {
    final content = switch (tab) {
      'penjualan' => _salesPage(),
      'pengeluaran' => _expensesPage(),
      'produk' => _productsPage(),
      _ => _dashboardPage(),
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final bottomPadding = tab == 'penjualan'
            ? (_isDesktop ? 80.0 : (constraints.maxWidth < 440 ? 200.0 : 152.0))
            : (_isDesktop ? 36.0 : 112.0);
        final scrollContent = SingleChildScrollView(
          controller: tab == 'penjualan' ? _salesScrollController : null,
          padding: EdgeInsets.fromLTRB(
            _isDesktop ? 32 : 16,
            _isDesktop ? 106 : 14,
            _isDesktop ? 32 : 16,
            bottomPadding,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - (_isDesktop ? 150 : 70))
                  .clamp(0.0, double.infinity),
            ),
            child: content,
          ),
        );
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: scrollContent,
        );
      },
    );
  }

  Widget _desktopDragZone() {
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) async {
          await WindowManager.instance.startDragging();
        },
        child: SizedBox(
          width: double.infinity,
          height: 39,
          child: Center(
            child: Transform.translate(
              offset: const Offset(-124.5, -7),
              child: Container(
                width: 315,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .75),
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: [
                    BoxShadow(
                      color: _ink.withValues(alpha: .14),
                      blurRadius: 5,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _desktopPageHeader(String tab) {
    final title = switch (tab) {
      'penjualan' => 'Penjualan',
      'pengeluaran' => 'Pengeluaran',
      'produk' => 'Produk dan HPP',
      _ => 'Ringkasan Bulanan',
    };
    final actions = <Widget>[
      if (tab == 'ringkasan' || tab == 'penjualan' || tab == 'pengeluaran') ...[
        if (_hasLowStock) _lowStockWarning(animate: false),
      ],
      if (tab != 'produk') _monthSelector(),
      if (tab == 'penjualan') ...[
        _PocketRActionButton(
          icon: Icons.file_upload_outlined,
          label: 'Impor Penjualan',
          labelOffset: -1,
          onPressed: _showSalesImportDialog,
          blue: true,
        ),
      ],
    ];
    final pageTitle = Expanded(
      child: Transform.translate(
        offset: const Offset(0, 5),
        child: Padding(
          padding: const EdgeInsets.only(left: 3, top: 3),
          child: AppText(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _ink,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -.6,
            ),
          ),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRect(
          child: Stack(
            fit: StackFit.loose,
            children: [
              Positioned.fill(
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xd9e1f0f5),
                        Color(0xb3e1f0f5),
                        Color(0x8ce1f0f5),
                        Color(0x59e1f0f5),
                        Color(0x26e1f0f5),
                        Color(0x00e1f0f5),
                      ],
                      stops: [0, .28, .56, .82, .94, 1],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 32, 36),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final controls = Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: actions,
                    );
                    final alignedControls = Transform.translate(
                      offset: const Offset(0, 8),
                      child: controls,
                    );
                    if (constraints.maxWidth < 620) {
                      return Row(
                        children: [
                          pageTitle,
                          const SizedBox(width: 8),
                          alignedControls,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        pageTitle,
                        const SizedBox(width: 16),
                        alignedControls,
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pageTitle(String title, TextStyle style, {bool pill = true}) {
    if (!pill) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: .72),
              const Color(0xffdcecf6).withValues(alpha: .62),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: .65)),
          boxShadow: [
            BoxShadow(
              color: _ink.withValues(alpha: .08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: AppText(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: style.copyWith(fontSize: 23),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: Hero(
        tag: 'pocketr-main-page-title-pill',
        child: Material(
          color: Colors.transparent,
          child: _FrostedSurface(
            borderRadius: BorderRadius.circular(99),
            tintOpacity: .42,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            shadow: false,
            blurSigma: 16,
            child: AppText(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ),
      ),
    );
  }

  Widget _pageHeading(
    String title, {
    Widget? action,
    bool monthStepper = false,
    bool showLowStockWarning = false,
    bool plainTitle = false,
  }) => _isDesktop
      ? const SizedBox.shrink()
      : LayoutBuilder(
          builder: (context, constraints) {
            final heading = _pageTitle(
              title,
              TextStyle(
                color: _ink,
                fontSize: _isDesktop ? 28 : 25,
                fontWeight: FontWeight.w700,
                letterSpacing: -.6,
              ),
              pill: !plainTitle,
            );
            final controls = Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (showLowStockWarning && _hasLowStock)
                  _lowStockWarning(animate: false),
                if (monthStepper) _monthSelector(),
                ?action,
              ],
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: constraints.maxWidth < 560
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        heading,
                        const SizedBox(height: 10),
                        SizedBox(width: double.infinity, child: controls),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: heading),
                        const SizedBox(width: 14),
                        controls,
                      ],
                    ),
            );
          },
        );

  Widget _monthSelector() {
    return _ButtonPop(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1421425b),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: _windowAwareBlur(
            sigmaX: 18,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: .62),
                    const Color(0xfff5faff).withValues(alpha: .58),
                  ],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: .5)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AnimatedMonthArrow(
                      icon: Icons.chevron_left,
                      onPressed: () => _changeMonth(-1),
                      pop: false,
                    ),
                    Builder(
                      builder: (buttonContext) => Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(99),
                          splashFactory: NoSplash.splashFactory,
                          overlayColor: const WidgetStatePropertyAll(
                            Colors.transparent,
                          ),
                          onTap: () {
                            final renderObject = buttonContext
                                .findRenderObject();
                            final anchorRect = renderObject is RenderBox
                                ? renderObject.localToGlobal(Offset.zero) &
                                      renderObject.size
                                : null;
                            _selectMonth(anchorRect);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            child: AppText(
                              monthLabel(_month),
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    _AnimatedMonthArrow(
                      icon: Icons.chevron_right,
                      onPressed: () => _changeMonth(1),
                      pop: false,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dashboardPage() {
    final summary = _data.summary(_month);
    final sales = _data.sales.where((sale) => sale.date.startsWith(_month));
    final previous = _data.summary(shiftMonth(_month, -1));
    final growth = previous.revenue == 0
        ? null
        : (summary.revenue - previous.revenue) / previous.revenue * 100;
    final byPlatform = {
      for (final key in marketplaceNames.keys)
        key: sales
            .where((sale) => sale.platform == key)
            .fold<double>(0, (total, sale) => total + sale.received),
    };
    final breakdownCard = _glassCard(
      title: 'Perhitungan laba',
      icon: Icons.receipt_long_outlined,
      child: _breakdown(summary),
    );
    final annualCard = _annualSummary();
    final dailyCard = _glassCard(
      title: 'Omzet harian',
      icon: Icons.show_chart_rounded,
      child: SizedBox(
        height: 200,
        child: _DailyChart(sales: sales.toList(), month: _month),
      ),
    );
    final marketplaceCard = _glassCard(
      title: 'Platform penjualan',
      icon: Icons.storefront_outlined,
      child: Column(
        children: [
          for (final entry in byPlatform.entries)
            _progressLine(
              marketplaceNames[entry.key]!,
              entry.value,
              summary.revenue,
              _marketColor(entry.key),
            ),
        ],
      ),
    );
    final productSalesCard = _glassCard(
      title: 'Produk terjual',
      icon: Icons.inventory_2_outlined,
      child: _productSalesSummary(sales.toList(), summary),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageHeading(
          'Ringkasan Bulanan',
          monthStepper: true,
          showLowStockWarning: true,
          plainTitle: Platform.isAndroid,
        ),
        _kpiGrid([
          _Kpi(
            'Omzet (uang diterima)',
            formatMoney(summary.revenue),
            '${summary.orders} pesanan · ${formatNumber(summary.pcs)} pcs${growth == null ? '' : ' · ${growth >= 0 ? '▲' : '▼'} ${growth.abs().toStringAsFixed(0)}% vs bulan lalu'}',
            Icons.payments_outlined,
            _blue,
          ),
          _Kpi(
            'Laba bersih',
            formatMoney(summary.net),
            'Margin ${formatNumber(_percent(summary.net, summary.revenue), decimals: 1)}%',
            Icons.trending_up,
            summary.net < 0 ? _red : _green,
          ),
          _Kpi(
            'Total HPP',
            formatMoney(summary.hpp),
            '${formatNumber(_percent(summary.hpp, summary.revenue), decimals: 1)}% dari omzet',
            Icons.sell_outlined,
            _orange,
          ),
          _Kpi(
            'Total pengeluaran',
            formatMoney(summary.costs),
            'Operasional, iklan, gaji, THR, zakat',
            Icons.account_balance_wallet_outlined,
            _red,
          ),
        ]),
        if (_data.targetRevenue > 0) ...[
          const SizedBox(height: 14),
          _targetCard(summary),
        ],
        const SizedBox(height: 14),
        _ownerCard(summary),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 720) {
              return Column(
                children: [
                  breakdownCard,
                  const SizedBox(height: 12),
                  dailyCard,
                  const SizedBox(height: 12),
                  annualCard,
                  const SizedBox(height: 12),
                  marketplaceCard,
                  const SizedBox(height: 12),
                  productSalesCard,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      breakdownCard,
                      const SizedBox(height: 14),
                      dailyCard,
                      const SizedBox(height: 14),
                      marketplaceCard,
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    children: [
                      annualCard,
                      const SizedBox(height: 14),
                      productSalesCard,
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _targetCard(MonthSummary summary) {
    final progress = summary.revenue <= 0
        ? 0.0
        : (summary.revenue / _data.targetRevenue).clamp(0.0, 1.0);
    return _glassCard(
      title: 'Target omzet ${monthLabel(_month)}',
      icon: Icons.flag_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AppText(formatMoney(summary.revenue)),
              AppText('dari ${formatMoney(_data.targetRevenue)}'),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: progress,
              color: progress >= 1 ? _green : _blue,
              backgroundColor: Colors.white.withValues(alpha: .58),
            ),
          ),
          const SizedBox(height: 6),
          AppText('${(progress * 100).toStringAsFixed(0)}% tercapai'),
        ],
      ),
    );
  }

  Widget _ownerCard(MonthSummary summary) {
    final totalPct = _data.owners.fold<double>(
      0,
      (sum, owner) => sum + owner.pct,
    );
    return _glassCard(
      title: 'Pembagian laba pemilik',
      icon: Icons.groups_2_outlined,
      trailing: _PocketRActionButton(
        icon: Icons.edit_outlined,
        label: 'Ubah pemilik',
        labelOffset: -1,
        onPressed: _editOwners,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 800
              ? 4
              : constraints.maxWidth >= 480
              ? 2
              : 1;
          const spacing = 10.0;
          final width =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Column(
            children: [
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (var index = 0; index < _data.owners.length; index++)
                    SizedBox(
                      width: width,
                      child: _ownerShareTile(index, summary),
                    ),
                ],
              ),
              if (totalPct != 100)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: AppText(
                      'Total persentase ${formatNumber(totalPct, decimals: 1)}% (idealnya 100%).',
                      style: const TextStyle(color: _red, fontSize: 12),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _ownerShareTile(int index, MonthSummary summary) {
    final owner = _data.owners[index];
    final key = '$_month:${owner.id}';
    final isPaid = _data.paid[key] ?? false;
    final statusColor = isPaid ? _green : _red;
    Widget ownerText({
      required bool initial,
      required TextStyle style,
      String suffix = '',
      int? maxLines,
      TextOverflow? overflow,
    }) => ValueListenableBuilder<String>(
      valueListenable: appLanguageCode,
      builder: (context, languageCode, _) {
        final name = localizeOwnerName(owner.name, languageCode: languageCode);
        return Text(
          initial
              ? (name.isEmpty ? '?' : name.characters.first.toUpperCase())
              : '$name$suffix',
          style: style,
          maxLines: maxLines,
          overflow: overflow,
        );
      },
    );

    return _FrostedSurface(
      borderRadius: BorderRadius.circular(99),
      tintColor: const Color(0xffe7f7fd),
      tintOpacity: .64,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      shadow: false,
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: Colors.white.withValues(alpha: .46),
            child: ownerText(
              initial: true,
              style: const TextStyle(
                color: Color(0xff354f60),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ownerText(
                  initial: false,
                  style: const TextStyle(color: _muted, fontSize: 12),
                  suffix: ' · ${formatNumber(owner.pct.round())}%',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: AppText(
                    formatMoney(summary.net * owner.pct / 100),
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Material(
            color: statusColor,
            borderRadius: BorderRadius.circular(99),
            child: _ButtonPop(
              child: InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: () async {
                  setState(() => _data.paid[key] = !isPaid);
                  await _save();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppText(
                        isPaid ? 'Lunas' : 'Belum',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _breakdown(MonthSummary summary) {
    final rows = <(String, double, bool, int, bool, bool)>[
      ('Uang diterima (omzet)', summary.revenue, true, 0, false, false),
      ('HPP produk terjual', -summary.hpp, true, 0, false, false),
      (
        'Biaya iklan (+PPN)',
        -(summary.ads + summary.ppn),
        true,
        0,
        false,
        false,
      ),
      ('Iklan', -summary.ads, false, 14, false, false),
      (
        'PPN iklan ${formatNumber(_data.ppnPct, decimals: 1)}%',
        -summary.ppn,
        false,
        14,
        false,
        false,
      ),
      (
        'Biaya operasional',
        -(summary.operations + summary.salary + summary.thr),
        true,
        0,
        false,
        true,
      ),
      ('Operasional lain', -summary.operations, false, 14, false, false),
      ('Gaji pegawai', -summary.salary, false, 14, false, false),
      ('Persiapan THR Lebaran', -summary.thr, false, 14, false, false),
      ('Laba', summary.preTax, true, 0, false, false),
      (
        'Zakat ${formatNumber(_data.zakatPct, decimals: 1)}%',
        -summary.zakat,
        true,
        0,
        false,
        true,
      ),
      ('Laba bersih', summary.net, true, 0, true, false),
    ];
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _breakdownRow(rows[i], summary),
          ),
          if (i < rows.length - 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 1),
              child: _DashedDivider(),
            ),
        ],
      ],
    );
  }

  Future<void> _saveZakatPct() async {
    final rate = await showGeneralDialog<double>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0x180f202c),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: _ZakatPctDialog(initialValue: _data.zakatPct),
        ),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          _normalDialogTransition(animation, child),
    );
    if (rate == null || !mounted) return;
    setState(() => _data.zakatPct = rate);
    await _save();
  }

  Widget _breakdownRow(
    (String, double, bool, int, bool, bool) row,
    MonthSummary summary,
  ) {
    final (label, value, isBold, indent, isNet, isQualifierLabel) = row;
    final valueColor = isNet
        ? (summary.net < 0 ? _red : _green)
        : value < 0
        ? _muted
        : _ink;
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Padding(
            padding: EdgeInsets.only(left: indent.toDouble()),
            child: label.startsWith('Zakat ')
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppText(
                        label,
                        style: TextStyle(
                          fontWeight: isBold
                              ? FontWeight.w700
                              : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(width: 4),
                      _ButtonPop(
                        child: Material(
                          color: Colors.transparent,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _saveZakatPct,
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.edit_outlined,
                                size: 15,
                                color: _blue,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : isQualifierLabel && label == 'Biaya operasional'
                ? AppText.rich(
                    TextSpan(
                      style: TextStyle(
                        color: _ink,
                        fontWeight: isBold
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                      children: [
                        TextSpan(text: '$label '),
                        TextSpan(
                          text: '(termasuk gaji & THR)',
                          style: TextStyle(
                            color: _muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                : AppText(
                    label,
                    style: TextStyle(
                      fontWeight: isBold ? FontWeight.w700 : FontWeight.normal,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: AppText(
                '${value < 0 ? '− ' : ''}${formatMoney(value.abs())}',
                maxLines: 1,
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: valueColor,
                  fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _productSalesSummary(List<Sale> sales, MonthSummary summary) {
    String normalizedProductName(String value) =>
        value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final productsByName = {
      for (final product in _data.products)
        normalizedProductName(product.name): product,
    };
    final totals = aggregateProductSales(
      sales,
      hppForSale: (sale) {
        final name = normalizedProductName(sale.productName);
        final productByName = productsByName[name];
        final productById = _data.productById(sale.productId);
        final product =
            productByName != null &&
                (productById == null ||
                    normalizedProductName(productById.name) != name)
            ? productByName
            : productById ?? productByName;
        return product == null ? sale.hpp : _data.productHpp(product);
      },
    );
    if (totals.isEmpty) {
      return const _EmptyState(
        title: 'Belum ada penjualan',
        detail: 'Catat penjualan di menu Penjualan.',
      );
    }
    final rows = totals.values.toList()
      ..sort((a, b) {
        final comparison = switch (_productSalesSortColumn) {
          'qty' => a.$2.compareTo(b.$2),
          'revenue' => a.$3.compareTo(b.$3),
          'hpp' => a.$4.compareTo(b.$4),
          'gross' => (a.$3 - a.$4).compareTo(b.$3 - b.$4),
          _ => a.$1.toLowerCase().compareTo(b.$1.toLowerCase()),
        };
        return _productSalesSortAscending ? comparison : -comparison;
      });
    final hppTotal = rows.fold<double>(0, (sum, row) => sum + row.$4);
    const columns = [
      ('product', 'Produk', 3),
      ('qty', 'Qty', 2),
      ('revenue', 'Omzet', 3),
      ('hpp', 'HPP', 3),
      ('gross', 'Laba kotor', 3),
    ];
    Widget columnHeader(
      String key,
      String label,
      int flex, {
      bool first = false,
    }) {
      final isSorted = _productSalesSortColumn == key;
      return Expanded(
        flex: flex,
        child: InkWell(
          onTap: () => setState(() {
            if (isSorted) {
              _productSalesSortAscending = !_productSalesSortAscending;
            } else {
              _productSalesSortColumn = key;
              _productSalesSortAscending = true;
            }
          }),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: EdgeInsets.only(left: first ? 0 : 6, right: 3),
            child: Row(
              mainAxisAlignment: first
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.end,
              children: [
                Flexible(
                  child: AppText(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  isSorted
                      ? _productSalesSortAscending
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded
                      : Icons.unfold_more_rounded,
                  size: 14,
                  color: const Color(0xff7893a3),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget valueCell(
      String value,
      int flex, {
      bool first = false,
      bool centered = false,
      Color? color,
      FontWeight fontWeight = FontWeight.normal,
    }) => Expanded(
      flex: flex,
      child: Padding(
        padding: EdgeInsets.only(left: first ? 0 : 6, right: 3),
        child: Align(
          alignment: first
              ? Alignment.centerLeft
              : centered
              ? Alignment.center
              : Alignment.centerRight,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: first
                ? Alignment.centerLeft
                : centered
                ? Alignment.center
                : Alignment.centerRight,
            child: AppText(
              value,
              maxLines: 1,
              style: TextStyle(color: color ?? _ink, fontWeight: fontWeight),
            ),
          ),
        ),
      ),
    );

    Widget productRow((String, double, double, double) row) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: _ink.withValues(alpha: .1), width: .7),
        ),
      ),
      child: Row(
        children: [
          valueCell(row.$1, columns[0].$3, first: true),
          valueCell(formatNumber(row.$2), columns[1].$3, centered: true),
          valueCell(formatMoney(row.$3), columns[2].$3),
          valueCell(formatMoney(row.$4), columns[3].$3, color: _muted),
          valueCell(
            formatMoney(row.$3 - row.$4),
            columns[4].$3,
            fontWeight: FontWeight.w700,
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 700.0;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xffe4f2f9).withValues(alpha: .72),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      for (final column in columns)
                        columnHeader(
                          column.$1,
                          column.$2,
                          column.$3,
                          first: column == columns.first,
                        ),
                    ],
                  ),
                ),
                if (rows.length <= 10)
                  for (final row in rows) productRow(row)
                else
                  SizedBox(
                    height: 400,
                    child: ListView.builder(
                      primary: false,
                      itemCount: rows.length,
                      itemExtent: 40,
                      itemBuilder: (context, index) => productRow(rows[index]),
                    ),
                  ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xffa8cfe2).withValues(alpha: .52),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      valueCell(
                        'Total',
                        columns[0].$3,
                        first: true,
                        fontWeight: FontWeight.w700,
                      ),
                      valueCell(
                        formatNumber(summary.pcs),
                        columns[1].$3,
                        centered: true,
                        fontWeight: FontWeight.w700,
                      ),
                      valueCell(
                        formatMoney(summary.revenue),
                        columns[2].$3,
                        fontWeight: FontWeight.w700,
                      ),
                      valueCell(
                        formatMoney(hppTotal),
                        columns[3].$3,
                        fontWeight: FontWeight.w700,
                      ),
                      valueCell(
                        formatMoney(summary.revenue - hppTotal),
                        columns[4].$3,
                        fontWeight: FontWeight.w700,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _annualSummary() {
    final year = int.parse(_month.substring(0, 4));
    final rows = List.generate(12, (index) {
      final ym = '$year-${(index + 1).toString().padLeft(2, '0')}';
      return (monthLabel(ym).split(' ').first, _data.summary(ym));
    });
    final totalRevenue = rows.fold<double>(
      0,
      (total, row) => total + row.$2.revenue,
    );
    final totalCosts = rows.fold<double>(
      0,
      (total, row) => total + row.$2.costs,
    );
    final totalNet = rows.fold<double>(0, (total, row) => total + row.$2.net);
    return _glassCard(
      title: 'Laba tahunan · $year',
      icon: Icons.calendar_month_outlined,
      child: Column(
        children: [
          Container(
            key: const ValueKey('annual-summary-header'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xffe4f2f9).withValues(alpha: .72),
              borderRadius: BorderRadius.circular(14),
            ),
            child: _annualSummaryRow(const [
              'Bulan',
              'Omzet',
              'Pengeluaran',
              'Laba bersih',
            ], isHeader: true),
          ),
          for (var i = 0; i < rows.length; i++) ...[
            _annualSummaryRow([
              rows[i].$1,
              formatMoney(rows[i].$2.revenue),
              formatMoney(rows[i].$2.costs),
              formatMoney(rows[i].$2.net),
            ], isNetNegative: rows[i].$2.net < 0),
            if (i < rows.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: _ink.withValues(alpha: .1),
                ),
              ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Divider(
              height: 1,
              thickness: 1,
              color: _ink.withValues(alpha: .1),
            ),
          ),
          Container(
            key: const ValueKey('annual-total-row'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xffa8cfe2).withValues(alpha: .52),
              borderRadius: BorderRadius.circular(14),
            ),
            child: _annualSummaryRow(
              [
                'Total',
                formatMoney(totalRevenue),
                formatMoney(totalCosts),
                formatMoney(totalNet),
              ],
              isTotal: true,
              isNetNegative: totalNet < 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _annualSummaryRow(
    List<String> values, {
    bool isHeader = false,
    bool isTotal = false,
    bool isNetNegative = false,
  }) {
    const flexes = [12, 10, 14, 12];
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isHeader || isTotal ? 0 : 6),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isTotal ? 0 : 12),
        child: Row(
          children: [
            for (var i = 0; i < values.length; i++)
              Expanded(
                flex: flexes[i],
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 6, right: 3),
                  child: Align(
                    alignment: i == 0
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: i == 0
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: AppText(
                        values[i],
                        style: TextStyle(
                          color: isHeader
                              ? _muted
                              : i == values.length - 1
                              ? (isNetNegative ? _red : _ink)
                              : _ink,
                          fontSize: isHeader ? 11 : 13,
                          fontWeight: isHeader
                              ? FontWeight.w600
                              : isTotal
                              ? FontWeight.w700
                              : i == values.length - 1
                              ? FontWeight.w700
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _salesPage() {
    final indexedSales =
        _data.sales.asMap().entries.where((entry) {
          final sale = entry.value;
          return sale.date.startsWith(_month) &&
              (_marketFilter == 'all' || sale.platform == _marketFilter) &&
              (_search.isEmpty ||
                  '${sale.productName} ${sale.variant} ${sale.orderNo}'
                      .toLowerCase()
                      .contains(_search.toLowerCase()));
        }).toList()..sort((first, second) {
          final dateOrder = second.value.date.compareTo(first.value.date);
          return dateOrder != 0 ? dateOrder : second.key.compareTo(first.key);
        });
    final sales = indexedSales
        .map((entry) => entry.value)
        .toList(growable: false);
    final monthSales = _data.sales.where(
      (sale) =>
          sale.date.startsWith(_month) &&
          (_marketFilter == 'all' || sale.platform == _marketFilter),
    );
    final revenue = monthSales.fold<double>(
      0,
      (sum, sale) => sum + sale.received,
    );
    final orders = monthSales
        .map((sale) => sale.orderNo.isEmpty ? sale.id : sale.orderNo)
        .toSet()
        .length;
    final pcs = monthSales.fold<double>(0, (sum, sale) => sum + sale.qty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeading(
          'Penjualan',
          monthStepper: true,
          showLowStockWarning: true,
          action: Wrap(
            spacing: 8,
            children: [
              _PocketRActionButton(
                icon: Icons.file_upload_outlined,
                label: 'Impor Penjualan',
                labelOffset: -1,
                onPressed: _showSalesImportDialog,
                blue: true,
              ),
            ],
          ),
        ),
        _kpiGrid([
          _Kpi(
            'Uang diterima',
            formatMoney(revenue),
            'bulan ini',
            Icons.payments_outlined,
            _green,
          ),
          _Kpi(
            'Pesanan',
            formatNumber(orders),
            'pesanan tercatat',
            Icons.receipt_long_outlined,
            _blue,
          ),
          _Kpi(
            'Produk terjual',
            formatNumber(pcs),
            'kuantitas bulan ini',
            Icons.shopping_bag_outlined,
            _orange,
          ),
        ]),
        const SizedBox(height: 14),
        _marketplaceSalesCards(),
        const SizedBox(height: 14),
        _glassCard(
          title: 'Daftar penjualan · ${monthLabel(_month)}',
          icon: Icons.list_alt,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final tabs = _LiquidGlassTabBar(
                    tabs: <(String, String)>[
                      ('all', 'Semua'),
                      ...marketplaceNames.entries.map(
                        (item) => (item.key, item.value),
                      ),
                    ],
                    selectedValue: _marketFilter,
                    onSelected: (value) =>
                        setState(() => _marketFilter = value),
                  );
                  Widget searchField(double width) => SizedBox(
                    width: width,
                    height: 40,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1421425b),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: _windowAwareBlur(
                          sigmaX: 18,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(99),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white.withValues(alpha: .72),
                                  const Color(0xffe6f4fb)
                                      .withValues(alpha: .68),
                                ],
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .48),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 5,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withValues(
                                        alpha: .58,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.search_rounded,
                                      color: _muted,
                                      size: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: SizedBox(
                                      height: 30,
                                      child: Transform.translate(
                                        offset: const Offset(0, 5),
                                        child: TextField(
                                          controller: _searchController,
                                          onChanged: (value) {
                                            setState(() => _search = value);
                                            if (_salesScrollController
                                                .hasClients) {
                                              _salesScrollController.jumpTo(0);
                                            }
                                          },
                                          textAlignVertical:
                                              TextAlignVertical.center,
                                          strutStyle: const StrutStyle(
                                            fontSize: 12,
                                            height: 1,
                                            forceStrutHeight: true,
                                          ),
                                          style: const TextStyle(
                                            color: _ink,
                                            fontSize: 12,
                                            height: 1,
                                          ),
                                          decoration: InputDecoration(
                                            filled: false,
                                            isCollapsed: true,
                                            hintText: localizeAppText(
                                              'Cari produk / pesanan',
                                            ),
                                            hintStyle: TextStyle(
                                              color: _muted,
                                              fontSize: 12,
                                              height: 1,
                                            ),
                                            border: InputBorder.none,
                                            enabledBorder: InputBorder.none,
                                            focusedBorder: InputBorder.none,
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: _search.isEmpty
                                        ? null
                                        : _PopIconButton(
                                            onPressed: () {
                                              _searchController.clear();
                                              setState(() => _search = '');
                                            },
                                            tooltip: localizeAppText(
                                              'Hapus pencarian',
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                            constraints:
                                                const BoxConstraints.tightFor(
                                                  width: 28,
                                                  height: 28,
                                                ),
                                            padding: EdgeInsets.zero,
                                            icon: const Icon(
                                              Icons.close_rounded,
                                              size: 15,
                                              color: _muted,
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );

                  final addSaleButton = _PocketRActionButton(
                    icon: Icons.add,
                    label: 'Tambah penjualan',
                    labelOffset: -1,
                    onPressed: () => _addSale(),
                    blue: true,
                    fixedWidth: 190,
                  );
                  if (constraints.maxWidth >= 1020) {
                    return Row(
                      children: [
                        Expanded(child: tabs),
                        const SizedBox(width: 12),
                        searchField(190),
                        const SizedBox(width: 8),
                        addSaleButton,
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      tabs,
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          searchField(
                            constraints.maxWidth < 190
                                ? constraints.maxWidth
                                : 190,
                          ),
                          addSaleButton,
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              _SalesTable(
                sales: sales,
                emptyState: _search.isEmpty
                    ? const _EmptyState(
                        title: 'Belum ada penjualan',
                        detail: 'Tambah penjualan untuk mencatat pesanan di bulan ini.',
                      )
                    : const _EmptyState(
                        title: 'Tidak ada hasil pencarian',
                        detail: 'Coba kata kunci pencarian yang lain.',
                      ),
                hasBottomNavigation: !_isDesktop,
                total: sales.fold<double>(
                  0,
                  (sum, sale) => sum + sale.received,
                ),
                onEdit: (sale) => _addSale(sale),
                onDelete: _deleteSale,
                onCopyOrder: _copyOrderNumber,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _marketplaceSalesCards() {
    final monthSales = _data.sales
        .where((sale) => sale.date.startsWith(_month))
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 1100
            ? 5
            : constraints.maxWidth > 700
            ? 3
            : 2;
        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final entry in marketplaceNames.entries)
              Builder(
                builder: (context) {
                  final sales = monthSales.where(
                    (sale) => sale.platform.toLowerCase() == entry.key,
                  );
                  final revenue = sales.fold<double>(
                    0,
                    (total, sale) => total + sale.received,
                  );
                  final pcs = sales.fold<double>(
                    0,
                    (total, sale) => total + sale.qty,
                  );
                  return SizedBox(
                    width: width,
                    child: _glassCard(
                      title: entry.value,
                      titleLeading: _marketplaceCardBadge(entry.key),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AppText(
                            'Total omzet',
                            style: TextStyle(color: _muted, fontSize: 12),
                          ),
                          const SizedBox(height: 3),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: AppText(
                              formatMoney(revenue),
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          AppText(
                            '${formatNumber(pcs)} pcs terjual',
                            style: const TextStyle(color: _muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Widget _marketplaceCardBadge(String platform) {
    final (icon, color) = switch (platform) {
      'lazada' => (Icons.local_mall_outlined, const Color(0xff0f146d)),
      'shopee' => (Icons.shopping_bag_outlined, const Color(0xffee4d2d)),
      'tiktok' => (Icons.music_note_rounded, const Color(0xff000000)),
      'tokopedia' => (Icons.storefront_outlined, const Color(0xff03ac0e)),
      _ => (Icons.more_horiz_rounded, const Color(0xff808080)),
    };
    return Container(
      width: 29,
      height: 29,
      margin: const EdgeInsets.only(right: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 17, color: color),
    );
  }

  Widget _aboutPage() {
    const features = <(IconData, String, String)>[
      (
        Icons.insights_outlined,
        'Ringkasan usaha',
        'Pantau omzet, pengeluaran, laba bersih, dan performa usaha setiap bulan.',
      ),
      (
        Icons.shopping_bag_outlined,
        'Penjualan & HPP',
        'Catat transaksi dan hitung HPP per produk dengan lebih mudah.',
      ),
      (
        Icons.inventory_2_outlined,
        'Stok & pengeluaran',
        'Pantau persediaan dan biaya usaha dalam satu alur.',
      ),
      (
        Icons.phonelink_lock_outlined,
        'Data tetap di perangkat',
        'Data disimpan secara lokal. Ekspor ke Excel atau buat cadangan saat dibutuhkan.',
      ),
    ];

    Widget featureCard((IconData, String, String) feature) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .34),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _blue.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(feature.$1, size: 19, color: _blue),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  feature.$2,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                AppText(
                  feature.$3,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    Widget metadata(
      String label,
      String value,
      IconData icon, {
      Widget? leading,
      VoidCallback? onTap,
    }) => Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .34),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white.withValues(alpha: .4)),
          ),
          child: Row(
            children: [
              leading ?? Icon(icon, size: 19, color: _blue),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      label,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 3),
                    AppText.raw(
                      value,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    Future<void> openSocialProfile(BuildContext dialogContext, Uri uri) async {
      Navigator.of(dialogContext).pop();
      try {
        final opened = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!opened && mounted) {
          _message('Profil tidak bisa dibuka');
        }
      } on PlatformException catch (error) {
        debugPrint('Could not open social profile (${uri.host}): $error');
        if (mounted) {
          _message('Profil tidak bisa dibuka');
        }
      }
    }

    Future<void> openUpdatePage() async {
      final uri = Uri.parse('https://github.com/cuoraex/pocketr/');
      try {
        final opened = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!opened && mounted) {
          _message('Tautan repositori tidak bisa dibuka.', isError: true);
        }
      } on PlatformException catch (error) {
        debugPrint('Could not open update page (${uri.host}): $error');
        if (mounted) {
          _message('Tautan repositori tidak bisa dibuka.', isError: true);
        }
      }
    }

    void showCreatorSocials() {
      showDialog<void>(
        context: context,
        barrierColor: const Color(0x180f202c),
        builder: (dialogContext) {
          Widget socialLink(String name, String handle, Widget logo, Uri uri) =>
              Material(
                color: Colors.white.withValues(alpha: .38),
                borderRadius: BorderRadius.circular(15),
                child: InkWell(
                  borderRadius: BorderRadius.circular(15),
                  onTap: () => openSocialProfile(dialogContext, uri),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: logo,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  color: _ink,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                handle,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.open_in_new_rounded,
                          size: 17,
                          color: _muted,
                        ),
                      ],
                    ),
                  ),
                ),
              );

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _popupTintColor.withValues(alpha: .98),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: .8)),
                  boxShadow: [
                    BoxShadow(
                      color: _ink.withValues(alpha: .13),
                      blurRadius: 32,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        ClipOval(
                          child: Image.asset(
                            'assets/images/cuoraex_profile.jpg',
                            width: 42,
                            height: 42,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 11),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppText(
                                'Ikuti Cuoraex',
                                style: TextStyle(
                                  color: _ink,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 3),
                              AppText(
                                'Pilih media sosial untuk melihat profil',
                                style: TextStyle(color: _muted, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: localizeAppText('Tutup'),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close_rounded, size: 19),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    socialLink(
                      'GitHub',
                      'cuoraex',
                      Image.asset(
                        'assets/images/github-logo.png',
                        width: 24,
                        height: 24,
                        fit: BoxFit.contain,
                      ),
                      Uri.parse('https://github.com/cuoraex'),
                    ),
                    const SizedBox(height: 8),
                    socialLink(
                      'Facebook',
                      'cuoraex',
                      const Icon(Icons.facebook, size: 24, color: _blue),
                      Uri.parse('https://www.facebook.com/Cuoraex/'),
                    ),
                    const SizedBox(height: 8),
                    socialLink(
                      'Instagram',
                      '@cuoraex',
                      ClipOval(
                        child: Image.asset(
                          'assets/images/instagram_logo.png',
                          width: 24,
                          height: 24,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Uri.parse('https://www.instagram.com/cuoraex/'),
                    ),
                    const SizedBox(height: 8),
                    socialLink(
                      'Threads',
                      '@cuoraex',
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: Image.asset(
                          'assets/images/threads_logo.png',
                          width: 24,
                          height: 24,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Uri.parse('https://www.threads.com/@cuoraex'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    final featureSection = _glassCard(
      title: 'Fitur utama',
      icon: Icons.auto_awesome_outlined,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 520 ? 2 : 1;
          final cardHeight = constraints.maxWidth < 260 ? 148.0 : 128.0;
          final rows = <Widget>[];
          for (var start = 0; start < features.length; start += columns) {
            final rowFeatures = features.skip(start).take(columns).toList();
            rows.add(
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var index = 0;
                      index < rowFeatures.length;
                      index++
                    ) ...[
                      if (index > 0) const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: cardHeight,
                          child: featureCard(rowFeatures[index]),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
            if (start + columns < features.length) {
              rows.add(const SizedBox(height: 10));
            }
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          );
        },
      ),
    );
    final informationSection = _glassCard(
      title: 'Informasi aplikasi',
      icon: Icons.info_outline,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 10.0;
          final columns = constraints.maxWidth >= 440 ? 2 : 1;
          final width =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  SizedBox(
                    width: width,
                    child: metadata(
                      'Dibuat oleh',
                      'Cuoraex',
                      Icons.person_outline_rounded,
                      onTap: showCreatorSocials,
                      leading: ClipOval(
                        child: Image.asset(
                          'assets/images/cuoraex_profile.jpg',
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: metadata(
                      'Versi',
                      'v$_appVersion',
                      Icons.sell_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(15),
                child: InkWell(
                  onTap: openUpdatePage,
                  borderRadius: BorderRadius.circular(15),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .34),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.system_update_alt_rounded,
                          size: 20,
                          color: _blue,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppText(
                                'Check for update',
                                style: TextStyle(
                                  color: _ink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 3),
                              AppText(
                                'Lihat versi terbaru di GitHub',
                                style: TextStyle(color: _muted, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.open_in_new_rounded,
                          size: 17,
                          color: _muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final sections = constraints.maxWidth >= 760
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: featureSection),
                  const SizedBox(width: 14),
                  Expanded(child: informationSection),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  featureSection,
                  const SizedBox(height: 14),
                  informationSection,
                ],
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => Align(
                alignment: Alignment.center,
                child: SizedBox(
                  width: constraints.maxWidth * .5,
                  child: _glassCard(
                    padding: EdgeInsets.zero,
                    cornerRadius: 32,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: AspectRatio(
                        aspectRatio: 2030 / 768,
                        child: Image.asset(
                          'assets/images/pocketr_about_banner.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: _glassCard(
                padding: const EdgeInsets.all(20),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      'Kelola keuangan usaha dengan lebih rapi.',
                      style: TextStyle(
                        color: _blue,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 8),
                    AppText(
                      'PocketR membantu mencatat penjualan dan pengeluaran, menghitung HPP dan laba, serta memantau stok dan pembagian laba dalam satu aplikasi.',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            sections,
          ],
        );
      },
    );
  }

  Widget _expensesPage() {
    const tabs = <(String, String)>[
      ('operasional', 'Operasional'),
      ('iklan', 'Iklan'),
      ('gaji', 'Gaji'),
      ('thr', 'THR'),
      ('zakat', 'Zakat'),
    ];
    final summary = _data.summary(_month);
    final expenses = _data.expenses
        .where(
          (expense) =>
              expense.month == _month && expense.category == _expenseTab,
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeading(
          'Pengeluaran',
          monthStepper: true,
          showLowStockWarning: true,
        ),
        _kpiGrid([
          _Kpi(
            'Total pengeluaran',
            formatMoney(summary.costs),
            'bulan ini',
            Icons.account_balance_wallet_outlined,
            _red,
          ),
          _Kpi(
            'Operasional',
            formatMoney(summary.operations),
            'biaya rutin',
            Icons.home_outlined,
            _orange,
          ),
          _Kpi(
            'Iklan (+PPN)',
            formatMoney(summary.ads + summary.ppn),
            'platform',
            Icons.campaign_outlined,
            const Color(0xffca5e90),
          ),
          _Kpi(
            'Gaji + THR',
            formatMoney(summary.salary + summary.thr),
            'pegawai & cadangan',
            Icons.groups_outlined,
            _blue,
          ),
        ]),
        const SizedBox(height: 12),
        _SlideUpEntrance(
          order: _slideUpEntranceOrder,
          child: _LiquidGlassTabBar(
            tabs: tabs,
            selectedValue: _expenseTab,
            onSelected: (value) => setState(() => _expenseTab = value),
          ),
        ),
        const SizedBox(height: 12),
        if (_expenseTab == 'zakat')
          _zakatTab(summary)
        else
          _expenseList(expenses),
      ],
    );
  }

  Widget _expenseList(List<Expense> expenses) {
    final title = categoryNames[_expenseTab] ?? 'Pengeluaran';
    final addable = _expenseTab != 'zakat';
    final total = expenses.fold<double>(
      0,
      (sum, expense) => sum + _data.expenseTotal(expense),
    );
    if (_expenseTab == 'operasional' ||
        _expenseTab == 'iklan' ||
        _expenseTab == 'gaji' ||
        _expenseTab == 'thr') {
      final isOperations = _expenseTab == 'operasional';
      return _glassCard(
        title: isOperations ? 'Biaya operasional' : title,
        icon: _expenseIcon(_expenseTab),
        trailing: _PocketRActionButton(
          icon: Icons.add,
          blue: true,
          label: isOperations ? 'Tambah biaya' : 'Tambah $title',
          labelOffset: -1,
          onPressed: () => _addExpense(_expenseTab),
        ),
        padding: const EdgeInsets.all(16),
        child: expenses.isEmpty
            ? const _EmptyState(
                title: 'Belum ada data bulan ini',
                detail:
                    'Tambah catatan pengeluaran menggunakan tombol di atas.',
              )
            : _OperationalExpenseTable(
                expenses: expenses,
                total: total,
                getTotal: _data.expenseTotal,
                onEdit: (expense) => _addExpense(_expenseTab, expense),
                onDelete: _deleteExpense,
              ),
      );
    }
    return _glassCard(
      title: title,
      icon: _expenseIcon(_expenseTab),
      trailing: addable
          ? _PocketRActionButton(
              icon: Icons.add,
              blue: true,
              label: 'Tambah $title',
              labelOffset: -1,
              onPressed: () => _addExpense(_expenseTab),
            )
          : null,
      child: expenses.isEmpty
          ? const _EmptyState(
              title: 'Belum ada data bulan ini',
              detail: 'Tambah catatan pengeluaran menggunakan tombol di atas.',
            )
          : Column(
              children: [
                for (final expense in expenses)
                  _ExpenseTile(
                    expense: expense,
                    total: _data.expenseTotal(expense),
                    onEdit: () => _addExpense(_expenseTab, expense),
                    onDelete: () => _deleteExpense(expense),
                  ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const AppText(
                      'Total',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    AppText(
                      formatMoney(total),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _zakatTab(MonthSummary summary) => _glassCard(
    title: 'Zakat mal · ${monthLabel(_month)}',
    icon: Icons.volunteer_activism_outlined,
    child: Column(
      children: [
        _breakdown(summary),
        const SizedBox(height: 10),
        Divider(height: 1, color: _ink.withValues(alpha: .12)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              const Expanded(
                child: AppText(
                  'Nominal zakat terhitung',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              AppText(
                formatMoney(-summary.zakat),
                style: const TextStyle(
                  color: _muted,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const AppText(
          'Zakat dihitung dari laba sebelum zakat. Laba bersih adalah nilai setelah zakat dan menjadi dasar pembagian untuk pemilik.',
          style: TextStyle(color: _muted),
        ),
      ],
    ),
  );

  Widget _productsPage() {
    final products = [..._data.products]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (_selectedProductId == null ||
        !products.any((product) => product.id == _selectedProductId)) {
      _selectedProductId = products.firstOrNull?.id;
    }
    final selected = products
        .where((product) => product.id == _selectedProductId)
        .firstOrNull;
    final hasLowStock = _hasLowStock;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeading('Produk dan HPP'),
        LayoutBuilder(
          builder: (context, constraints) {
            final tabs = _SlideUpEntrance(
              order: _slideUpEntranceOrder,
              child: _LiquidGlassTabBar(
                tabs: const [('produk', 'Produk'), ('bahan', 'Bahan baku')],
                selectedValue: _productTab,
                onSelected: (value) {
                  _slideUpEntranceOrder.reset();
                  setState(() => _productTab = value);
                },
              ),
            );
            final showProductAdd = _productTab == 'produk';
            final addButton = _PocketRActionButton(
              icon: Icons.add,
              label: 'Tambah produk',
              labelOffset: -1,
              onPressed: () => _addProduct(),
              blue: true,
            );
            final productActions = Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                _SlideUpEntrance(
                  order: _slideUpEntranceOrder,
                  child: _PocketRActionButton(
                    icon: Icons.upload_file_outlined,
                    label: 'Impor HPP',
                    labelOffset: -1,
                    onPressed: _showHppImportMenu,
                    blue: true,
                  ),
                ),
                _SlideUpEntrance(
                  order: _slideUpEntranceOrder,
                  child: addButton,
                ),
              ],
            );
            final lowStockWarning = _lowStockWarning();
            if (constraints.maxWidth >= 900 &&
                (!hasLowStock || constraints.maxWidth >= 1100)) {
              return Row(
                children: [
                  tabs,
                  if (showProductAdd || hasLowStock) const Spacer(),
                  if (hasLowStock) ...[
                    lowStockWarning,
                    const SizedBox(width: 8),
                  ],
                  if (showProductAdd) productActions,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tabs,
                if (hasLowStock) ...[
                  const SizedBox(height: 8),
                  Center(child: lowStockWarning),
                ],
                if (showProductAdd) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: productActions,
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        if (_productTab == 'bahan')
          _catalogList()
        else
          _productDetails(products, selected),
      ],
    );
  }

  bool get _hasLowStock => _data.products.any((product) {
    if (product.stock == null) return false;
    final balances = _data.stockByColor(product);
    return balances.isEmpty
        ? (_data.stockOf(product) ?? 0) <= 5
        : balances.values.any((quantity) => quantity <= 5);
  });

  Widget _lowStockWarning({bool animate = true}) {
    final warning = Tooltip(
      message: localizeAppText(
        'Ada varian produk dengan stok 5 pcs atau kurang',
      ),
      child: _ButtonPop(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(99),
          child: InkWell(
            borderRadius: BorderRadius.circular(99),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            onTap: _scrollToStock,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _red.withValues(alpha: .09),
                border: Border.all(color: _red.withValues(alpha: .16)),
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: _red),
                  SizedBox(width: 6),
                  AppText(
                    'Stok menipis',
                    style: TextStyle(
                      color: _red,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return SizedBox(
      height: 40,
      child: Center(
        child: animate
            ? _SlideUpEntrance(order: _slideUpEntranceOrder, child: warning)
            : warning,
      ),
    );
  }

  Future<void> _scrollToStock() async {
    final alignment = _isDesktop ? .15 : .06;
    if (_tab != 'produk') {
      _navigate('produk');
    }
    if (_productTab != 'produk') {
      setState(() => _productTab = 'produk');
    }
    await WidgetsBinding.instance.endOfFrame;
    var targetContext = _stockTitleKey.currentContext;
    if (targetContext == null) {
      await WidgetsBinding.instance.endOfFrame;
      targetContext = _stockTitleKey.currentContext;
    }
    if (!mounted || targetContext == null || !targetContext.mounted) return;
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeInOutCubic,
      alignment: alignment,
    );
  }

  Widget _catalogList() => LayoutBuilder(
    builder: (context, constraints) {
      final materials = _data.materials
          .where((item) => item.category == MaterialCategory.bahanBaku)
          .toList();
      final sewingCosts = _data.materials
          .where((item) => item.category == MaterialCategory.ongkosJahit)
          .toList();
      final materialCard = _materialCatalogCard(
        title: 'Daftar bahan baku',
        icon: Icons.category_outlined,
        category: MaterialCategory.bahanBaku,
        materials: materials,
        trailing: _PocketRActionButton(
          icon: Icons.add,
          label: 'Tambah',
          compact: true,
          labelOffset: -1,
          onPressed: () =>
              _addCatalogMaterial(category: MaterialCategory.bahanBaku),
          blue: true,
        ),
      );
      final sewingCard = _materialCatalogCard(
        title: 'Daftar ongkos',
        icon: Icons.content_cut_outlined,
        category: MaterialCategory.ongkosJahit,
        materials: sewingCosts,
        trailing: _PocketRActionButton(
          icon: Icons.add,
          label: 'Tambah',
          compact: true,
          labelOffset: -1,
          onPressed: () =>
              _addCatalogMaterial(category: MaterialCategory.ongkosJahit),
          blue: true,
        ),
      );
      if (constraints.maxWidth >= 820) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: materialCard),
            const SizedBox(width: 12),
            Expanded(child: sewingCard),
          ],
        );
      }
      return Column(
        children: [materialCard, const SizedBox(height: 12), sewingCard],
      );
    },
  );

  Widget _materialCatalogCard({
    required String title,
    required IconData icon,
    required MaterialCategory category,
    required List<MaterialCost> materials,
    Widget? trailing,
  }) => _glassCard(
    title: title,
    icon: icon,
    trailing: trailing,
    padding: const EdgeInsets.all(16),
    child: materials.isEmpty
        ? _EmptyState(
            title: category == MaterialCategory.ongkosJahit
                ? 'Belum ada ongkos'
                : 'Belum ada bahan baku',
            detail: category == MaterialCategory.ongkosJahit
                ? 'Tambahkan ongkos jahit untuk dipakai dalam HPP produk.'
                : 'Tambahkan kain, resleting, atau komponen produk.',
          )
        : _materialCatalogTable(materials),
  );

  Widget _materialCatalogTable(List<MaterialCost> materials) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 440;
      final rowExtent = compact ? 78.0 : 44.0;
      final visibleItemCount = materials.length < 15 ? materials.length : 15;
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .28),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: compact ? 3 : 4,
                  child: const AppText('Nama', style: _headerStyle),
                ),
                if (!compact)
                  const Expanded(
                    flex: 3,
                    child: AppText(
                      'Satuan',
                      textAlign: TextAlign.center,
                      style: _headerStyle,
                    ),
                  ),
                Expanded(
                  flex: 3,
                  child: AppText(
                    compact ? 'Harga' : 'Harga satuan',
                    textAlign: TextAlign.center,
                    style: _headerStyle,
                  ),
                ),
                if (!compact) const SizedBox(width: 128),
              ],
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: visibleItemCount * rowExtent,
            child: ListView.builder(
              primary: false,
              itemCount: materials.length,
              itemExtent: rowExtent,
              itemBuilder: (context, index) {
                final material = materials[index];
                return Column(
                  children: [
                    Expanded(
                      child: _MaterialTile(
                        material: material,
                        compact: compact,
                        onEdit: () => _addCatalogMaterial(existing: material),
                        onDelete: () => _deleteCatalogMaterial(material),
                      ),
                    ),
                    if (index < materials.length - 1)
                      Divider(height: 1, color: _ink.withValues(alpha: .1)),
                  ],
                );
              },
            ),
          ),
        ],
      );
    },
  );

  Widget _productDetails(List<Product> products, Product? selected) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final query = _productSearchController.text.trim().toLowerCase();
          final shownProducts = query.isEmpty
              ? products
              : products
                    .where(
                      (product) => product.name.toLowerCase().contains(query),
                    )
                    .toList();
          final productList = _productPicker(
            shownProducts,
            selected,
            searching: query.isNotEmpty,
          );
          final productListFill = _productPicker(
            shownProducts,
            selected,
            fill: true,
            searching: query.isNotEmpty,
          );
          final productEditor = selected == null
              ? _emptyProductEditor()
              : _productDetailCard(
                  selected,
                  _data.sales
                      .where((sale) => sale.productId == selected.id)
                      .fold<double>(0, (sum, sale) => sum + sale.qty),
                );
          final productPanel = _SlideUpEntrance(
            order: _slideUpEntranceOrder,
            child: _FrostedSurface(
              borderRadius: BorderRadius.circular(22),
              tintColor: const Color(0xfff7f9fb),
              tintOpacity: .48,
              prominentShadow: true,
              child: LayoutBuilder(
                builder: (context, panelConstraints) {
                  const sidePanelWidth = 258.0;
                  if (panelConstraints.maxWidth < 650) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 22, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _productListHeader(),
                              const SizedBox(height: 22),
                              productList,
                            ],
                          ),
                        ),
                        Divider(height: 1, color: _ink.withValues(alpha: .1)),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  _LiquidIconBadge(
                                    icon: Icons.edit_outlined,
                                    size: 29,
                                    iconSize: 17,
                                  ),
                                  SizedBox(width: 9),
                                  AppText(
                                    'Edit produk',
                                    style: TextStyle(
                                      color: _ink,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              productEditor,
                            ],
                          ),
                        ),
                      ],
                    );
                  }
                  // The card height follows the editor; the list fills that
                  // height and scrolls on its own.
                  const listBottomPadding = 21.0;
                  return Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: sidePanelWidth),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 460),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    _LiquidIconBadge(
                                      icon: Icons.edit_outlined,
                                      size: 29,
                                      iconSize: 17,
                                    ),
                                    SizedBox(width: 9),
                                    AppText(
                                      'Edit produk',
                                      style: TextStyle(
                                        color: _ink,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                productEditor,
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: sidePanelWidth,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            22,
                            22,
                            17,
                            listBottomPadding,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _productListHeader(),
                              const SizedBox(height: 22),
                              Expanded(child: productListFill),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: sidePanelWidth,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 1,
                          color: _ink.withValues(alpha: .1),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              productPanel,
              if (selected != null) ...[
                const SizedBox(height: 12),
                _stockDetails(products, selected),
              ],
            ],
          );
        },
      );

  Widget _productListHeader() {
    if (_productSearchOpen) {
      return Container(
        height: 36,
        padding: const EdgeInsets.only(left: 10, right: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _ink.withValues(alpha: .12)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              size: 17,
              color: _ink.withValues(alpha: .6),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _productSearchController,
                autofocus: true,
                cursorColor: _ink,
                style: const TextStyle(color: _ink, fontSize: 13),
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  hintText: localizeAppText('Cari produk'),
                  hintStyle: TextStyle(color: _ink.withValues(alpha: .45)),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            InkResponse(
              radius: 14,
              onTap: () => setState(() {
                _productSearchOpen = false;
                _productSearchController.clear();
              }),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.close_rounded, size: 16, color: _ink),
              ),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          const _LiquidIconBadge(
            icon: Icons.list_alt_outlined,
            size: 29,
            iconSize: 17,
          ),
          const SizedBox(width: 9),
          const Expanded(
            child: AppText(
              'List produk',
              style: TextStyle(
                color: _ink,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Tooltip(
            message: localizeAppText('Cari produk'),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _productSearchOpen = true),
              child: const MouseRegion(
                cursor: SystemMouseCursors.click,
                child: _LiquidIconBadge(
                  icon: Icons.search_rounded,
                  size: 29,
                  iconSize: 17,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _productPicker(
    List<Product> products,
    Product? selected, {
    bool fill = false,
    bool searching = false,
  }) {
    if (products.isEmpty && searching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: _EmptyState(
          centerTitle: true,
          title: 'Produk tidak ditemukan',
          detail: 'Coba kata kunci lain.',
        ),
      );
    }
    if (products.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: _EmptyState(
          centerTitle: true,
          title: 'Belum ada produk',
          detail: 'Tambahkan produk untuk mengelola varian dan bahan.',
        ),
      );
    }
    const itemHeight = 58.0;
    const pillHeight = 54.0;
    const bottomShadowSpace = 14.0;
    final selectedIndex = products.indexWhere(
      (product) => product.id == selected?.id,
    );
    if (selectedIndex >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_productPickerScrollController.hasClients) return;
        final position = _productPickerScrollController.position;
        final itemTop = selectedIndex * itemHeight;
        final itemBottom = itemTop + pillHeight;
        final visibleTop = position.pixels;
        final visibleBottom = visibleTop + position.viewportDimension;
        final target = itemTop < visibleTop
            ? itemTop
            : itemBottom + bottomShadowSpace > visibleBottom
            ? itemBottom + bottomShadowSpace - position.viewportDimension
            : null;
        if (target != null) {
          _productPickerScrollController.animateTo(
            target.clamp(0.0, position.maxScrollExtent),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
    final listHeight = products.length * itemHeight;
    final visibleHeight = listHeight + bottomShadowSpace;
    return ClipRect(
      clipper: const _ProductPickerClipper(),
      child: SizedBox(
        height: fill ? null : visibleHeight,
        child: SingleChildScrollView(
          clipBehavior: Clip.none,
          controller: _productPickerScrollController,
          child: SizedBox(
            height: listHeight + bottomShadowSpace,
            child: Stack(
              children: [
                if (selectedIndex >= 0)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 520),
                    curve: Curves.easeInOutCubicEmphasized,
                    top: selectedIndex * itemHeight,
                    left: 0,
                    right: 0,
                    height: pillHeight,
                    child: IgnorePointer(
                      child: _FrostedSurface(
                        borderRadius: BorderRadius.circular(22),
                        tintColor: const Color(0xfff2faff),
                        tintOpacity: .62,
                        blurSigma: 18,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final product in products)
                      SizedBox(
                        height: itemHeight,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: double.infinity,
                            height: pillHeight,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => setState(
                                () => _selectedProductId = product.id,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 7,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          AppText.raw(
                                            product.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: _ink,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          AppText(
                                            'HPP ${formatMoney(_data.productHpp(product))}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: _muted,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyProductEditor() => const Center(
    child: _EmptyState(
      title: 'Pilih produk untuk diedit',
      detail: 'Tambahkan produk, lalu pilih dari daftar untuk mengelola varian dan bahan baku.',
    ),
  );

  Future<void> _showProductImage(Product product) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final screenSize = MediaQuery.sizeOf(dialogContext);
        final image = _productImage(product);
        return SafeArea(
          child: Center(
            child: _FrostedSurface(
              borderRadius: BorderRadius.circular(28),
              tintColor: Colors.white,
              padding: const EdgeInsets.all(14),
              blurSigma: 20,
              child: Stack(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: screenSize.width * .45,
                      maxHeight: screenSize.height * .425,
                    ),
                    child: InteractiveViewer(
                      child: image != null
                          ? Image(image: image, fit: BoxFit.contain)
                          : const _ProfileAvatar(
                              image: null,
                              size: 116,
                              framed: false,
                            ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _FrostedSurface(
                      borderRadius: BorderRadius.circular(99),
                      tintOpacity: .58,
                      padding: const EdgeInsets.all(1),
                      blurSigma: 14,
                      backdropBlur: false,
                      shadow: false,
                      child: IconButton(
                        tooltip: localizeAppText('Tutup foto'),
                        onPressed: () => Navigator.pop(context),
                        style: IconButton.styleFrom(
                          foregroundColor: _ink,
                          minimumSize: const Size(36, 36),
                          padding: EdgeInsets.zero,
                        ),
                        icon: const Icon(Icons.close, size: 19),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          _normalDialogTransition(animation, child),
    );
  }

  Widget _productDetailCard(Product product, double sold) {
    const avatarSize = 116.0;
    final materials = product.materials.map(_data.effectiveMaterial).toList();
    final variantValues = switch (_productVariantTab) {
      'ukuran' => product.sizes,
      _ => product.colors,
    };
    final variantType = _productVariantTab == 'ukuran' ? 'Ukuran' : 'Warna';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Builder(
          builder: (context) {
            final info = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText.raw(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.4,
                  ),
                ),
                const SizedBox(height: 3),
                AppText(
                  '${product.materials.length} bahan · terjual ${formatNumber(sold)} pcs',
                  textAlign: TextAlign.left,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            );
            final imageButton = _productAction(
              'Ganti gambar',
              () => _pickProductImage(product),
              large: true,
            );
            final renameButton = _productAction(
              'Ubah nama',
              () => _addProduct(product),
              large: true,
            );
            final removeImageButton = _productAction(
              'Hapus gambar',
              () => _removeProductImage(product),
              danger: true,
              large: true,
            );
            final deleteButton = _productAction(
              'Hapus produk',
              () => _deleteProduct(product),
              danger: true,
              large: true,
            );
            final photo = Tooltip(
              message: localizeAppText('Lihat foto besar'),
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _showProductImage(product),
                  child: CircleAvatar(
                    radius: avatarSize / 2,
                    backgroundColor: Colors.white.withValues(alpha: .62),
                    backgroundImage: _productImage(product),
                    child: _productImage(product) == null
                        ? AppText(
                            product.name.isEmpty
                                ? '?'
                                : product.name.characters.first.toUpperCase(),
                            style: const TextStyle(
                              color: _blue,
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            );
            final actions = Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    imageButton,
                    const SizedBox(width: 5),
                    renameButton,
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (product.img.isNotEmpty) ...[
                      removeImageButton,
                      const SizedBox(width: 5),
                    ],
                    deleteButton,
                  ],
                ),
              ],
            );
            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < avatarSize + 14 + 380) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          photo,
                          const SizedBox(width: 14),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: info,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerRight, child: actions),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    photo,
                    const SizedBox(width: 14),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: info,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 269,
                      height: avatarSize,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: actions,
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: _FrostedSurface(
            borderRadius: BorderRadius.circular(20),
            tintColor: const Color(0xfff4fbff),
            tintOpacity: .42,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
            shadow: false,
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppText(
                    'HPP per pcs',
                    style: TextStyle(color: _muted, fontSize: 14),
                  ),
                  const SizedBox(height: 7),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: AppText(
                      formatMoney(_data.productHpp(product)),
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const _LiquidIconBadge(
              icon: Icons.category_outlined,
              size: 27,
              iconSize: 16,
            ),
            const SizedBox(width: 9),
            const AppText(
              'Varian',
              style: TextStyle(color: _ink, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: AppText(
                'opsional, Warna / Ukuran',
                style: TextStyle(color: _muted, fontSize: 11),
              ),
            ),
            _PocketRActionButton(
              icon: Icons.add,
              label: 'Tambah $variantType',
              labelOffset: -1,
              blue: true,
              onPressed: () => _editVariants(product),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _LiquidGlassTabBar(
          tabs: const [('warna', 'Warna'), ('ukuran', 'Ukuran')],
          selectedValue: _productVariantTab == 'ukuran' ? 'ukuran' : 'warna',
          onSelected: (value) => setState(() => _productVariantTab = value),
        ),
        const SizedBox(height: 9),
        if (variantValues.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 5),
            child: AppText(
              'Belum ada varian.',
              style: TextStyle(color: _muted),
            ),
          )
        else
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final value in variantValues)
                _productVariantPill(
                  value,
                  onRemove: () =>
                      _removeProductVariant(product, value, _productVariantTab),
                ),
            ],
          ),
        const SizedBox(height: 13),
        Row(
          children: [
            const _LiquidIconBadge(
              icon: Icons.sell_outlined,
              size: 27,
              iconSize: 16,
            ),
            const SizedBox(width: 9),
            const Expanded(
              child: AppText(
                'Rincian bahan baku',
                style: TextStyle(color: _ink, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ProductMaterialAdder(
          catalog: _data.materials,
          onAdd: (material) => _saveProductMaterial(product, material),
        ),
        const SizedBox(height: 10),
        if (materials.isEmpty)
          const _EmptyState(
            title: 'Belum ada bahan',
            detail: 'Masukkan bahan baku atau biaya produksi produk ini.',
          )
        else
          _productMaterialsTable(product, materials),
      ],
    );
  }

  Widget _productAction(
    String label,
    VoidCallback onPressed, {
    bool danger = false,
    bool large = false,
  }) => _PocketRActionButton(
    icon: null,
    label: label,
    onPressed: onPressed,
    danger: danger,
    fixedWidth: large ? 132 : null,
    labelOffset: -2,
    compact: !large,
  );

  Widget _productVariantPill(String value, {required VoidCallback onRemove}) =>
      Container(
        padding: const EdgeInsets.only(left: 9, right: 3, top: 3, bottom: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .48),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(radius: 3, backgroundColor: _blue),
            const SizedBox(width: 6),
            AppText.raw(value, style: const TextStyle(fontSize: 11)),
            const SizedBox(width: 3),
            _ButtonPop(
              child: InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(99),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close, size: 13, color: _muted),
                ),
              ),
            ),
          ],
        ),
      );

  Future<void> _removeProductVariant(
    Product product,
    String value,
    String variantType,
  ) async {
    setState(() {
      switch (variantType) {
        case 'warna':
          product.colors.remove(value);
        case 'ukuran':
          product.sizes.remove(value);
        case 'lainnya':
          product.variants.remove(value);
      }
    });
    await _save();
  }

  Widget _productMaterialsTable(
    Product product,
    List<MaterialCost> materials,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 620;
      return Column(
        children: [
          _productMaterialsHeader(compact),
          const SizedBox(height: 5),
          for (var index = 0; index < materials.length; index++) ...[
            if (index > 0) ...[
              const SizedBox(height: 5),
              Divider(height: 1, color: _ink.withValues(alpha: .1)),
              const SizedBox(height: 5),
            ],
            _productMaterialListRow(product, materials[index], compact),
          ],
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _blue.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                if (compact) ...[
                  const Expanded(
                    child: AppText(
                      'Total HPP',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  AppText(
                    formatMoney(_data.productHpp(product)),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ] else ...[
                  const Expanded(
                    flex: 6,
                    child: AppText(
                      'Total HPP',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: AppText(
                      formatMoney(_data.productHpp(product)),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 128),
                ],
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _productMaterialsHeader(bool compact) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .28),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      children: [
        Expanded(
          flex: 3,
          child: const AppText('Bahan / biaya', style: _headerStyle),
        ),
        if (!compact)
          const Expanded(
            flex: 7,
            child: AppText(
              'Catatan',
              textAlign: TextAlign.center,
              style: _headerStyle,
            ),
          ),
        Expanded(
          flex: 2,
          child: AppText(
            'Subtotal',
            textAlign: compact ? TextAlign.end : TextAlign.center,
            style: _headerStyle,
          ),
        ),
        if (!compact) const SizedBox(width: 128),
      ],
    ),
  );

  Widget _productMaterialListRow(
    Product product,
    MaterialCost material,
    bool compact,
  ) {
    final details =
        'Qty ${formatNumber(material.qty.round())} · '
        '${material.unit.isEmpty ? 'Tanpa satuan' : material.unit} · '
        '${formatMoney(material.price)}';
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PocketRActionButton(
          icon: null,
          label: 'Ubah',
          compact: true,
          labelOffset: -1,
          foregroundColor: _blue,
          onPressed: () => _addProductMaterial(product, material),
        ),
        const SizedBox(width: 4),
        _PocketRActionButton(
          icon: null,
          label: 'Hapus',
          danger: true,
          compact: true,
          labelOffset: -1,
          onPressed: () async {
            if (!await _confirm(
              'Hapus rincian bahan?',
              material.name,
              translateBody: false,
            )) {
              return;
            }
            setState(
              () => product.materials.removeWhere(
                (item) => item.id == material.id,
              ),
            );
            await _save();
          },
        ),
      ],
    );
    final subtotal = AppText(
      formatMoney(material.subtotal),
      textAlign: TextAlign.center,
      style: const TextStyle(fontWeight: FontWeight.w800),
    );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Expanded(child: _productMaterialName(material.name)),
                const SizedBox(width: 8),
                Flexible(child: subtotal),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: AppText(
                    details,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
                controls,
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: [
          Expanded(flex: 3, child: _productMaterialName(material.name)),
          Expanded(
            flex: 3,
            child: AppText(
              details,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ),
          Expanded(flex: 2, child: subtotal),
          SizedBox(
            width: 128,
            child: Align(alignment: Alignment.centerRight, child: controls),
          ),
        ],
      ),
    );
  }

  Widget _productMaterialName(String name) => Row(
    children: [
      CircleAvatar(
        radius: 15,
        backgroundColor: Colors.white.withValues(alpha: .55),
        child: AppText(
          name.isEmpty ? '?' : name.characters.first.toUpperCase(),
          style: const TextStyle(
            color: _muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: AppText.raw(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
    ],
  );

  Widget _stockDetails(List<Product> products, Product? selectedProduct) {
    final stockedProducts = products
        .where((product) => product.stock != null)
        .toList();
    final totalStock = stockedProducts.fold<double>(
      0,
      (total, product) => total + (_data.stockOf(product) ?? 0),
    );
    final initialProduct =
        selectedProduct ?? (products.isEmpty ? null : products.first);
    return _glassCard(
      title: 'Stok',
      titleKey: _stockTitleKey,
      icon: Icons.inventory_2_outlined,
      trailing: initialProduct == null
          ? null
          : _PocketRActionButton(
              icon: Icons.add,
              label: stockedProducts.isEmpty ? 'Aktifkan stok' : 'Tambah stok',
              labelOffset: -1,
              blue: true,
              onPressed: () => _editStock(initialProduct),
            ),
      padding: const EdgeInsets.all(16),
      child: stockedProducts.isEmpty
          ? const _EmptyState(
              title: 'Belum ada stok',
              detail: 'Catat stok awal agar jumlah tersedia otomatis berkurang saat penjualan dicatat.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _blue.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: AppText(
                          'Total stok',
                          style: TextStyle(
                            color: _muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      AppText(
                        '${formatNumber(totalStock)} pcs',
                        style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                _StockProductsGrid(
                  products: [
                    for (final product in stockedProducts)
                      _StockProductSummary(
                        product: product,
                        balances: _data.stockByColor(product).entries.toList()
                          ..sort((a, b) => a.key.compareTo(b.key)),
                        total: _data.stockOf(product) ?? 0,
                      ),
                  ],
                  onEdit: (product) =>
                      _editStock(product, editCurrentBalance: true),
                ),
              ],
            ),
    );
  }

  Future<void> _editVariants(Product product) async {
    final colors = TextEditingController();
    final sizes = TextEditingController();
    final ok = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0x180f202c),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (dialogContext, animation, secondaryAnimation) => Center(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Material(
                color: Colors.transparent,
                child: _FrostedSurface(
                  borderRadius: BorderRadius.circular(26),
                  tintColor: _popupTintColor,
                  tintOpacity: _popupTintOpacity,
                  padding: const EdgeInsets.all(24),
                  blurSigma: 18,
                  prominentShadow: true,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: AppText(
                                'Varian produk',
                                style: TextStyle(
                                  color: _ink,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                            _PopIconButton(
                              tooltip: localizeAppText('Tutup'),
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              style: IconButton.styleFrom(
                                foregroundColor: _muted,
                                backgroundColor: Colors.white.withValues(
                                  alpha: .44,
                                ),
                                minimumSize: const Size(32, 32),
                                padding: EdgeInsets.zero,
                              ),
                              icon: const Icon(Icons.close, size: 17),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _textField(
                          colors,
                          'Warna (pisahkan dengan koma)',
                          textOffset: const Offset(0, 6),
                          inputVerticalPadding: 0,
                        ),
                        const SizedBox(height: 10),
                        _textField(
                          sizes,
                          'Ukuran (pisahkan dengan koma)',
                          textOffset: const Offset(0, 6),
                          inputVerticalPadding: 0,
                        ),
                        const SizedBox(height: 8),
                        const AppText(
                          'Contoh: Hitam, Cokelat. Hindari tanda garis miring.',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 12,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _ImportDialogPill(
                              label: 'Batal',
                              labelOffset: -1,
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                            ),
                            const SizedBox(width: 8),
                            _ImportDialogPill(
                              label: 'Simpan',
                              blue: true,
                              labelOffset: -1,
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          _normalDialogTransition(animation, child),
    );
    if (ok == true) {
      List<String> parse(String text) => text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList();
      final values = [...parse(colors.text), ...parse(sizes.text)];
      if (values.any((value) => value.contains('/'))) {
        _message('Nama varian tidak boleh memakai tanda “/”.', isError: true);
      } else {
        setState(() {
          product
            ..colors = {...product.colors, ...parse(colors.text)}.toList()
            ..sizes = {...product.sizes, ...parse(sizes.text)}.toList();
        });
        await _save();
      }
    }
    colors.dispose();
    sizes.dispose();
  }

  Widget _kpiGrid(List<_Kpi> items) => LayoutBuilder(
    builder: (context, constraints) {
      final maxColumns = constraints.maxWidth > 1050 ? 4 : 2;
      final columns = items.isEmpty
          ? 1
          : items.length < maxColumns
          ? items.length
          : maxColumns;
      final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final item in items)
            SizedBox(
              width: width,
              child: _glassCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _LiquidIconBadge(
                          icon: item.icon,
                          size: 33,
                          iconSize: 17,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AppText(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AppText(
                        item.value,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (Platform.isAndroid)
                      // Reserve two lines so every card matches the tallest
                      // ("Total pengeluaran") on Android.
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: (TextPainter(
                            text: const TextSpan(
                              text: 'A\nA',
                              style: TextStyle(fontSize: 12),
                            ),
                            textDirection: TextDirection.ltr,
                            textScaler: MediaQuery.textScalerOf(context),
                          )..layout()).height,
                        ),
                        child: AppText(
                          item.detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      )
                    else
                      AppText(
                        item.detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _glassCard({
    String? title,
    Key? titleKey,
    IconData? icon,
    Widget? titleLeading,
    Widget? trailing,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(22),
    double cornerRadius = 22,
  }) => _SlideUpEntrance(
    order: _slideUpEntranceOrder,
    child: _FrostedSurface(
      borderRadius: BorderRadius.circular(cornerRadius),
      tintColor: const Color(0xfff7f9fb),
      tintOpacity: .48,
      prominentShadow: true,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (titleLeading != null)
                  titleLeading
                else if (icon != null) ...[
                  _LiquidIconBadge(icon: icon, size: 29, iconSize: 17),
                  const SizedBox(width: 9),
                ],
                Expanded(
                  child: AppText(
                    title,
                    key: titleKey,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
          ],
          DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 13),
            child: child,
          ),
        ],
      ),
    ),
  );

  Widget _progressLine(String label, double value, double total, Color color) {
    final progress = total <= 0 ? 0.0 : (value / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: AppText(label)),
              AppText(
                formatMoney(value),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: progress,
              color: color,
              backgroundColor: Colors.white.withValues(alpha: .5),
            ),
          ),
        ],
      ),
    );
  }

  // Kept for the replacement backup entry point.
  // ignore: unused_element
  void _backupMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xffedf6fb),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppText(
                'Cadangkan data',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const AppText(
                'Data tersimpan otomatis di perangkat ini. Buat cadangan berkala agar mudah dipindahkan atau dipulihkan.',
                style: TextStyle(color: _muted),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: _PocketRActionButton(
                  blue: true,
                  expand: true,
                  icon: Icons.download_outlined,
                  label: 'Simpan cadangan PocketR',
                  onPressed: () {
                    Navigator.pop(context);
                    _backup();
                  },
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _restore();
                  },
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const AppText('Pulihkan dari cadangan'),
                ),
              ),
              _PopTextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _reset();
                },
                child: const AppText(
                  'Hapus semua data',
                  style: TextStyle(color: _red),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Kept for the replacement calculator entry point.
  // ignore: unused_element
  Future<void> _calculator() => showDialog<void>(
    context: context,
    builder: (context) => const _CalculatorDialog(),
  );

  double _percent(double value, double total) =>
      total <= 0 ? 0 : value / total * 100;

  Color _marketColor(String platform) => switch (platform) {
    'lazada' => const Color(0xff0f146d),
    'shopee' => const Color(0xffee4d2d),
    'tiktok' => const Color(0xfffe2c55),
    _ => _blue,
  };

  IconData _expenseIcon(String category) => switch (category) {
    'iklan' => Icons.campaign_outlined,
    'gaji' => Icons.groups_outlined,
    'thr' => Icons.card_giftcard_outlined,
    _ => Icons.home_outlined,
  };
}

class _ZakatPctDialog extends StatefulWidget {
  const _ZakatPctDialog({required this.initialValue});

  final double initialValue;

  @override
  State<_ZakatPctDialog> createState() => _ZakatPctDialogState();
}

class _ZakatPctDialogState extends State<_ZakatPctDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: formatNumber(widget.initialValue, decimals: 1),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close([double? rate]) {
    Navigator.of(context).pop(rate);
  }

  void _submit() {
    final text = _controller.text.trim();
    final value = _parseDecimal(text);
    if (text.isEmpty || value < 0 || value > 100) {
      setState(() => _error = 'Persentase zakat harus antara 0 dan 100%.');
      return;
    }
    _close(value);
  }

  @override
  Widget build(BuildContext context) => _FrostedSurface(
    borderRadius: BorderRadius.circular(26),
    tintColor: _popupTintColor,
    tintOpacity: _popupTintOpacity,
    padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
    blurSigma: 12,
    prominentShadow: true,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppText(
          'Persentase zakat',
          style: TextStyle(
            color: _ink,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 6),
          child: AppText(
            'Zakat (%)',
            style: TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _liquidInputSurface(
          minHeight: 40,
          verticalPadding: 0,
          child: Transform.translate(
            offset: const Offset(0, 9),
            child: TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.start,
              textAlignVertical: TextAlignVertical.center,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                TextInputFormatter.withFunction((oldValue, newValue) {
                  return RegExp(r'^\d*(?:[,.]\d{0,1})?$')
                          .hasMatch(newValue.text)
                      ? newValue
                      : oldValue;
                }),
              ],
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
              style: const TextStyle(color: _ink, fontSize: 13, height: 1),
              decoration: InputDecoration(
                filled: false,
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: localizeAppText('Contoh: 2,5'),
                hintStyle: TextStyle(color: Color(0xff8da0ae), fontSize: 13),
                suffix: AppText(
                  '%',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: AppText(
            _error ?? 'Masukkan nilai dari 0 sampai 100%.',
            style: TextStyle(
              color: _error == null ? _muted : _red,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _ImportDialogPill(
              label: 'Batal',
              labelOffset: 0,
              onPressed: _close,
            ),
            const SizedBox(width: 8),
            _ImportDialogPill(
              label: 'Simpan',
              blue: true,
              labelOffset: 0,
              onPressed: _submit,
            ),
          ],
        ),
      ],
    ),
  );
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color, blurRadius: size * .5)],
      ),
    ),
  );
}

class _FrostedSurface extends StatelessWidget {
  const _FrostedSurface({
    required this.child,
    required this.borderRadius,
    this.tintColor = Colors.white,
    this.tintOpacity = .38,
    this.padding = EdgeInsets.zero,
    this.shadow = true,
    this.prominentShadow = false,
    this.blurSigma = 20,
    this.backdropBlur = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Color tintColor;
  final double tintOpacity;
  final EdgeInsetsGeometry padding;
  final bool shadow;
  final bool prominentShadow;
  final double blurSigma;
  final bool backdropBlur;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: borderRadius,
      boxShadow: shadow
          ? prominentShadow
                ? const [
                    BoxShadow(
                      color: Color(0x3021425b),
                      blurRadius: 30,
                      offset: Offset(0, 12),
                    ),
                    BoxShadow(
                      color: Color(0x263da8cf),
                      blurRadius: 22,
                      offset: Offset(0, 4),
                    ),
                  ]
                : const [
                    BoxShadow(
                      color: Color(0x1f21425b),
                      blurRadius: 18,
                      offset: Offset(0, 7),
                    ),
                  ]
          : null,
    ),
    child: ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        children: [
          _windowAwareBlur(
            sigmaX: blurSigma,
            enabled: backdropBlur,
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: tintColor.withValues(alpha: tintOpacity),
                borderRadius: borderRadius,
              ),
              child: child,
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _GlassEdgePainter(borderRadius: borderRadius),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _GlassEdgePainter extends CustomPainter {
  const _GlassEdgePainter({required this.borderRadius});

  final BorderRadius borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 1 || size.height <= 1) return;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0x99ffffff),
          Color(0x4dffffff),
          Color(0x3372c8ed),
          Color(0x1affffff),
        ],
        stops: [0, .28, .72, 1],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(borderRadius.toRRect(rect.deflate(.5)), paint);
  }

  @override
  bool shouldRepaint(_GlassEdgePainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius;
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 1,
    width: double.infinity,
    child: CustomPaint(
      painter: _DashedLinePainter(color: _ink.withValues(alpha: .14)),
    ),
  );
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset((x + 3.5).clamp(0.0, size.width), size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _MacTrafficLights extends StatelessWidget {
  const _MacTrafficLights({
    required this.onMinimize,
    required this.onToggleMaximize,
  });

  final Future<void> Function() onMinimize;
  final Future<void> Function() onToggleMaximize;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _WindowControlButton(
        color: const Color(0xfffa6058),
        onPressed: () async => WindowManager.instance.close(),
      ),
      const SizedBox(width: 8),
      _WindowControlButton(
        color: const Color(0xfff5bd4f),
        onPressed: onMinimize,
      ),
      const SizedBox(width: 8),
      _WindowControlButton(
        color: const Color(0xff35c85a),
        onPressed: onToggleMaximize,
      ),
    ],
  );
}

class _SidebarProfile extends StatelessWidget {
  const _SidebarProfile({
    required this.businessName,
    required this.image,
    required this.subtitle,
    required this.onTap,
    required this.onTapDown,
  });

  final String businessName;
  final ImageProvider<Object>? image;
  final String subtitle;
  final VoidCallback onTap;
  final ValueChanged<TapDownDetails> onTapDown;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(4),
    child: Row(
      children: [
        _ProfileAvatar(image: image, framed: false),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText.raw(
                businessName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.3,
                ),
              ),
              if (subtitle.trim().isNotEmpty)
                AppText.raw(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        _SidebarProfileEditButton(onPressed: onTap, onTapDown: onTapDown),
      ],
    ),
  );
}

class _SidebarProfileEditButton extends StatefulWidget {
  const _SidebarProfileEditButton({
    required this.onPressed,
    required this.onTapDown,
  });

  final VoidCallback onPressed;
  final ValueChanged<TapDownDetails> onTapDown;

  @override
  State<_SidebarProfileEditButton> createState() =>
      _SidebarProfileEditButtonState();
}

class _SidebarProfileEditButtonState extends State<_SidebarProfileEditButton> {
  bool _highlighted = false;

  @override
  Widget build(BuildContext context) => _ButtonPop(
    child: Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTapDown: widget.onTapDown,
        onHighlightChanged: (highlighted) {
          setState(() => _highlighted = highlighted);
        },
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.edit_outlined,
            size: 18,
            color: _highlighted ? _blue : _ink,
          ),
        ),
      ),
    ),
  );
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.image,
    this.size = 52,
    this.framed = true,
  });

  final ImageProvider<Object>? image;
  final double size;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final imageSize = framed ? size - 10 : size;
    final radius = BorderRadius.circular(imageSize / 2);
    Widget fallbackImage() => const ColoredBox(
      color: Color(0xffe8f3f8),
      child: Center(
        child: AppText(
          'R',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xff354f60),
            fontSize: 23,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
    Widget buildImage() {
      if (image == null) return fallbackImage();
      return Image(
        image: image!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => fallbackImage(),
      );
    }

    final avatar = Container(
      width: imageSize,
      height: imageSize,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x3321425b),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
          BoxShadow(
            color: Color(0x227ec9e8),
            blurRadius: 14,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            buildImage(),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: image == null ? .1 : .2),
                        Colors.white.withValues(alpha: .035),
                        const Color(0xffbfe9ff).withValues(alpha: .07),
                      ],
                      stops: const [0, .42, 1],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (!framed) return avatar;
    return _FrostedSurface(
      borderRadius: BorderRadius.circular(18),
      tintColor: const Color(0xfff2faff),
      tintOpacity: .58,
      padding: const EdgeInsets.all(5),
      blurSigma: 18,
      prominentShadow: true,
      child: avatar,
    );
  }
}

class _WindowControlButton extends StatefulWidget {
  const _WindowControlButton({required this.color, required this.onPressed});

  final Color color;
  final Future<void> Function() onPressed;

  @override
  State<_WindowControlButton> createState() => _WindowControlButtonState();
}

class _WindowControlButtonState extends State<_WindowControlButton> {
  bool _hovered = false;
  bool _pressed = false;

  bool _safeSetState(VoidCallback callback) {
    if (!mounted) return false;
    final renderObject = context.findRenderObject();
    if (renderObject is RenderBox && !renderObject.hasSize) return false;
    setState(callback);
    return true;
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) {
      if (!_safeSetState(() => _hovered = true)) return;
    },
    onExit: (_) {
      if (!_safeSetState(() {
        _hovered = false;
        _pressed = false;
      })) {
        return;
      }
    },
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onPressed(),
        onTapDown: (_) {
          if (!_safeSetState(() => _pressed = true)) return;
        },
        onTapUp: (_) {
          if (!_safeSetState(() => _pressed = false)) return;
        },
        onTapCancel: () {
          if (!_safeSetState(() => _pressed = false)) return;
        },
        borderRadius: BorderRadius.circular(99),
        child: SizedBox(
          width: 21,
          height: 21,
          child: Center(
            child: AnimatedScale(
              scale: _pressed
                  ? 1.25
                  : _hovered
                  ? 1.12
                  : 1,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutBack,
              child: Container(
                width: 17,
                height: 17,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: .4)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SlideUpEntranceOrder {
  int _generation = 0;
  bool _scheduled = false;
  final List<(double, double, void Function(Duration))> _cards = [];

  void reset() {
    _generation++;
    _scheduled = false;
    _cards.clear();
  }

  void register(GlobalKey key, void Function(Duration delay) start) {
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (generation != _generation) return;
      final renderObject = key.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) return;
      final position = renderObject.localToGlobal(Offset.zero);
      _cards.add((position.dy, position.dx, start));
      if (_scheduled) return;
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (generation != _generation) return;
        _cards.sort((a, b) {
          final vertical = a.$1.compareTo(b.$1);
          return vertical != 0 ? vertical : a.$2.compareTo(b.$2);
        });
        var row = -1;
        var rowTop = 0.0;
        for (final card in _cards) {
          if (row < 0 || (card.$1 - rowTop).abs() > 20) {
            row++;
            rowTop = card.$1;
          }
          card.$3(
            Duration(
              milliseconds:
                  row.clamp(0, _slideUpMaxStaggerRows) *
                  _slideUpStaggerMilliseconds,
            ),
          );
        }
        _cards.clear();
      });
    });
  }
}

/// Canonical entrance for cards and pills; reuse this for consistent slide-up.
class _SlideUpEntrance extends StatefulWidget {
  const _SlideUpEntrance({required this.child, required this.order});

  final Widget child;
  final _SlideUpEntranceOrder order;

  @override
  State<_SlideUpEntrance> createState() => _SlideUpEntranceState();
}

class _SlideUpEntranceState extends State<_SlideUpEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _position;
  final GlobalKey _positionKey = GlobalKey();
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _slideUpDuration);
    final transition = CurvedAnimation(
      parent: _controller,
      curve: _slideUpCurve,
    );
    _position = Tween<Offset>(
      begin: const Offset(0, _slideUpDistance),
      end: Offset.zero,
    ).animate(transition);
    widget.order.register(_positionKey, (delay) {
      _delayTimer = Timer(delay, () {
        if (mounted) _controller.forward();
      });
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _position,
    child: KeyedSubtree(key: _positionKey, child: widget.child),
    builder: (context, child) =>
        Transform.translate(offset: _position.value, child: child),
  );
}

class _ButtonPop extends StatefulWidget {
  const _ButtonPop({
    required this.child,
    this.enabled = true,
    this.intensity = 1,
    this.normalizeScaleByWidth = false,
  });

  final Widget child;
  final bool enabled;
  final double intensity;
  final bool normalizeScaleByWidth;

  @override
  State<_ButtonPop> createState() => _ButtonPopState();
}

class _ButtonPopState extends State<_ButtonPop> {
  bool _hovered = false;
  bool _pressed = false;

  bool _hasUsableSize() {
    final renderObject = context.findRenderObject();
    return renderObject is RenderBox &&
        renderObject.hasSize &&
        !renderObject.size.isEmpty;
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) {
      if (!widget.enabled || !mounted || !_hasUsableSize()) return;
      setState(() => _hovered = true);
    },
    onExit: (_) {
      if (!mounted) return;
      final renderObject = context.findRenderObject();
      if (renderObject is RenderBox && !renderObject.hasSize) return;
      setState(() {
        _hovered = false;
        _pressed = false;
      });
    },
    child: Listener(
      onPointerDown: widget.enabled
          ? (_) {
              if (!mounted || !_hasUsableSize()) return;
              setState(() => _pressed = true);
            }
          : null,
      onPointerUp: widget.enabled
          ? (_) {
              if (!mounted) return;
              setState(() => _pressed = false);
            }
          : null,
      onPointerCancel: widget.enabled
          ? (_) {
              if (!mounted) return;
              setState(() => _pressed = false);
            }
          : null,
      child: AnimatedScale(
        scale: !widget.enabled
            ? 1
            : _pressed
            ? 1 - (.009 * widget.intensity)
            : _hovered
            ? 1 + (.0075 * widget.intensity)
            : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    ),
  );
}

class _PopIconButton extends StatelessWidget {
  const _PopIconButton({
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.style,
    this.visualDensity,
    this.constraints,
    this.padding,
  });

  final VoidCallback? onPressed;
  final Widget icon;
  final String? tooltip;
  final ButtonStyle? style;
  final VisualDensity? visualDensity;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => _ButtonPop(
    enabled: onPressed != null,
    child: IconButton(
      onPressed: onPressed,
      icon: icon,
      tooltip: tooltip == null ? null : localizeAppText(tooltip!),
      style: style,
      visualDensity: visualDensity,
      constraints: constraints,
      padding: padding,
    ),
  );
}

class _PopTextButton extends StatelessWidget {
  const _PopTextButton({required this.onPressed, required this.child});

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => _ButtonPop(
    enabled: onPressed != null,
    child: TextButton(onPressed: onPressed, child: child),
  );
}

class _PopFilledButton extends StatelessWidget {
  const _PopFilledButton({
    required this.onPressed,
    required this.child,
    this.style,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) => _ButtonPop(
    enabled: onPressed != null,
    child: FilledButton(onPressed: onPressed, style: style, child: child),
  );
}

class _LiquidIconBadge extends StatelessWidget {
  const _LiquidIconBadge({
    required this.icon,
    required this.size,
    required this.iconSize,
  });

  final IconData icon;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: ClipOval(
      child: _windowAwareBlur(
        sigmaX: 10,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: .68),
                Colors.white.withValues(alpha: .36),
              ],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1421425b),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Icon(icon, size: iconSize, color: const Color(0xff2d4656)),
          ),
        ),
      ),
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 42,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              AnimatedScale(
                scale: selected ? 1.08 : 1,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: Icon(icon, size: 21, color: selected ? _blue : _ink),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: AppText(
                  label,
                  style: const TextStyle(fontSize: 13).copyWith(
                    color: selected ? _ink : _muted,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PocketRActionButton extends StatefulWidget {
  const _PocketRActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.blue = false,
    this.danger = false,
    this.foregroundColor,
    this.labelOffset = -4,
    this.fixedWidth,
    this.compact = false,
    this.expand = false,
  });

  final IconData? icon;
  final String label;
  final VoidCallback onPressed;
  final bool blue;
  final bool danger;
  final Color? foregroundColor;
  final double labelOffset;
  final double? fixedWidth;
  final bool compact;
  final bool expand;

  @override
  State<_PocketRActionButton> createState() => _PocketRActionButtonState();
}

class _PocketRActionButtonState extends State<_PocketRActionButton> {
  @override
  Widget build(BuildContext context) => _ButtonPop(
    child: _PillFocusIndicator(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          boxShadow: [
            BoxShadow(
              color: widget.blue
                  ? _blue.withValues(alpha: .2)
                  : const Color(0x1421425b),
              blurRadius: widget.blue ? 16 : 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: _windowAwareBlur(
            sigmaX: 18,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: widget.blue
                      ? [
                          const Color(0xff75bdff).withValues(alpha: .82),
                          const Color(0xff378eea).withValues(alpha: .76),
                          const Color(0xff2478e5).withValues(alpha: .8),
                        ]
                      : widget.danger
                      ? [const Color(0xfff06f68), const Color(0xffdc4b45)]
                      : [
                          Colors.white.withValues(alpha: .62),
                          const Color(0xfff5faff).withValues(alpha: .58),
                        ],
                ),
                border: widget.blue || widget.danger
                    ? null
                    : Border.all(color: Colors.white.withValues(alpha: .62)),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(99),
                  splashFactory: NoSplash.splashFactory,
                  overlayColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  onTap: widget.onPressed,
                  child: SizedBox(
                    width: widget.expand ? double.infinity : widget.fixedWidth,
                    height: widget.compact ? 30 : 36,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: widget.compact ? 11 : 13,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (widget.icon != null) ...[
                                Icon(
                                  widget.icon,
                                  size: 17,
                                  color:
                                      widget.foregroundColor ??
                                      (widget.blue || widget.danger
                                          ? Colors.white
                                          : _blue),
                                ),
                                const SizedBox(width: 7),
                              ],
                              Transform.translate(
                                offset: Offset(0, widget.labelOffset),
                                child: AppText(
                                  widget.label,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color:
                                        widget.foregroundColor ??
                                        (widget.blue || widget.danger
                                            ? Colors.white
                                            : _ink),
                                    fontSize: widget.compact ? 11 : 12,
                                    fontWeight: widget.compact
                                        ? FontWeight.w600
                                        : FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _HppImportAction extends StatelessWidget {
  const _HppImportAction({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      splashFactory: NoSplash.splashFactory,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: primary
              ? _blue.withValues(alpha: .1)
              : Colors.white.withValues(alpha: .42),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: primary
                ? _blue.withValues(alpha: .2)
                : Colors.white.withValues(alpha: .64),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: primary
                    ? _blue.withValues(alpha: .14)
                    : Colors.white.withValues(alpha: .7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: _blue, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    title,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  AppText(
                    detail,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: _muted.withValues(alpha: .8),
              size: 20,
            ),
          ],
        ),
      ),
    ),
  );
}

class _SalesPlatformCard extends StatelessWidget {
  const _SalesPlatformCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.available,
    required this.accent,
    required this.action,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool available;
  final Color accent;
  final Widget action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .38),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withValues(alpha: .68)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0c21425b),
          blurRadius: 10,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: accent, size: 21),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: (available ? _green : _muted).withValues(alpha: .1),
                borderRadius: BorderRadius.circular(99),
              ),
              child: AppText(
                available ? 'TERSEDIA' : 'SEGERA HADIR',
                style: TextStyle(
                  color: available ? _green : _muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .35,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        AppText(
          title,
          style: const TextStyle(
            color: _ink,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        AppText(
          description,
          style: const TextStyle(color: _muted, fontSize: 11, height: 1.4),
        ),
        const Spacer(),
        const SizedBox(height: 12),
        action,
      ],
    ),
  );
}

class _ImportDialogPill extends StatefulWidget {
  const _ImportDialogPill({
    required this.label,
    required this.onPressed,
    this.icon,
    this.blue = false,
    this.danger = false,
    this.labelOffset = -4,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool blue;
  final bool danger;
  final double labelOffset;

  @override
  State<_ImportDialogPill> createState() => _ImportDialogPillState();
}

class _ImportDialogPillState extends State<_ImportDialogPill> {
  @override
  Widget build(BuildContext context) => _ButtonPop(
    enabled: widget.onPressed != null,
    child: _PillFocusIndicator(
      child: Opacity(
        opacity: widget.onPressed == null ? .5 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            boxShadow: [
              BoxShadow(
                color: widget.blue
                    ? _blue.withValues(alpha: .2)
                    : const Color(0x1421425b),
                blurRadius: widget.blue ? 16 : 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: _windowAwareBlur(
              sigmaX: 18,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: widget.blue
                        ? [
                            const Color(0xff75bdff).withValues(alpha: .82),
                            const Color(0xff378eea).withValues(alpha: .76),
                            const Color(0xff2478e5).withValues(alpha: .8),
                          ]
                        : widget.danger
                        ? [const Color(0xfff06f68), const Color(0xffdc4b45)]
                        : [
                            Colors.white.withValues(alpha: .62),
                            const Color(0xfff5faff).withValues(alpha: .58),
                          ],
                  ),
                  border: widget.blue || widget.danger
                      ? null
                      : Border.all(color: Colors.white.withValues(alpha: .62)),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(99),
                    splashFactory: NoSplash.splashFactory,
                    overlayColor: const WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                    onTap: widget.onPressed,
                    child: SizedBox(
                      height: 36,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.icon != null) ...[
                              Icon(
                                widget.icon,
                                size: 17,
                                color: widget.blue || widget.danger
                                    ? Colors.white
                                    : _blue,
                              ),
                              const SizedBox(width: 7),
                            ],
                            Transform.translate(
                              offset: Offset(0, widget.labelOffset),
                              child: AppText(
                                widget.label,
                                style: TextStyle(
                                  color: widget.blue || widget.danger
                                      ? Colors.white
                                      : _ink,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _LiquidGlassTabBar extends StatelessWidget {
  const _LiquidGlassTabBar({
    required this.tabs,
    required this.selectedValue,
    required this.onSelected,
    this.equalWidths = false,
  });

  final List<(String, String)> tabs;
  final String selectedValue;
  final ValueChanged<String> onSelected;
  final bool equalWidths;

  @override
  Widget build(BuildContext context) {
    final tabs = this.tabs;
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    final measuredWidths = [
      for (final tab in tabs)
        (TextPainter(
              text: TextSpan(
                text: tab.$2,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              textDirection: textDirection,
              textScaler: textScaler,
            )..layout()).width +
            28,
    ];
    final widths = equalWidths
        ? List<double>.filled(
            measuredWidths.length,
            measuredWidths.reduce((a, b) => a > b ? a : b),
          )
        : measuredWidths;
    final totalWidth = widths.fold<double>(0, (sum, width) => sum + width);
    final selectedIndex = tabs.indexWhere((tab) => tab.$1 == selectedValue);
    var selectedLeft = 3.0;
    if (selectedIndex > 0) {
      for (var index = 0; index < selectedIndex; index++) {
        selectedLeft += widths[index];
      }
    }
    final selectedWidth = selectedIndex < 0 ? 0.0 : widths[selectedIndex];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: totalWidth + 6,
        height: 38,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1421425b),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: _windowAwareBlur(
              sigmaX: 18,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: .72),
                      const Color(0xffd8edf4).withValues(alpha: .72),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .56),
                  ),
                ),
                child: Stack(
                  children: [
                    if (selectedIndex >= 0)
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 480),
                        curve: Curves.easeInOutCubicEmphasized,
                        left: selectedLeft,
                        top: 3,
                        bottom: 3,
                        width: selectedWidth,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: _windowAwareBlur(
                            sigmaX: 12,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(99),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.white.withValues(alpha: .66),
                                    const Color(0xfff5faff)
                                        .withValues(alpha: .6),
                                  ],
                                ),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: .56),
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x1821425b),
                                    blurRadius: 7,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Row(
                        children: [
                          for (var index = 0; index < tabs.length; index++)
                            SizedBox(
                              width: widths[index],
                              height: double.infinity,
                              child: Material(
                                color: Colors.transparent,
                                child: _PillFocusIndicator(
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(99),
                                    splashFactory: NoSplash.splashFactory,
                                    overlayColor: const WidgetStatePropertyAll(
                                      Colors.transparent,
                                    ),
                                    onTap: () => onSelected(tabs[index].$1),
                                    child: Align(
                                      alignment: Alignment.center,
                                      child: Transform.translate(
                                        offset: const Offset(0, -1),
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: AppText(
                                            tabs[index].$2,
                                            maxLines: 1,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: const Color(0xff172d39),
                                              fontSize: 12,
                                              fontWeight: selectedIndex == index
                                                  ? FontWeight.w600
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedMonthArrow extends StatefulWidget {
  const _AnimatedMonthArrow({
    required this.icon,
    required this.onPressed,
    this.pop = true,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool pop;

  @override
  State<_AnimatedMonthArrow> createState() => _AnimatedMonthArrowState();
}

class _AnimatedMonthArrowState extends State<_AnimatedMonthArrow> {
  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: 30,
      height: 30,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          onTap: widget.onPressed,
          child: Center(child: Icon(widget.icon, size: 19, color: _blue)),
        ),
      ),
    );
    return widget.pop ? _ButtonPop(child: button) : button;
  }
}

class _PocketRMonthGrid extends StatelessWidget {
  const _PocketRMonthGrid({
    required this.year,
    required this.selectedMonth,
    required this.columns,
    required this.onSelected,
  });

  final int year;
  final int selectedMonth;
  final ValueChanged<int> onSelected;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: columns,
      mainAxisSpacing: 7,
      crossAxisSpacing: 7,
      childAspectRatio: columns == 2 ? 2.8 : 2.35,
      children: [
        for (var month = 1; month <= 12; month++)
          _MonthChoicePill(
            label: monthLabel('$year-${month.toString().padLeft(2, '0')}')
                .split(' ')
                .first,
            selected: selectedMonth == month,
            isCurrentMonth: year == today.year && month == today.month,
            onTap: () => onSelected(month),
          ),
      ],
    );
  }
}

class _MonthChoicePill extends StatelessWidget {
  const _MonthChoicePill({
    required this.label,
    required this.selected,
    required this.isCurrentMonth,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool isCurrentMonth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _ButtonPop(
    child: _FrostedSurface(
      borderRadius: BorderRadius.circular(99),
      tintColor: selected ? Colors.white : const Color(0xffd8edf4),
      tintOpacity: selected ? .78 : .54,
      padding: EdgeInsets.zero,
      blurSigma: 12,
      shadow: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          onTap: onTap,
          child: Stack(
            children: [
              Center(
                child: AppText(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? _blue : _ink,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              if (isCurrentMonth)
                Positioned(
                  top: 6,
                  left: 0,
                  right: 0,
                  child: Container(
                    alignment: Alignment.center,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: _blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _NavMenu extends StatelessWidget {
  const _NavMenu({
    required this.items,
    required this.utilityItems,
    required this.calculatorButtonKey,
    required this.selectedValue,
    required this.onSelected,
    required this.onUtilitySelected,
  });

  final List<(String, String, IconData)> items;
  final List<(String, String, IconData)> utilityItems;
  final GlobalKey calculatorButtonKey;
  final String selectedValue;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onUtilitySelected;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = items.indexWhere((item) => item.$1 == selectedValue);
    return Column(
      children: [
        SizedBox(
          height: items.length * 42,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (selectedIndex >= 0)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 520),
                  curve: Curves.easeInOutCubicEmphasized,
                  top: selectedIndex * 42 - 1,
                  left: 0,
                  right: 0,
                  height: 44,
                  child: _FrostedSurface(
                    borderRadius: BorderRadius.circular(22),
                    tintColor: const Color(0xfff2faff),
                    tintOpacity: .62,
                    blurSigma: 18,
                    child: const SizedBox.expand(),
                  ),
                ),
              Column(
                children: [
                  for (final item in items)
                    _NavItem(
                      label: item.$2,
                      icon: item.$3,
                      selected: selectedValue == item.$1,
                      onTap: () => onSelected(item.$1),
                    ),
                ],
              ),
            ],
          ),
        ),
        const Spacer(),
        if (utilityItems.isNotEmpty) ...[
          for (final item in utilityItems)
            _SidebarUtilityItem(
              key: item.$1 == 'calculator' ? calculatorButtonKey : null,
              label: item.$2,
              icon: item.$3,
              onTap: () => onUtilitySelected(item.$1),
            ),
        ],
      ],
    );
  }
}

class _SidebarUtilityItem extends StatelessWidget {
  const _SidebarUtilityItem({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: SizedBox(
      height: 36,
      child: _ButtonPop(
        intensity: .45,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(icon, size: 17, color: _muted),
                  const SizedBox(width: 9),
                  Expanded(
                    child: AppText(
                      label,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _CalculatorWindow extends StatefulWidget {
  const _CalculatorWindow({
    required this.onClose,
    required this.onDragStart,
    required this.onDrag,
    required this.onDragEnd,
  });

  final VoidCallback onClose;
  final ValueChanged<Offset> onDragStart;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;

  @override
  State<_CalculatorWindow> createState() => _CalculatorWindowState();
}

class _CalculatorWindowState extends State<_CalculatorWindow> {
  String _expression = '';
  String? _preview;
  bool _justEvaluated = false;
  bool _dragging = false;
  int? _dragPointer;

  void _startDragging(PointerDownEvent event) {
    if (_dragPointer != null) return;
    _dragPointer = event.pointer;
    widget.onDragStart(event.position);
  }

  void _updateDragging(PointerMoveEvent event) {
    if (_dragPointer != event.pointer) return;
    if (!_dragging) setState(() => _dragging = true);
    widget.onDrag(event.position);
  }

  void _finishDragging(PointerEvent event) {
    if (_dragPointer != event.pointer) return;
    _dragPointer = null;
    if (_dragging) setState(() => _dragging = false);
    widget.onDragEnd();
  }

  static const _keyRows = [
    ['AC', '⌫', '%', '÷'],
    ['7', '8', '9', '×'],
    ['4', '5', '6', '-'],
    ['1', '2', '3', '+'],
    ['0', '.', '='],
  ];

  void _press(String key) {
    setState(() {
      final previousPreview = _preview;
      var preservePreviewWhenIncomplete = false;
      if (key == 'AC') {
        _expression = '';
        _preview = null;
        _justEvaluated = false;
        return;
      }
      if (key == '⌫') {
        if (_expression.isNotEmpty) {
          _expression = _expression.substring(0, _expression.length - 1);
        }
        _justEvaluated = false;
      } else if (key == '=') {
        try {
          _expression = _formatCalculatorNumber(
            _CalculatorExpressionParser(_expression).parse(),
          );
          _justEvaluated = true;
          _preview = null;
          return;
        } on FormatException {
          _preview = 'Input belum lengkap';
          return;
        } on UnsupportedError {
          _preview = 'Tidak bisa dibagi nol';
          return;
        }
      } else {
        final value = switch (key) {
          '×' => '*',
          '÷' => '/',
          _ => key,
        };
        if (_justEvaluated &&
            (RegExp(r'^\d$').hasMatch(key) || key == '.' || key == '(')) {
          _expression = '';
        }
        _justEvaluated = false;
        if ('+-*/'.contains(value)) {
          preservePreviewWhenIncomplete = true;
          final endsWithOperator =
              _expression.isNotEmpty &&
              '+-*/'.contains(_expression[_expression.length - 1]);
          if (value == '-' &&
              (_expression.isEmpty ||
                  endsWithOperator ||
                  _expression.endsWith('('))) {
            _expression += value;
          } else if (endsWithOperator) {
            _expression =
                _expression.substring(0, _expression.length - 1) + value;
          } else {
            _expression += value;
          }
        } else {
          _expression += value;
        }
      }
      final preview = _calculatePreview();
      _preview =
          preview ?? (preservePreviewWhenIncomplete ? previousPreview : null);
    });
  }

  String? _calculatePreview() {
    if (_expression.isEmpty) return null;
    try {
      return _formatCalculatorNumber(
        _CalculatorExpressionParser(_expression).parse(),
      );
    } on FormatException {
      return null;
    } on UnsupportedError {
      return 'Tidak bisa dibagi nol';
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 320,
    child: _FrostedSurface(
      borderRadius: BorderRadius.circular(24),
      tintColor: const Color(0xffe4f3fa),
      tintOpacity: .86,
      blurSigma: 24,
      prominentShadow: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 28,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: MouseRegion(
                    cursor: _dragging
                        ? SystemMouseCursors.grabbing
                        : SystemMouseCursors.grab,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _startDragging,
                      onPointerMove: _updateDragging,
                      onPointerUp: _finishDragging,
                      onPointerCancel: _finishDragging,
                      child: Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: _muted.withValues(alpha: .42),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 11,
                  right: 0,
                  child: Tooltip(
                    message: localizeAppText('Tutup kalkulator'),
                    child: _ButtonPop(
                      intensity: .35,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: widget.onClose,
                          child: _FrostedSurface(
                            borderRadius: BorderRadius.circular(99),
                            tintColor: const Color(0xffedf7fb),
                            tintOpacity: .88,
                            padding: EdgeInsets.zero,
                            shadow: true,
                            blurSigma: 12,
                            child: const SizedBox(
                              width: 22,
                              height: 22,
                              child: Icon(
                                Icons.close_rounded,
                                size: 15,
                                color: _muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .48),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: .58)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: AppText(
                        _expression.isEmpty
                            ? '0'
                            : _expression
                                  .replaceAll('*', '×')
                                  .replaceAll('/', '÷'),
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 23,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_preview != null)
                  AppText(
                    _preview!,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final row in _keyRows) ...[
            Row(
              children: [
                for (var index = 0; index < row.length; index++) ...[
                  if (index > 0) const SizedBox(width: 8),
                  Expanded(
                    flex: row == _keyRows.last && row[index] == '0' ? 2 : 1,
                    child: _CalculatorKey(
                      label: row[index],
                      highlighted:
                          '+-×÷%='.contains(row[index]) || row[index] == 'AC',
                      onPressed: () => _press(row[index]),
                    ),
                  ),
                ],
              ],
            ),
            if (row != _keyRows.last) const SizedBox(height: 8),
          ],
        ],
      ),
    ),
  );
}

class _CalculatorKey extends StatelessWidget {
  const _CalculatorKey({
    required this.label,
    required this.highlighted,
    required this.onPressed,
  });

  final String label;
  final bool highlighted;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 46,
    child: _ButtonPop(
      intensity: .35,
      child: Material(
        color: highlighted
            ? _blue.withValues(alpha: .14)
            : Colors.white.withValues(alpha: .38),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Center(
            child: AppText(
              label,
              style: TextStyle(
                color: highlighted ? _blue : _ink,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _CalculatorExpressionParser {
  _CalculatorExpressionParser(this.source);

  final String source;
  int _index = 0;

  double parse() {
    final result = _sum();
    if (_index != source.length) {
      throw const FormatException('Ekspresi tidak valid.');
    }
    if (!result.isFinite) throw UnsupportedError('Hasil tidak valid.');
    return result;
  }

  double _sum() {
    var value = _product();
    while (_index < source.length) {
      final operator = source[_index];
      if (operator != '+' && operator != '-') break;
      _index++;
      final next = _product();
      value = operator == '+' ? value + next : value - next;
    }
    return value;
  }

  double _product() {
    var value = _factor();
    while (_index < source.length) {
      final operator = source[_index];
      if (operator != '*' && operator != '/') break;
      _index++;
      final next = _factor();
      if (operator == '/' && next == 0) {
        throw UnsupportedError('Tidak bisa dibagi nol.');
      }
      value = operator == '*' ? value * next : value / next;
    }
    return value;
  }

  double _factor() {
    if (_index >= source.length) {
      throw const FormatException('Ekspresi belum lengkap.');
    }
    final sign = source[_index] == '-' || source[_index] == '+'
        ? source[_index++]
        : null;
    final value = _index < source.length && source[_index] == '('
        ? _parenthesized()
        : _number();
    var result = sign == '-' ? -value : value;
    while (_index < source.length && source[_index] == '%') {
      _index++;
      result /= 100;
    }
    return result;
  }

  double _parenthesized() {
    _index++;
    final value = _sum();
    if (_index >= source.length || source[_index] != ')') {
      throw const FormatException('Kurung belum ditutup.');
    }
    _index++;
    return value;
  }

  double _number() {
    final start = _index;
    var hasDigit = false;
    while (_index < source.length &&
        (source[_index].contains(RegExp(r'\d')) || source[_index] == '.')) {
      if (source[_index].contains(RegExp(r'\d'))) hasDigit = true;
      _index++;
    }
    if (!hasDigit) throw const FormatException('Angka tidak valid.');
    final value = double.tryParse(source.substring(start, _index));
    if (value == null) throw const FormatException('Angka tidak valid.');
    return value;
  }
}

String _formatCalculatorNumber(double value) {
  if (!value.isFinite) throw UnsupportedError('Hasil tidak valid.');
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsPrecision(10).replaceFirst(RegExp(r'\.?0+$'), '');
}

class _Kpi {
  const _Kpi(this.title, this.value, this.detail, this.icon, this.color);
  final String title;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.detail,
    this.centerTitle = false,
  });
  final String title;
  final String detail;
  final bool centerTitle;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(
      vertical: centerTitle ? 16 : 22,
      horizontal: 12,
    ),
    decoration: BoxDecoration(
      border: Border.all(
        color: _ink.withValues(alpha: .13),
        style: BorderStyle.solid,
      ),
      borderRadius: BorderRadius.circular(17),
      color: Colors.white.withValues(alpha: .2),
    ),
    child: Column(
      children: [
        AppText(
          title,
          textAlign: centerTitle ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: _ink,
            fontSize: centerTitle ? 13.5 : null,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        AppText(
          detail,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted),
        ),
      ],
    ),
  );
}

class _StockDialogResult {
  const _StockDialogResult({required this.productId, required this.stock});

  final String productId;
  final StockData stock;
}

class _StockEditIconButton extends StatefulWidget {
  const _StockEditIconButton({required this.onPressed});

  final Future<void> Function() onPressed;

  @override
  State<_StockEditIconButton> createState() => _StockEditIconButtonState();
}

class _StockEditIconButtonState extends State<_StockEditIconButton> {
  bool _highlighted = false;
  bool _editorOpen = false;

  Future<void> _openEditor() async {
    setState(() => _editorOpen = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _editorOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) => _ButtonPop(
    child: Tooltip(
      message: localizeAppText('Edit stok'),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onHighlightChanged: (value) {
              if (!mounted) return;
              final renderObject = context.findRenderObject();
              if (renderObject is RenderBox && !renderObject.hasSize) return;
              setState(() => _highlighted = value);
            },
            onTap: _openEditor,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _highlighted || _editorOpen
                    ? _blue.withValues(alpha: .12)
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.edit_outlined,
                size: 16,
                color: _highlighted || _editorOpen ? _blue : _ink,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _StockProductSummary {
  const _StockProductSummary({
    required this.product,
    required this.balances,
    required this.total,
  });

  final Product product;
  final List<MapEntry<String, double>> balances;
  final double total;
}

class _StockProductsGrid extends StatefulWidget {
  const _StockProductsGrid({required this.products, required this.onEdit});

  final List<_StockProductSummary> products;
  final ValueChanged<Product> onEdit;

  @override
  State<_StockProductsGrid> createState() => _StockProductsGridState();
}

class _StockProductsGridState extends State<_StockProductsGrid> {
  final _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 900
          ? 5
          : constraints.maxWidth >= 500
          ? 2
          : 1;
      final pageSize = columns * 3;
      final pageCount = (widget.products.length / pageSize).ceil();
      final page = pageCount == 0 ? 0 : _currentPage.clamp(0, pageCount - 1);
      if (page != _currentPage) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_pageController.hasClients) return;
          _pageController.jumpToPage(page);
          setState(() => _currentPage = page);
        });
      }
      const tileHeight = 224.0;
      const rowSpacing = 9.0;
      final gridHeight = tileHeight * 3 + rowSpacing * 2;
      return Column(
        children: [
          SizedBox(
            height: gridHeight,
            child: PageView.builder(
              controller: _pageController,
              itemCount: pageCount,
              onPageChanged: (index) => setState(() => _currentPage = index),
              itemBuilder: (context, pageIndex) {
                final start = pageIndex * pageSize;
                final end = (start + pageSize).clamp(0, widget.products.length);
                final pageProducts = widget.products.sublist(start, end);
                return GridView.builder(
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: pageProducts.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: tileHeight,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: rowSpacing,
                  ),
                  itemBuilder: (context, index) => _StockProductTile(
                    summary: pageProducts[index],
                    onEdit: () => widget.onEdit(pageProducts[index].product),
                  ),
                );
              },
            ),
          ),
          if (pageCount > 1) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _PopIconButton(
                  tooltip: localizeAppText('Halaman sebelumnya'),
                  onPressed: page > 0
                      ? () => _pageController.previousPage(
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeInOutCubic,
                        )
                      : null,
                  style: IconButton.styleFrom(
                    foregroundColor: page > 0 ? _blue : _muted,
                    backgroundColor: Colors.white.withValues(alpha: .38),
                    minimumSize: const Size(30, 30),
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(Icons.chevron_left, size: 19),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: AppText(
                    'Halaman ${page + 1} dari $pageCount',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _PopIconButton(
                  tooltip: localizeAppText('Halaman berikutnya'),
                  onPressed: page + 1 < pageCount
                      ? () => _pageController.nextPage(
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeInOutCubic,
                        )
                      : null,
                  style: IconButton.styleFrom(
                    foregroundColor: page + 1 < pageCount ? _blue : _muted,
                    backgroundColor: Colors.white.withValues(alpha: .38),
                    minimumSize: const Size(30, 30),
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(Icons.chevron_right, size: 19),
                ),
              ],
            ),
          ],
        ],
      );
    },
  );
}

class _StockProductTile extends StatelessWidget {
  const _StockProductTile({required this.summary, required this.onEdit});

  final _StockProductSummary summary;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    bool isLowStock(num quantity) => quantity <= 5;
    final sortedBalances = [...summary.balances]
      ..sort((a, b) => a.value.compareTo(b.value));
    final hasColorRows = sortedBalances.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .44),
        border: Border.all(color: _ink.withValues(alpha: .09)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AppText.raw(
                  summary.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 3),
              _StockEditIconButton(onPressed: () async => onEdit()),
            ],
          ),
          const SizedBox(height: 5),
          Divider(height: 1, thickness: 1, color: _ink.withValues(alpha: .08)),
          const SizedBox(height: 4),
          if (hasColorRows)
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      children: [
                        const Expanded(
                          child: AppText(
                            'VARIAN',
                            style: TextStyle(
                              color: _muted,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: .35,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 70,
                          child: AppText(
                            'STOK',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _muted,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: .35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < sortedBalances.length;
                            index++
                          )
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: AppText(
                                          sortedBalances[index].key.isEmpty
                                              ? 'Tanpa warna'
                                              : sortedBalances[index].key,
                                          translate:
                                              sortedBalances[index].key.isEmpty,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: _ink,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 70,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                (isLowStock(
                                                          sortedBalances[index]
                                                              .value,
                                                        )
                                                        ? _red
                                                        : _ink)
                                                    .withValues(alpha: .1),
                                            borderRadius: BorderRadius.circular(
                                              7,
                                            ),
                                          ),
                                          child: AppText(
                                            '${formatNumber(sortedBalances[index].value)} pcs',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color:
                                                  isLowStock(
                                                    sortedBalances[index].value,
                                                  )
                                                  ? _red
                                                  : _ink,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (index < sortedBalances.length - 1)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 2,
                                        bottom: 1,
                                      ),
                                      child: Divider(
                                        height: 1,
                                        thickness: 1,
                                        color: _ink.withValues(alpha: .06),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (sortedBalances.length > 7)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.keyboard_double_arrow_down_rounded,
                        size: 15,
                        color: _muted.withValues(alpha: .75),
                      ),
                    ),
                ],
              ),
            )
          else
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: (isLowStock(summary.total) ? _red : _muted)
                        .withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: AppText(
                    '${formatNumber(summary.total)} pcs',
                    style: TextStyle(
                      color: isLowStock(summary.total) ? _red : _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StockDialog extends StatefulWidget {
  const _StockDialog({
    required this.products,
    required this.initialProduct,
    required this.onSaveAndAdd,
    this.editCurrentBalance = false,
    this.initialBalances = const {},
  });

  final List<Product> products;
  final Product initialProduct;
  final Future<void> Function(_StockDialogResult result) onSaveAndAdd;
  final bool editCurrentBalance;
  final Map<String, double> initialBalances;

  @override
  State<_StockDialog> createState() => _StockDialogState();
}

class _StockDialogState extends State<_StockDialog> {
  int get _rowCount =>
      _availableColors.length > 6 ? _availableColors.length : 6;

  final _formKey = GlobalKey<FormState>();
  late List<TextEditingController> _quantities;
  late Product _selectedProduct;
  late List<String?> _selectedColors;
  late String _date;
  bool _saving = false;
  bool _emptyBulkError = false;

  bool get _isFirst => _selectedProduct.stock == null;
  StockData? get _initial => _selectedProduct.stock;

  @override
  void initState() {
    super.initState();
    _selectedProduct = widget.initialProduct;
    _quantities = List.generate(_rowCount, (_) => TextEditingController());
    _selectedColors = _defaultSelectedColors();
    if (widget.editCurrentBalance) {
      final colors = _availableColors;
      for (var index = 0; index < _rowCount && index < colors.length; index++) {
        _quantities[index].text = _formatStockInput(
          _balanceForColor(colors[index]),
        );
      }
    }
    _date = DateTime.now().toIso8601String().substring(0, 10);
  }

  List<String?> _defaultSelectedColors() {
    final colors = _availableColors;
    return List.generate(
      _rowCount,
      (index) => colors.isEmpty
          ? ''
          : index < colors.length
          ? colors[index]
          : null,
    );
  }

  List<String> get _availableColors => {
    ..._selectedProduct.colors,
    if (widget.editCurrentBalance) ...widget.initialBalances.keys,
  }.where((color) => color.isNotEmpty).toList();

  void _resizeQuantityControllers() {
    while (_quantities.length < _rowCount) {
      _quantities.add(TextEditingController());
    }
    while (_quantities.length > _rowCount) {
      _quantities.removeLast().dispose();
    }
  }

  double _balanceForColor(String? color) =>
      widget.initialBalances[color ?? ''] ?? 0;

  double _quantityAt(int index) => _parseDecimal(_quantities[index].text);

  String _formatStockInput(double value) {
    final raw = value.toString();
    return raw.endsWith('.0')
        ? raw.substring(0, raw.length - 2)
        : raw.replaceAll('.', ',');
  }

  void _selectProduct(String? productId) {
    final product = widget.products
        .where((item) => item.id == productId)
        .firstOrNull;
    if (product == null) return;
    setState(() {
      _selectedProduct = product;
      _resizeQuantityControllers();
      _selectedColors = _defaultSelectedColors();
      for (final quantity in _quantities) {
        quantity.clear();
      }
    });
  }

  void _selectColor(int index, String? color) {
    setState(() {
      _selectedColors[index] = color;
      if (widget.editCurrentBalance && color != null) {
        _quantities[index].text = _formatStockInput(_balanceForColor(color));
      }
    });
  }

  Future<void> _submit({required bool addAnother}) async {
    final activeRows = [
      for (var index = 0; index < _rowCount; index++)
        if (_quantities[index].text.trim().isNotEmpty) index,
    ];
    if (activeRows.isEmpty) {
      setState(() => _emptyBulkError = true);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final entries = <StockEntry>[];
    for (final index in activeRows) {
      final color = _selectedColors[index];
      if (color == null) continue;
      final quantity = _quantityAt(index);
      final currentBalance = _balanceForColor(color);
      final stockChange = widget.editCurrentBalance
          ? quantity - currentBalance
          : quantity;
      if (stockChange == 0) continue;
      entries.add(
        StockEntry(
          date: _date,
          qty: stockChange,
          note: widget.editCurrentBalance
              ? 'Penyesuaian stok'
              : _isFirst
              ? 'Stok awal'
              : 'Tambah stok',
          color: color,
        ),
      );
    }
    if (entries.isEmpty && widget.editCurrentBalance) {
      Navigator.pop(context);
      return;
    }
    final result = _StockDialogResult(
      productId: _selectedProduct.id,
      stock: StockData(log: [...?_initial?.log, ...entries]),
    );
    if (!addAnother) {
      Navigator.pop(context, result);
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.onSaveAndAdd(result);
      if (!mounted) return;
      for (final quantity in _quantities) {
        quantity.clear();
      }
      setState(() {
        _selectedColors = _defaultSelectedColors();
        _emptyBulkError = false;
      });
      setState(() => _saving = false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      rethrow;
    }
  }

  Widget _quantityField(int index) => _textField(
    _quantities[index],
    index > 0
        ? null
        : widget.editCurrentBalance
        ? 'Stok'
        : 'Jumlah',
    inputVerticalPadding: 0,
    textOffset: const Offset(0, 7),
    keyboard: const TextInputType.numberWithOptions(decimal: true),
    positiveDecimalOnly: true,
    suffixText: 'pcs',
    errorBuilder: (context, errorText) => Transform.translate(
      offset: const Offset(0, -13),
      child: AppText(
        errorText,
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
          fontSize: 12,
        ),
      ),
    ),
    validator: (value) {
      if (value == null || value.trim().isEmpty) return null;
      final quantity = _parseDecimal(value);
      if (_selectedColors[index] == null) return 'Warna wajib diisi';
      if (List.generate(_rowCount, (otherIndex) => otherIndex).any(
        (otherIndex) =>
            otherIndex != index &&
            _selectedColors[otherIndex] == _selectedColors[index] &&
            _selectedColors[index]?.isNotEmpty == true,
      )) {
        return 'Warna sudah dipilih';
      }
      if (!widget.editCurrentBalance && quantity < 0) {
        return 'Jumlah tidak boleh negatif';
      }
      if (!widget.editCurrentBalance && !_isFirst && quantity == 0) {
        return 'Jumlah tidak boleh 0';
      }
      return null;
    },
  );

  Widget _colorDropdown(int index) => _stockDropdown(
    label: index == 0 ? 'Warna' : null,
    value: _selectedColors[index] ?? '',
    options: [
      for (final color in _availableColors)
        if (color == _selectedColors[index] ||
            !_selectedColors.asMap().entries.any(
              (entry) => entry.key != index && entry.value == color,
            ))
          (color, color),
    ],
    onChanged: (value) => _selectColor(index, value),
  );

  Widget _bulkRow(int index) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: _quantityField(index)),
      if (_availableColors.isNotEmpty) ...[
        const SizedBox(width: 10),
        Expanded(child: _colorDropdown(index)),
      ],
    ],
  );

  @override
  void dispose() {
    for (final quantity in _quantities) {
      quantity.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 480, maxHeight: 680),
    child: Material(
      color: Colors.transparent,
      child: _FrostedSurface(
        borderRadius: BorderRadius.circular(26),
        tintColor: _popupTintColor,
        tintOpacity: _popupTintOpacity,
        padding: const EdgeInsets.all(24),
        blurSigma: 18,
        prominentShadow: true,
        child: Form(
          key: _formKey,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context)
                .copyWith(scrollbars: false),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppText(
                          widget.editCurrentBalance
                              ? 'Edit stok'
                              : _isFirst
                              ? 'Aktifkan stok'
                              : 'Tambah stok',
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      _PopIconButton(
                        tooltip: localizeAppText('Tutup'),
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        style: IconButton.styleFrom(
                          foregroundColor: _muted,
                          backgroundColor: Colors.white.withValues(alpha: .44),
                          minimumSize: const Size(32, 32),
                          padding: EdgeInsets.zero,
                        ),
                        icon: const Icon(Icons.close, size: 17),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (!widget.editCurrentBalance) ...[
                    _stockDropdown(
                      label: 'Produk',
                      value: _selectedProduct.id,
                      options: [
                        for (final product in widget.products)
                          (product.id, product.name),
                      ],
                      onChanged: _selectProduct,
                    ),
                    const SizedBox(height: 10),
                  ],
                  for (var index = 0; index < _rowCount; index++) ...[
                    if (index > 0) const SizedBox(height: 8),
                    _bulkRow(index),
                  ],
                  if (_emptyBulkError) ...[
                    const SizedBox(height: 6),
                    const AppText(
                      'Isi minimal satu jumlah stok.',
                      style: TextStyle(
                        color: _red,
                        fontSize: 12,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                  if (_isFirst) ...[
                    const SizedBox(height: 8),
                    const AppText(
                      'Penjualan pada tanggal stok awal dan sesudahnya akan mengurangi jumlah tersedia.',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 12,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ImportDialogPill(
                            label: 'Batal',
                            labelOffset: -1,
                            onPressed: _saving
                                ? null
                                : () => Navigator.pop(context),
                          ),
                          if (!widget.editCurrentBalance)
                            _ImportDialogPill(
                              label: 'Simpan & tambah lagi',
                              labelOffset: -1,
                              onPressed: _saving
                                  ? null
                                  : () => _submit(addAnother: true),
                            ),
                          _ImportDialogPill(
                            label: widget.editCurrentBalance
                                ? 'Simpan perubahan'
                                : 'Simpan',
                            blue: true,
                            labelOffset: -1,
                            onPressed: _saving
                                ? null
                                : () => _submit(addAnother: false),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _CalculatorDialog extends StatefulWidget {
  const _CalculatorDialog();

  @override
  State<_CalculatorDialog> createState() => _CalculatorDialogState();
}

class _CalculatorDialogState extends State<_CalculatorDialog> {
  String _display = '0';
  double? _stored;
  String? _operator;
  bool _replaceDisplay = false;

  void _input(String key) {
    setState(() {
      if (key == 'C') {
        _display = '0';
        _stored = null;
        _operator = null;
        _replaceDisplay = false;
      } else if (key == '⌫') {
        _display = _display.length <= 1
            ? '0'
            : _display.substring(0, _display.length - 1);
      } else if (key == '+/-') {
        if (_display != '0') {
          _display = _display.startsWith('-')
              ? _display.substring(1)
              : '-$_display';
        }
      } else if (key == '%') {
        _display = ((_readDisplay()) / 100).toString();
        _replaceDisplay = true;
      } else if (['+', '−', '×', '÷'].contains(key)) {
        _stored = _readDisplay();
        _operator = key;
        _replaceDisplay = true;
      } else if (key == '=') {
        final left = _stored;
        final right = _readDisplay();
        if (left != null && _operator != null) {
          final result = switch (_operator) {
            '+' => left + right,
            '−' => left - right,
            '×' => left * right,
            '÷' => right == 0 ? double.nan : left / right,
            _ => right,
          };
          _display = result.isFinite ? result.toString() : 'Tidak terdefinisi';
          _stored = null;
          _operator = null;
          _replaceDisplay = true;
        }
      } else {
        if (!_display.contains(key)) {
          _display = _replaceDisplay || _display == '0'
              ? key == '.'
                    ? '0.'
                    : key
              : '$_display$key';
          _replaceDisplay = false;
        }
      }
    });
  }

  double _readDisplay() => double.tryParse(_display) ?? 0;

  @override
  Widget build(BuildContext context) {
    const keys = [
      'C',
      '+/-',
      '%',
      '÷',
      '7',
      '8',
      '9',
      '×',
      '4',
      '5',
      '6',
      '−',
      '1',
      '2',
      '3',
      '+',
      '⌫',
      '0',
      '.',
      '=',
    ];
    return AlertDialog(
      title: const AppText('Kalkulator'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .7),
                borderRadius: BorderRadius.circular(17),
              ),
              child: AppText(
                _display,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.fade,
                style: const TextStyle(
                  fontSize: 30,
                  color: _ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            GridView.count(
              crossAxisCount: 4,
              mainAxisSpacing: 7,
              crossAxisSpacing: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final key in keys)
                  _PopFilledButton(
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: key == '='
                          ? _blue.withValues(alpha: .88)
                          : ['÷', '×', '−', '+'].contains(key)
                          ? _blue.withValues(alpha: .15)
                          : ['C', '+/-', '%', '⌫'].contains(key)
                          ? Colors.blueGrey.withValues(alpha: .15)
                          : Colors.white.withValues(alpha: .85),
                      foregroundColor: key == '='
                          ? Colors.white
                          : ['÷', '×', '−', '+'].contains(key)
                          ? _blue
                          : _ink,
                      side: key == '='
                          ? BorderSide(
                              color: Colors.white.withValues(alpha: .72),
                            )
                          : BorderSide.none,
                      elevation: key == '=' ? 2 : 0,
                      shadowColor: _blue.withValues(alpha: .24),
                    ),
                    onPressed: () => _input(key),
                    child: AppText(key, style: const TextStyle(fontSize: 19)),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        _PopTextButton(
          onPressed: () => Navigator.pop(context),
          child: const AppText('Selesai'),
        ),
      ],
    );
  }
}

class _DailyChart extends StatefulWidget {
  const _DailyChart({required this.sales, required this.month});
  final List<Sale> sales;
  final String month;

  @override
  State<_DailyChart> createState() => _DailyChartState();
}

class _DailyChartState extends State<_DailyChart> {
  static const _leftInset = 34.0;
  static const _topInset = 12.0;
  static const _bottomInset = 25.0;
  static const _tooltipWidth = 190.0;
  int? _hoveredDay;

  @override
  void didUpdateWidget(covariant _DailyChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month != widget.month) _hoveredDay = null;
  }

  void _updateHoveredDay(Offset position, Size size, List<double> values) {
    const rightInset = 4.0;
    final plotWidth = size.width - _leftInset - rightInset;
    final plotHeight = size.height - _topInset - _bottomInset;
    final maximum = values.fold<double>(0, (a, b) => a > b ? a : b);
    int? hoveredDay;

    if (plotWidth > 0 &&
        plotHeight > 0 &&
        maximum > 0 &&
        position.dx >= _leftInset &&
        position.dx <= size.width - rightInset &&
        position.dy >= _topInset &&
        position.dy <= _topInset + plotHeight) {
      final groupWidth = plotWidth / values.length;
      final index = ((position.dx - _leftInset) / groupWidth).floor();
      if (index >= 0 && index < values.length) {
        final barWidth = (groupWidth * .62).clamp(2.0, 14.0).toDouble();
        final barHeight = values[index] / maximum * plotHeight;
        final barLeft =
            _leftInset + groupWidth * index + (groupWidth - barWidth) / 2;
        final barTop = _topInset + plotHeight - barHeight;
        final hitArea =
            Rect.fromLTWH(
              barLeft - 3,
              barTop - 3,
              barWidth + 6,
              barHeight + 6,
            ).intersect(
              Rect.fromLTRB(
                _leftInset,
                _topInset,
                size.width - rightInset,
                _topInset + plotHeight,
              ),
            );
        if (hitArea.contains(position)) hoveredDay = index;
      }
    }

    if (hoveredDay != _hoveredDay) {
      setState(() => _hoveredDay = hoveredDay);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupedRevenue = <int, double>{};
    final groupedQuantity = <int, double>{};
    for (final sale in widget.sales) {
      final day = int.tryParse(sale.date.substring(8)) ?? 1;
      groupedRevenue[day] = (groupedRevenue[day] ?? 0) + sale.received;
      groupedQuantity[day] = (groupedQuantity[day] ?? 0) + sale.qty;
    }
    final parts = widget.month.split('-').map(int.parse).toList();
    final days = DateTime(parts[0], parts[1], 1);
    final daysInMonth = DateTime(days.year, days.month + 1, 0).day;
    final revenues = List.generate(
      daysInMonth,
      (index) => groupedRevenue[index + 1] ?? 0,
    );
    final quantities = List.generate(
      daysInMonth,
      (index) => groupedQuantity[index + 1] ?? 0,
    );
    final hoveredDay = _hoveredDay;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return MouseRegion(
          onHover: (event) =>
              _updateHoveredDay(event.localPosition, size, revenues),
          onExit: (_) {
            if (_hoveredDay != null) setState(() => _hoveredDay = null);
          },
          child: Stack(
            children: [
              CustomPaint(
                painter: _ChartPainter(values: revenues),
                child: const SizedBox.expand(),
              ),
              if (hoveredDay != null && hoveredDay < revenues.length)
                Positioned(
                  left: _tooltipLeft(hoveredDay, revenues.length, size.width),
                  top: _tooltipTop(hoveredDay, revenues, size.height),
                  child: IgnorePointer(
                    child: Container(
                      width: _tooltipWidth,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xf5222b3a),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .16),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .2),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppText(
                            '${hoveredDay + 1} ${monthLabel(widget.month).split(' ').first} ${parts[0]}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          AppText(
                            'Penjualan ${formatNumber(quantities[hoveredDay])} pcs',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .85),
                              fontSize: 11,
                            ),
                          ),
                          AppText(
                            'Omzet ${formatMoney(revenues[hoveredDay])}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .85),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  double _tooltipLeft(int dayIndex, int dayCount, double width) {
    final plotWidth = width - _leftInset - 4;
    final groupWidth = plotWidth / dayCount;
    final center = _leftInset + groupWidth * (dayIndex + .5);
    final maxLeft = (width - _tooltipWidth).clamp(0.0, width).toDouble();
    return (center - _tooltipWidth / 2).clamp(0.0, maxLeft).toDouble();
  }

  double _tooltipTop(int dayIndex, List<double> values, double height) {
    const tooltipHeight = 76.0;
    final plotHeight = height - _topInset - _bottomInset;
    final maximum = values.fold<double>(0, (a, b) => a > b ? a : b);
    final barTop = maximum == 0
        ? _topInset + plotHeight
        : _topInset + plotHeight - values[dayIndex] / maximum * plotHeight;
    return (barTop - tooltipHeight - 6)
        .clamp(0.0, (height - tooltipHeight).clamp(0.0, height))
        .toDouble();
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.values});
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const left = _DailyChartState._leftInset;
    const top = _DailyChartState._topInset;
    const bottom = _DailyChartState._bottomInset;
    final plotWidth = size.width - left - 4;
    final plotHeight = size.height - top - bottom;
    final maximum = values.fold<double>(0, (a, b) => a > b ? a : b);
    final grid = Paint()
      ..color = _ink.withValues(alpha: .09)
      ..strokeWidth = 1;
    final text = TextStyle(
      color: _muted,
      fontSize: 9,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    for (var i = 0; i <= 3; i++) {
      final y = top + plotHeight * i / 3;
      canvas.drawLine(Offset(left, y), Offset(size.width - 3, y), grid);
      final amount = maximum * (3 - i) / 3;
      final label = amount >= 1000000
          ? '${(amount / 1000000).toStringAsFixed(0)}jt'
          : amount >= 1000
          ? '${(amount / 1000).toStringAsFixed(0)}rb'
          : amount.toStringAsFixed(0);
      final painter = TextPainter(
        text: TextSpan(text: label, style: text),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: left - 4);
      painter.paint(canvas, Offset(left - painter.width - 5, y - 6));
    }
    if (values.isEmpty) return;
    final groupWidth = plotWidth / values.length;
    final barWidth = (groupWidth * .62).clamp(2.0, 14.0).toDouble();
    final paint = Paint()..color = _blue.withValues(alpha: .82);
    for (var i = 0; i < values.length; i++) {
      final height = maximum == 0 ? 0.0 : values[i] / maximum * plotHeight;
      final x = left + groupWidth * i + (groupWidth - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top + plotHeight - height, barWidth, height),
          const Radius.circular(3),
        ),
        paint,
      );
    }
    for (final day in [1, 5, 10, 15, 20, 25, values.length]) {
      if (day > values.length) continue;
      final painter = TextPainter(
        text: TextSpan(text: '$day', style: text),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = left + groupWidth * (day - .5) - painter.width / 2;
      painter.paint(canvas, Offset(x, size.height - bottom + 6));
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.values != values;
}

class _SalesTable extends StatefulWidget {
  const _SalesTable({
    required this.sales,
    required this.emptyState,
    required this.hasBottomNavigation,
    required this.total,
    required this.onEdit,
    required this.onDelete,
    required this.onCopyOrder,
  });
  final List<Sale> sales;
  final Widget emptyState;
  final bool hasBottomNavigation;
  final double total;
  final ValueChanged<Sale> onEdit;
  final ValueChanged<Sale> onDelete;
  final ValueChanged<String> onCopyOrder;

  @override
  State<_SalesTable> createState() => _SalesTableState();
}

class _SalesTableState extends State<_SalesTable> {
  static const _actionsColumnWidth = 132.0;
  static const _pageSizes = [25, 50, 100];
  static const _rowsPerPageMenuDropup = true;
  OverlayEntry? _paginationOverlayEntry;
  bool _dockInsertScheduled = false;
  bool _paginationOverlayUpdateScheduled = false;
  bool _rowsPerPageMenuOpen = false;
  int _rowsPerPage = 25;
  int _pageIndex = 0;

  List<Sale> get sales => widget.sales;
  double get total => widget.total;
  ValueChanged<Sale> get onEdit => widget.onEdit;
  ValueChanged<Sale> get onDelete => widget.onDelete;
  ValueChanged<String> get onCopyOrder => widget.onCopyOrder;

  @override
  void didUpdateWidget(covariant _SalesTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameSales(oldWidget.sales, widget.sales)) {
      _pageIndex = 0;
      _schedulePaginationOverlayUpdate();
    }
  }

  void _schedulePaginationOverlayUpdate() {
    if (_paginationOverlayEntry == null || _paginationOverlayUpdateScheduled) {
      return;
    }
    _paginationOverlayUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _paginationOverlayUpdateScheduled = false;
      if (!mounted) return;
      _paginationOverlayEntry?.markNeedsBuild();
    });
  }

  void _schedulePaginationDockSync() {
    if (_paginationOverlayEntry != null || _dockInsertScheduled) return;
    _dockInsertScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dockInsertScheduled = false;
      if (!mounted || sales.isEmpty) return;
      _insertPaginationDock();
    });
  }

  void _insertPaginationDock() {
    if (_paginationOverlayEntry != null) return;
    final entry = OverlayEntry(
      builder: (context) {
        final pageCount = sales.isEmpty
            ? 1
            : (sales.length + _rowsPerPage - 1) ~/ _rowsPerPage;
        final pageIndex = _pageIndex.clamp(0, pageCount - 1);
        final startIndex = pageIndex * _rowsPerPage;
        final pageLength = (sales.length - startIndex)
            .clamp(0, _rowsPerPage)
            .toInt();
        return Positioned(
          left: widget.hasBottomNavigation ? 16 : 32,
          bottom: widget.hasBottomNavigation ? 84 : 12,
          child: Offstage(
            offstage: sales.isEmpty,
            child: Transform.scale(
              scale: .9,
              child: Material(
                color: Colors.transparent,
                child: _FrostedSurface(
                  borderRadius: BorderRadius.circular(99),
                  tintColor: const Color(0xfff5faff),
                  tintOpacity: .66,
                  blurSigma: 18,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  child: _paginationControls(
                    start: startIndex + 1,
                    end: startIndex + pageLength,
                    total: sales.length,
                    pageIndex: pageIndex,
                    pageCount: pageCount,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    _paginationOverlayEntry = entry;
    Overlay.of(context).insert(entry);
  }

  void _removePaginationDock() {
    _paginationOverlayEntry?.remove();
    _paginationOverlayEntry?.dispose();
    _paginationOverlayEntry = null;
  }

  void _updatePaginationState(VoidCallback update) {
    setState(update);
    _paginationOverlayEntry?.markNeedsBuild();
  }

  void _changePage(int pageIndex) {
    _updatePaginationState(() => _pageIndex = pageIndex);
  }

  @override
  void dispose() {
    _removePaginationDock();
    super.dispose();
  }

  bool _sameSales(List<Sale> first, List<Sale> second) {
    if (identical(first, second)) return true;
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index].id != second[index].id) return false;
    }
    return true;
  }

  Future<void> _showRowsPerPageMenu(BuildContext buttonContext) async {
    if (_rowsPerPageMenuOpen) {
      Navigator.of(buttonContext).maybePop();
      return;
    }
    _rowsPerPageMenuOpen = true;
    try {
      final selected = await _showFrostedOptionsMenu(
        buttonContext,
        values: _pageSizes,
        selectedValue: _rowsPerPage,
        labelFor: (size) => '$size baris',
      );
      if (selected == null || !mounted) return;
      _updatePaginationState(() {
        _rowsPerPage = selected;
        _pageIndex = 0;
      });
    } finally {
      _rowsPerPageMenuOpen = false;
    }
  }

  Future<int?> _showFrostedOptionsMenu(
    BuildContext buttonContext, {
    required List<int> values,
    required int selectedValue,
    required String Function(int) labelFor,
  }) async {
    final buttonObject = buttonContext.findRenderObject();
    final overlayObject = Overlay.of(buttonContext).context.findRenderObject();
    if (buttonObject is! RenderBox || overlayObject is! RenderBox) {
      throw StateError('Tidak bisa menentukan posisi menu pagination.');
    }

    final origin = buttonObject.localToGlobal(
      Offset.zero,
      ancestor: overlayObject,
    );
    final rect = origin & buttonObject.size;
    final preferredHeight = values.length * 44.0 + 8;
    final spaceAbove = (rect.top - 8).clamp(0.0, overlayObject.size.height);
    final spaceBelow = (overlayObject.size.height - rect.bottom - 8).clamp(
      0.0,
      overlayObject.size.height,
    );
    final availableHeight = _rowsPerPageMenuDropup ? spaceAbove : spaceBelow;
    if (availableHeight <= 0) {
      throw StateError('Tidak ada ruang untuk membuka menu pagination.');
    }

    final menuHeight = preferredHeight.clamp(0.0, availableHeight).toDouble();
    final maxWidth = (overlayObject.size.width - 16).clamp(
      0.0,
      double.infinity,
    );
    final menuWidth =
        (buttonObject.size.width < 112 ? 112.0 : buttonObject.size.width)
            .clamp(0.0, maxWidth)
            .toDouble();
    final menuLeft = (rect.center.dx - menuWidth / 2)
        .clamp(8.0, overlayObject.size.width - menuWidth - 8)
        .toDouble();
    final menuTop = _rowsPerPageMenuDropup
        ? rect.top - menuHeight
        : rect.bottom;

    final selected = await showGeneralDialog<int>(
      context: buttonContext,
      useRootNavigator: false,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(buttonContext)
          .modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (dialogContext, animation, secondaryAnimation) => Stack(
        children: [
          Positioned(
            left: menuLeft,
            top: menuTop,
            width: menuWidth,
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              ),
              child: SlideTransition(
                position:
                    Tween<Offset>(
                      begin: _rowsPerPageMenuDropup
                          ? const Offset(0, .16)
                          : const Offset(0, -.16),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                        reverseCurve: Curves.easeInCubic,
                      ),
                    ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: menuHeight),
                  child: _FrostedSurface(
                    borderRadius: BorderRadius.circular(14),
                    tintColor: _popupTintColor,
                    tintOpacity: .82,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    blurSigma: 18,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final value in values)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(99),
                                  hoverColor: Colors.white.withValues(
                                    alpha: .48,
                                  ),
                                  splashColor: Colors.white.withValues(
                                    alpha: .3,
                                  ),
                                  onTap: () =>
                                      Navigator.pop(dialogContext, value),
                                  child: SizedBox(
                                    height: 40,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: AppText(
                                              labelFor(value),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: _ink,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          if (value == selectedValue)
                                            const Icon(
                                              Icons.check_rounded,
                                              color: _blue,
                                              size: 17,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return selected;
  }

  @override
  Widget build(BuildContext context) {
    if (sales.isEmpty) return widget.emptyState;
    return LayoutBuilder(
      builder: (context, constraints) {
        _schedulePaginationDockSync();
        final compact = constraints.maxWidth < 620;
        final pageCount = (sales.length + _rowsPerPage - 1) ~/ _rowsPerPage;
        final pageIndex = _pageIndex.clamp(0, pageCount - 1);
        final startIndex = pageIndex * _rowsPerPage;
        final pageSales = sales
            .skip(startIndex)
            .take(_rowsPerPage)
            .toList(growable: false);
        return Column(
          children: [
            _header(compact),
            const SizedBox(height: 5),
            for (var index = 0; index < pageSales.length; index++) ...[
              if (index > 0) ...[
                const SizedBox(height: 5),
                Divider(height: 1, color: _ink.withValues(alpha: .1)),
                const SizedBox(height: 5),
              ],
              _row(pageSales[index], compact),
            ],
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _blue.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(
                children: [
                  if (compact) ...[
                    const Expanded(
                      child: AppText(
                        'Total diterima · semua halaman',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    AppText(
                      formatMoney(total),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ] else ...[
                    const Expanded(
                      flex: 9,
                      child: AppText(
                        'Total diterima · semua halaman',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Spacer(flex: 8),
                    const Spacer(flex: 8),
                    const Spacer(flex: 8),
                    Expanded(
                      flex: 8,
                      child: AppText(
                        formatMoney(total),
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: _actionsColumnWidth),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _paginationControls({
    required int start,
    required int end,
    required int total,
    required int pageIndex,
    required int pageCount,
  }) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 12,
    runSpacing: 8,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppText(
            'Baris per halaman',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 34,
            child: Builder(
              builder: (buttonContext) => _ButtonPop(
                child: InkWell(
                  onTap: () => _showRowsPerPageMenu(buttonContext),
                  borderRadius: BorderRadius.circular(99),
                  child: _FrostedSurface(
                    borderRadius: BorderRadius.circular(99),
                    tintColor: const Color(0xfff5faff),
                    tintOpacity: .62,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    shadow: false,
                    blurSigma: 18,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppText(
                          '$_rowsPerPage',
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Icon(Icons.expand_more_rounded, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppText(
            '$start–$end dari $total',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(width: 8),
          if (pageIndex > 0) ...[
            _paginationArrow(
              icon: Icons.chevron_left_rounded,
              tooltip: localizeAppText('Halaman sebelumnya'),
              onPressed: () => _changePage(pageIndex - 1),
            ),
            const SizedBox(width: 6),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AppText(
              '${pageIndex + 1} / $pageCount',
              style: const TextStyle(
                color: _ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (pageIndex + 1 < pageCount)
            _paginationArrow(
              icon: Icons.chevron_right_rounded,
              tooltip: localizeAppText('Halaman berikutnya'),
              onPressed: () => _changePage(pageIndex + 1),
            ),
        ],
      ),
    ],
  );

  Widget _paginationArrow({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) => SizedBox(
    width: 34,
    height: 34,
    child: Tooltip(
      message: localizeAppText(tooltip),
      child: _ButtonPop(
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(99),
          child: _FrostedSurface(
            borderRadius: BorderRadius.circular(99),
            tintColor: const Color(0xfff5faff),
            tintOpacity: .62,
            padding: const EdgeInsets.all(7),
            shadow: false,
            blurSigma: 18,
            child: Icon(icon, size: 20, color: _ink),
          ),
        ),
      ),
    ),
  );

  Widget _header(bool compact) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .28),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      children: [
        Expanded(
          flex: compact ? 1 : 9,
          child: Padding(
            padding: EdgeInsets.only(right: compact ? 0 : 14),
            child: Row(
              children: [const AppText('Produk', style: _headerStyle)],
            ),
          ),
        ),
        if (compact) const SizedBox(width: 8),
        if (!compact)
          const Expanded(
            flex: 8,
            child: AppText(
              'Nomor pesanan',
              textAlign: TextAlign.center,
              style: _headerStyle,
            ),
          ),
        if (!compact)
          const Expanded(
            flex: 8,
            child: AppText(
              'Tanggal dipesan',
              textAlign: TextAlign.center,
              style: _headerStyle,
            ),
          ),
        if (!compact)
          const Expanded(
            flex: 8,
            child: AppText(
              'Rincian',
              textAlign: TextAlign.end,
              style: _headerStyle,
            ),
          ),
        Expanded(
          flex: compact ? 1 : 8,
          child: const AppText(
            'Uang diterima',
            textAlign: TextAlign.end,
            style: _headerStyle,
          ),
        ),
        if (!compact) const SizedBox(width: _actionsColumnWidth),
      ],
    ),
  );

  Widget _row(Sale sale, bool compact) {
    final orderNo = sale.orderNo.trim();
    final orderNoText = orderNo.isEmpty ? '—' : orderNo;
    final dateParts = sale.date.split('-');
    final date = dateParts.length == 3
        ? '${dateParts[2]}/${dateParts[1]}/${dateParts[0]}'
        : sale.date;
    final details = [
      '${formatNumber(sale.qty)} pcs',
      if (sale.variant.isNotEmpty) sale.variant,
    ].join(' · ');
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PocketRActionButton(
          icon: null,
          label: 'Ubah',
          compact: true,
          labelOffset: -1,
          foregroundColor: _blue,
          onPressed: () => onEdit(sale),
        ),
        const SizedBox(width: 4),
        _PocketRActionButton(
          icon: null,
          label: 'Hapus',
          danger: true,
          compact: true,
          labelOffset: -1,
          onPressed: () => onDelete(sale),
        ),
      ],
    );
    final amount = AppText(
      formatMoney(sale.received),
      textAlign: TextAlign.end,
      style: const TextStyle(color: _green, fontWeight: FontWeight.w800),
    );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _name(sale)),
                const SizedBox(width: 8),
                Expanded(child: amount),
              ],
            ),
            Row(
              children: [
                Expanded(flex: 3, child: _orderNumber(orderNoText)),
                const SizedBox(width: 8),
                AppText(
                  'Tgl $date',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: AppText.raw(
                    details,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
                controls,
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: [
          Expanded(
            flex: 9,
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: _name(sale),
            ),
          ),
          Expanded(flex: 8, child: _orderNumber(orderNoText)),
          Expanded(
            flex: 8,
            child: AppText(
              date,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ),
          Expanded(
            flex: 8,
            child: AppText.raw(
              details,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ),
          Expanded(flex: 8, child: amount),
          SizedBox(
            width: _actionsColumnWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                alignment: Alignment.centerRight,
                fit: BoxFit.scaleDown,
                child: controls,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderNumber(String value) {
    final hasOrderNumber = value != '—';
    return Tooltip(
      message: localizeAppText(
        hasOrderNumber
            ? 'Klik untuk menyalin nomor pesanan'
            : 'Nomor pesanan kosong',
      ),
      child: InkWell(
        onTap: hasOrderNumber ? () => onCopyOrder(value) : null,
        mouseCursor: hasOrderNumber
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: AppText(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: hasOrderNumber ? _blue : _muted,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _name(Sale sale) {
    final platform = sale.platform.toLowerCase();
    final color = switch (platform) {
      'lazada' => const Color(0xff0f146d),
      'shopee' => const Color(0xffee4d2d),
      'tiktok' => const Color(0xff000000),
      'tokopedia' => const Color(0xff03ac0e),
      _ => const Color(0xff808080),
    };
    final avatarLabel = switch (platform) {
      'lazada' => 'L',
      'shopee' => 'S',
      'tiktok' => 'Tt',
      'tokopedia' => 'T',
      _ => 'etc.',
    };
    return Row(
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: color,
          child: AppText(
            avatarLabel,
            style: TextStyle(
              color: Colors.white,
              fontSize: avatarLabel.length > 1 ? 9 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AppText.raw(
            sale.productName,
            softWrap: true,
            style: const TextStyle(fontWeight: FontWeight.w500, height: 1.2),
          ),
        ),
      ],
    );
  }
}

class _OperationalExpenseTable extends StatelessWidget {
  const _OperationalExpenseTable({
    required this.expenses,
    required this.total,
    required this.getTotal,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Expense> expenses;
  final double total;
  final double Function(Expense) getTotal;
  final ValueChanged<Expense> onEdit;
  final ValueChanged<Expense> onDelete;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 620;
      final hasDateColumn = expenses.any(
        (expense) => expense.category == 'thr',
      );
      return Column(
        children: [
          _header(compact, hasDateColumn),
          const SizedBox(height: 5),
          for (var index = 0; index < expenses.length; index++) ...[
            if (index > 0) ...[
              const SizedBox(height: 5),
              Divider(height: 1, color: _ink.withValues(alpha: .1)),
              const SizedBox(height: 5),
            ],
            _row(expenses[index], compact, hasDateColumn),
          ],
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _blue.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                if (compact) ...[
                  const Expanded(
                    child: AppText(
                      'Total',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  AppText(
                    formatMoney(total),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ] else ...[
                  Expanded(
                    flex: hasDateColumn ? 7 : 6,
                    child: AppText(
                      'Total',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: AppText(
                      formatMoney(total),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 128),
                ],
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _header(bool compact, bool hasDateColumn) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .28),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      children: [
        Expanded(
          flex: compact
              ? 3
              : hasDateColumn
              ? 3
              : 4,
          child: const AppText('Biaya', style: _headerStyle),
        ),
        if (!compact && hasDateColumn)
          const Expanded(
            flex: 2,
            child: AppText(
              'Tanggal',
              textAlign: TextAlign.center,
              style: _headerStyle,
            ),
          ),
        if (!compact)
          const Expanded(
            flex: 2,
            child: AppText(
              'Catatan',
              textAlign: TextAlign.center,
              style: _headerStyle,
            ),
          ),
        Expanded(
          flex: compact ? 2 : 2,
          child: const AppText(
            'Jumlah',
            textAlign: TextAlign.center,
            style: _headerStyle,
          ),
        ),
        if (!compact) const SizedBox(width: 128),
      ],
    ),
  );

  Widget _row(Expense expense, bool compact, bool hasDateColumn) {
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PocketRActionButton(
          icon: null,
          label: 'Ubah',
          compact: true,
          labelOffset: -1,
          foregroundColor: _blue,
          onPressed: () => onEdit(expense),
        ),
        const SizedBox(width: 4),
        _PocketRActionButton(
          icon: null,
          label: 'Hapus',
          danger: true,
          compact: true,
          labelOffset: -1,
          onPressed: () => onDelete(expense),
        ),
      ],
    );
    final amount = AppText(
      formatMoney(getTotal(expense)),
      textAlign: TextAlign.center,
      style: const TextStyle(fontWeight: FontWeight.w800),
    );
    final date = _formatExpenseDate(expense.date);

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _name(expense)),
                const SizedBox(width: 8),
                Flexible(child: amount),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _noteText(
                    expense,
                    prefix: hasDateColumn ? date : null,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                controls,
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: [
          Expanded(flex: hasDateColumn ? 3 : 4, child: _name(expense)),
          if (hasDateColumn)
            Expanded(
              flex: 2,
              child: AppText(
                date,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ),
          Expanded(
            flex: 2,
            child: _noteText(
              expense,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(flex: 2, child: amount),
          SizedBox(
            width: 128,
            child: FittedBox(
              alignment: Alignment.centerRight,
              fit: BoxFit.scaleDown,
              child: controls,
            ),
          ),
        ],
      ),
    );
  }

  Widget _noteText(
    Expense expense, {
    String? prefix,
    TextAlign? textAlign,
    int? maxLines,
    TextOverflow? overflow,
  }) => ValueListenableBuilder<String>(
    valueListenable: appLanguageCode,
    builder: (context, languageCode, _) {
      final note = expense.category == 'iklan'
          ? [
              localizeAppText(
                marketplaceNames[expense.platform] ?? expense.platform,
                languageCode: languageCode,
              ),
              expense.productName.isEmpty
                  ? localizeAppText(
                      'Semua produk / umum',
                      languageCode: languageCode,
                    )
                  : expense.productName,
              if (expense.note.isNotEmpty) expense.note,
            ].join(' · ')
          : expense.note.isEmpty
          ? '—'
          : expense.note;
      return Text(
        prefix == null ? note : '$prefix · $note',
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        style: const TextStyle(color: _muted, fontSize: 12),
      );
    },
  );

  Widget _name(Expense expense) => Row(
    children: [
      CircleAvatar(
        radius: 15,
        backgroundColor: Colors.white.withValues(alpha: .55),
        child: AppText.raw(
          expense.name.isEmpty
              ? '?'
              : expense.name.characters.first.toUpperCase(),
          style: const TextStyle(
            color: _muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: AppText.raw(
          expense.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
    ],
  );
}

const _headerStyle = TextStyle(color: _muted, fontSize: 11);

String _formatExpenseDate(String date) {
  final parsed = DateTime.tryParse(date);
  if (parsed == null) return '—';
  return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({
    required this.expense,
    required this.total,
    required this.onEdit,
    required this.onDelete,
  });
  final Expense expense;
  final double total;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: _FrostedSurface(
      borderRadius: BorderRadius.circular(14),
      tintOpacity: .2,
      shadow: false,
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 12, right: 2),
        leading: CircleAvatar(
          backgroundColor: _orange.withValues(alpha: .14),
          child: AppText(
            expense.name.isEmpty
                ? '?'
                : expense.name.characters.first.toUpperCase(),
            style: const TextStyle(color: _orange, fontWeight: FontWeight.w700),
          ),
        ),
        title: AppText(
          expense.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: ValueListenableBuilder<String>(
          valueListenable: appLanguageCode,
          builder: (context, languageCode, _) {
            final subtitle = expense.category == 'iklan'
                ? '${localizeAppText(marketplaceNames[expense.platform] ?? expense.platform, languageCode: languageCode)} · ${expense.productName.isEmpty ? localizeAppText('Semua produk / umum', languageCode: languageCode) : expense.productName}${expense.note.isEmpty ? '' : ' · ${expense.note}'}'
                : expense.note.isEmpty
                ? localizeAppText(
                    'Biaya ${categoryNames[expense.category]?.toLowerCase() ?? 'lainnya'}',
                    languageCode: languageCode,
                  )
                : expense.note;
            return Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis);
          },
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppText(
              formatMoney(total),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            PopupMenuButton<String>(
              onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: AppText('Ubah')),
                PopupMenuItem(value: 'delete', child: AppText('Hapus')),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _MaterialTile extends StatelessWidget {
  const _MaterialTile({
    required this.material,
    required this.compact,
    required this.onEdit,
    required this.onDelete,
  });

  final MaterialCost material;
  final bool compact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  Widget _name() => Row(
    children: [
      CircleAvatar(
        radius: 15,
        backgroundColor: Colors.white.withValues(alpha: .55),
        child: AppText(
          material.name.isEmpty
              ? '?'
              : material.name.characters.first.toUpperCase(),
          style: const TextStyle(
            color: _muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: AppText.raw(
          material.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
    ],
  );

  Widget _controls() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _PocketRActionButton(
        icon: null,
        label: 'Ubah',
        compact: true,
        labelOffset: -1,
        foregroundColor: _blue,
        onPressed: onEdit,
      ),
      const SizedBox(width: 4),
      _PocketRActionButton(
        icon: null,
        label: 'Hapus',
        danger: true,
        compact: true,
        labelOffset: -1,
        onPressed: onDelete,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final unit = AppText.raw(
      material.unit.isEmpty ? '—' : material.unit,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: _muted, fontSize: 12),
    );
    final price = AppText(
      formatMoney(material.price),
      textAlign: TextAlign.center,
      style: const TextStyle(fontWeight: FontWeight.w800),
    );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _name()),
                const SizedBox(width: 8),
                Flexible(child: price),
              ],
            ),
            Row(
              children: [
                Expanded(child: unit),
                _controls(),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: [
          Expanded(flex: 4, child: _name()),
          Expanded(flex: 3, child: unit),
          Expanded(flex: 3, child: price),
          SizedBox(width: 128, child: _controls()),
        ],
      ),
    );
  }
}

class _SaleDialog extends StatefulWidget {
  const _SaleDialog({required this.data, this.initial, this.initialPlatform});
  final FinanceData data;
  final Sale? initial;
  final String? initialPlatform;

  @override
  State<_SaleDialog> createState() => _SaleDialogState();
}

class _SaleDialogState extends State<_SaleDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _qty;
  late final TextEditingController _received;
  late final TextEditingController _order;
  late final TextEditingController _hpp;
  late String _date;
  late String _platform;
  late String _productId;
  String _color = '';
  String _size = '';
  String _other = '';

  Product get _product => widget.data.products.firstWhere(
    (product) => product.id == _productId,
    orElse: () => widget.data.products.first,
  );

  double _calculatedHpp(Product product) => widget.data.productHpp(product);

  @override
  void initState() {
    super.initState();
    final sale = widget.initial;
    _date = sale?.date ?? DateTime.now().toIso8601String().substring(0, 10);
    _platform = sale?.platform ?? widget.initialPlatform ?? 'shopee';
    _productId =
        widget.data.products.any((product) => product.id == sale?.productId)
        ? sale!.productId
        : widget.data.products.first.id;
    _color = _product.colors.contains(sale?.color)
        ? sale!.color
        : _product.colors.firstOrNull ?? '';
    _size = sale?.size ?? '';
    _other = sale?.other ?? '';
    _qty = TextEditingController(text: '${sale?.qty.round() ?? 1}');
    _received = TextEditingController(
      text: sale == null ? '' : _formatAmountInput('${sale.received.round()}'),
    );
    _order = TextEditingController(text: sale?.orderNo ?? '');
    _hpp = TextEditingController(
      text: _formatAmountInput(
        '${sale?.hpp.round() ?? _calculatedHpp(_product).round()}',
      ),
    );
  }

  @override
  void dispose() {
    _qty.dispose();
    _received.dispose();
    _order.dispose();
    _hpp.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      Sale(
        id: widget.initial?.id,
        date: _date,
        platform: _platform,
        productId: _product.id,
        productName: _product.name,
        qty: _parseDecimal(_qty.text),
        orderNo: _order.text.trim(),
        received: _parseAmount(_received.text),
        hpp: _parseAmount(_hpp.text),
        color: _color,
        size: _size,
        other: _other,
      ),
    );
  }

  Widget _productField() => _stockDropdown(
    label: 'Produk',
    value: _productId,
    options: [
      for (final product in widget.data.products) (product.id, product.name),
    ],
    onChanged: (selected) {
      setState(() {
        _productId = selected;
        _hpp.text = _formatAmountInput('${_calculatedHpp(_product).round()}');
        _color = _product.colors.firstOrNull ?? '';
        _size = '';
        _other = '';
      });
    },
  );

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 480,
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      child: _FrostedSurface(
        borderRadius: BorderRadius.circular(26),
        tintColor: _popupTintColor,
        tintOpacity: _popupTintOpacity,
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
        blurSigma: 12,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: AppText(
                        widget.initial == null
                            ? 'Tambah penjualan'
                            : 'Ubah penjualan',
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _PopIconButton(
                      tooltip: localizeAppText('Tutup'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 18),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: .56),
                        foregroundColor: _muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _MarketplacePills(
                  selectedValue: _platform,
                  onSelected: (value) => setState(() => _platform = value),
                ),
                const SizedBox(height: 10),
                _productField(),
                if (_product.colors.isNotEmpty || _product.sizes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        if (_product.colors.isNotEmpty)
                          Expanded(
                            child: _stockDropdown(
                              label: 'Warna',
                              value: _product.colors.contains(_color)
                                  ? _color
                                  : _product.colors.first,
                              options: [
                                for (final color in _product.colors)
                                  (color, color),
                              ],
                              onChanged: (value) =>
                                  setState(() => _color = value),
                            ),
                          ),
                        if (_product.sizes.isNotEmpty) ...[
                          if (_product.colors.isNotEmpty)
                            const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('size-$_productId'),
                              initialValue: _product.sizes.contains(_size)
                                  ? _size
                                  : '',
                              decoration: InputDecoration(
                                labelText: localizeAppText('Ukuran'),
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: '',
                                  child: AppText('Tanpa ukuran'),
                                ),
                                for (final value in _product.sizes)
                                  DropdownMenuItem(
                                    value: value,
                                    child: AppText.raw(value),
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _size = value ?? ''),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (_product.variants.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('variant-$_productId'),
                      initialValue: _product.variants.contains(_other)
                          ? _other
                          : '',
                      decoration: InputDecoration(
                        labelText: localizeAppText('Varian lain'),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: AppText('Tanpa varian'),
                        ),
                        for (final value in _product.variants)
                          DropdownMenuItem(
                            value: value,
                            child: AppText.raw(value),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _other = value ?? ''),
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _textField(
                        _qty,
                        'Kuantitas',
                        inputVerticalPadding: 0,
                        textOffset: const Offset(0, 8),
                        keyboard: TextInputType.number,
                        integerOnly: true,
                        onSubmitted: _submit,
                        errorBuilder: (context, errorText) =>
                            Transform.translate(
                              offset: const Offset(0, -15),
                              child: AppText(
                                errorText,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        validator: (value) => _parseDecimal(value ?? '') <= 0
                            ? 'Qty harus lebih dari 0'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _textField(
                        _received,
                        'Uang diterima (Rp)',
                        inputVerticalPadding: 0,
                        textOffset: const Offset(0, 8),
                        keyboard: TextInputType.number,
                        groupThousands: true,
                        onSubmitted: _submit,
                        errorBuilder: (context, errorText) =>
                            Transform.translate(
                              offset: const Offset(0, -15),
                              child: AppText(
                                errorText,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        validator: (value) =>
                            (value ?? '').trim().isEmpty ? 'Wajib diisi' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _textField(
                  _order,
                  'Nomor pesanan (opsional)',
                  inputVerticalPadding: 0,
                  textOffset: const Offset(0, 8),
                  onSubmitted: _submit,
                ),
                const SizedBox(height: 10),
                _textField(
                  _hpp,
                  'HPP per pcs (Rp)',
                  inputVerticalPadding: 0,
                  textOffset: const Offset(0, 8),
                  keyboard: TextInputType.number,
                  groupThousands: true,
                  helper: 'Nilai HPP tersimpan pada catatan penjualan ini.',
                  onSubmitted: _submit,
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ImportDialogPill(
                        label: 'Batal',
                        labelOffset: -1,
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      _ImportDialogPill(
                        label: 'Simpan',
                        blue: true,
                        labelOffset: -1,
                        onPressed: _submit,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _MarketplacePills extends StatelessWidget {
  const _MarketplacePills({
    required this.selectedValue,
    required this.onSelected,
  });

  final String selectedValue;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(left: 4, bottom: 5),
        child: AppText(
          'Platform penjualan',
          style: TextStyle(color: _muted, fontSize: 12),
        ),
      ),
      _LiquidGlassTabBar(
        tabs: [
          for (final entry in marketplaceNames.entries)
            (entry.key, entry.value),
        ],
        selectedValue: selectedValue,
        onSelected: onSelected,
      ),
    ],
  );
}

class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog({
    required this.category,
    required this.products,
    required this.ppnPct,
    required this.month,
    required this.onSaveAndAdd,
    required this.isWindowMaximized,
    this.initial,
  });
  final String category;
  final List<Product> products;
  final double ppnPct;
  final String month;
  final Future<bool> Function(Expense expense) onSaveAndAdd;
  final bool isWindowMaximized;
  final Expense? initial;

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  late final FocusNode _nameFocusNode;
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late String _platform;
  late String _productId;
  late bool _ppn;
  late DateTime _date;
  bool _savingAndAdding = false;

  @override
  void initState() {
    super.initState();
    _nameFocusNode = FocusNode();
    final expense = widget.initial;
    final savedDate = DateTime.tryParse(expense?.date ?? '');
    _date =
        savedDate ?? DateTime.tryParse('${widget.month}-01') ?? DateTime.now();
    _name = TextEditingController(
      text:
          expense?.name ??
          (widget.category == 'thr'
              ? localizeAppText('Persiapan THR Lebaran')
              : ''),
    );
    _amount = TextEditingController(
      text: expense == null
          ? ''
          : _formatAmountInput('${expense.amount.round()}'),
    );
    _note = TextEditingController(text: expense?.note ?? '');
    _platform = expense?.platform ?? 'shopee';
    _productId = expense?.productId ?? '';
    _ppn = expense?.ppn ?? true;
  }

  @override
  void dispose() {
    _nameFocusNode.dispose();
    _name.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Expense _expenseFromForm() {
    final ads = widget.category == 'iklan';
    final product = widget.products
        .where((item) => item.id == _productId)
        .firstOrNull;
    return Expense(
      id: widget.initial?.id,
      category: widget.category,
      date: widget.category == 'thr'
          ? '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'
          : widget.initial?.date ?? '',
      month: widget.category == 'thr'
          ? '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}'
          : widget.month,
      name: ads ? 'Iklan' : _name.text.trim(),
      amount: _parseAmount(_amount.text),
      note: _note.text.trim(),
      platform: _platform,
      productId: ads ? _productId : '',
      productName: ads ? product?.name ?? '' : '',
      ppn: ads && _ppn,
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _expenseFromForm());
  }

  Future<void> _saveAndAddAgain() async {
    if (_savingAndAdding || !_formKey.currentState!.validate()) return;
    setState(() => _savingAndAdding = true);
    try {
      final saved = await widget.onSaveAndAdd(_expenseFromForm());
      if (!mounted || !saved) return;
      _name.clear();
      _amount.clear();
      _note.clear();
      _formKey.currentState?.reset();
      _nameFocusNode.requestFocus();
    } finally {
      if (mounted) setState(() => _savingAndAdding = false);
    }
  }

  Future<void> _pickDate() async {
    final selected = await showGeneralDialog<DateTime>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0x180f202c),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: _FrostedCalendarDialog(initialDate: _date),
        ),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          _normalDialogTransition(animation, child),
    );
    if (selected != null && mounted) setState(() => _date = selected);
  }

  Widget _dateField() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(left: 4, bottom: 5),
        child: AppText(
          'Tanggal',
          style: TextStyle(color: _muted, fontSize: 12),
        ),
      ),
      SizedBox(
        height: 40,
        child: _ButtonPop(
          child: _liquidInputSurface(
            minHeight: 40,
            verticalPadding: 0,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: _pickDate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Transform.translate(
                          offset: const Offset(0, -2),
                          child: AppText(
                            '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                            style: const TextStyle(color: _ink, fontSize: 13),
                          ),
                        ),
                      ),
                      Transform.translate(
                        offset: const Offset(0, -2),
                        child: const Icon(
                          Icons.calendar_month_outlined,
                          size: 17,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _dropdownField({
    required String label,
    required String value,
    required List<(String, String)> options,
    required ValueChanged<String> onSelected,
  }) {
    Widget optionText(
      String text, {
      int? maxLines,
      TextOverflow? overflow,
      TextStyle? style,
    }) => text == 'Semua produk / umum'
        ? AppText(text, maxLines: maxLines, overflow: overflow, style: style)
        : AppText.raw(
            text,
            maxLines: maxLines,
            overflow: overflow,
            style: style,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 5),
          child: AppText(
            label,
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ),
        SizedBox(
          height: 44,
          child: Builder(
            builder: (context) => _ButtonPop(
              intensity: .5,
              normalizeScaleByWidth: true,
              child: _liquidInputSurface(
                showBorder: false,
                minHeight: 44,
                verticalPadding: 0,
                child: SizedBox.expand(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(99),
                    onTap: () async {
                      final anchor = context.findRenderObject()! as RenderBox;
                      final overlay =
                          Overlay.of(context).context.findRenderObject()!
                              as RenderBox;
                      final origin = anchor.localToGlobal(
                        Offset.zero,
                        ancestor: overlay,
                      );
                      final rect = origin & anchor.size;
                      final availableHeight =
                          overlay.size.height - rect.bottom - 8;
                      if (availableHeight <= 0) return;
                      final selected = await showMenu<String>(
                        context: context,
                        position: RelativeRect.fromLTRB(
                          rect.left,
                          rect.bottom,
                          overlay.size.width - rect.right,
                          rect.bottom,
                        ),
                        constraints: BoxConstraints(
                          minWidth: anchor.size.width,
                          maxWidth: anchor.size.width,
                          maxHeight: availableHeight,
                        ),
                        color: const Color(0xffeef6fb),
                        elevation: 10,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        items: [
                          for (final option in options)
                            PopupMenuItem<String>(
                              value: option.$1,
                              height: 44,
                              child: optionText(
                                option.$2,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      );
                      if (selected != null) onSelected(selected);
                    },
                    child: Row(
                      children: [
                        Expanded(
                          child: Transform.translate(
                            offset: const Offset(0, -2),
                            child: optionText(
                              options
                                  .firstWhere((option) => option.$1 == value)
                                  .$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: _ink, fontSize: 14),
                            ),
                          ),
                        ),
                        Transform.translate(
                          offset: const Offset(0, -1),
                          child: const Icon(
                            Icons.arrow_drop_down,
                            color: _muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _marketplacePills() => _MarketplacePills(
    selectedValue: _platform,
    onSelected: (value) => setState(() => _platform = value),
  );

  @override
  Widget build(BuildContext context) {
    final ads = widget.category == 'iklan';
    final inputFontSize = widget.isWindowMaximized ? 13.0 : 14.0;
    final inputTextOffset = ads ? 7.0 : 6.0;
    final amountTextOffset = inputTextOffset;
    final nameLabel = switch (widget.category) {
      'gaji' => 'Nama pegawai',
      'thr' => 'Keterangan',
      _ => 'Nama biaya',
    };
    final title =
        '${widget.initial == null ? 'Tambah' : 'Ubah'} ${categoryNames[widget.category]?.toLowerCase() ?? 'pengeluaran'}';
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(context).height * .9,
        ),
        child: _FrostedSurface(
          borderRadius: BorderRadius.circular(28),
          tintColor: _popupTintColor,
          tintOpacity: _popupTintOpacity,
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
          blurSigma: 12,
          prominentShadow: true,
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppText(
                          title,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _PopIconButton(
                        tooltip: localizeAppText('Tutup'),
                        onPressed: () => Navigator.pop(context),
                        style: IconButton.styleFrom(
                          foregroundColor: _muted,
                          backgroundColor: Colors.white.withValues(alpha: .5),
                          minimumSize: const Size(32, 32),
                          padding: EdgeInsets.zero,
                        ),
                        icon: const Icon(Icons.close, size: 17),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (ads) ...[
                    _marketplacePills(),
                    const SizedBox(height: 10),
                    _dropdownField(
                      label: 'Iklan untuk produk',
                      value:
                          widget.products.any((item) => item.id == _productId)
                          ? _productId
                          : '',
                      options: [
                        ('', 'Semua produk / umum'),
                        for (final product in widget.products)
                          (product.id, product.name),
                      ],
                      onSelected: (value) => setState(() => _productId = value),
                    ),
                    const SizedBox(height: 10),
                  ] else ...[
                    if (widget.category == 'thr') ...[
                      _dateField(),
                      const SizedBox(height: 10),
                    ],
                    _textField(
                      _name,
                      nameLabel,
                      focusNode: _nameFocusNode,
                      fontSize: inputFontSize,
                      inputVerticalPadding: 0,
                      textOffset: Offset(0, inputTextOffset),
                      onSubmitted: _submit,
                      errorBuilder: (context, errorText) => Transform.translate(
                        offset: const Offset(0, -13),
                        child: AppText(
                          errorText,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      validator: (value) =>
                          (value ?? '').trim().isEmpty ? 'Wajib diisi' : null,
                    ),
                    const SizedBox(height: 10),
                  ],
                  _textField(
                    _amount,
                    ads ? 'Biaya iklan sebelum PPN (Rp)' : 'Jumlah (Rp)',
                    fontSize: inputFontSize,
                    inputVerticalPadding: 0,
                    textOffset: Offset(0, amountTextOffset),
                    keyboard: TextInputType.number,
                    groupThousands: true,
                    onSubmitted: _submit,
                    errorBuilder: (context, errorText) => Transform.translate(
                      offset: const Offset(0, -13),
                      child: AppText(
                        errorText,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? 'Wajib diisi' : null,
                  ),
                  if (ads) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AppText(
                                    'Tambahkan PPN ${formatNumber(widget.ppnPct, decimals: 1)}%',
                                    style: const TextStyle(
                                      color: _ink,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  AppText(
                                    'Total dibayar: ${formatMoney(_parseAmount(_amount.text) * (_ppn ? 1 + widget.ppnPct / 100 : 1))}',
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          CupertinoSwitch(
                            value: _ppn,
                            activeTrackColor: _blue,
                            onChanged: (value) => setState(() => _ppn = value),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _textField(
                    _note,
                    'Catatan (opsional)',
                    fontSize: inputFontSize,
                    inputVerticalPadding: 0,
                    textOffset: Offset(0, inputTextOffset),
                    onSubmitted: _submit,
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ImportDialogPill(
                          label: 'Batal',
                          labelOffset: -1,
                          onPressed: () => Navigator.pop(context),
                        ),
                        if (widget.category == 'operasional' &&
                            widget.initial == null)
                          _ImportDialogPill(
                            label: 'Simpan & tambah lagi',
                            labelOffset: -1,
                            onPressed: _savingAndAdding
                                ? null
                                : _saveAndAddAgain,
                          ),
                        _ImportDialogPill(
                          label: 'Simpan',
                          blue: true,
                          labelOffset: -1,
                          onPressed: _savingAndAdding ? null : _submit,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductPickerClipper extends CustomClipper<Rect> {
  const _ProductPickerClipper();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-18, 0, size.width + 18, size.height);

  @override
  bool shouldReclip(covariant _ProductPickerClipper oldClipper) => false;
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({this.initial, required this.onSave});
  final Product? initial;
  final Future<void> Function(Product product) onSave;

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _colors;
  late final TextEditingController _sizes;
  final _nameFocusNode = FocusNode();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial?.name ?? '');
    _colors = TextEditingController(
      text: widget.initial?.colors.join(', ') ?? '',
    );
    _sizes = TextEditingController(
      text: widget.initial?.sizes.join(', ') ?? '',
    );
  }

  @override
  void dispose() {
    _nameFocusNode.dispose();
    _name.dispose();
    _colors.dispose();
    _sizes.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool addAnother}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    List<String> parse(TextEditingController controller) => controller.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    final product = Product(
      id: widget.initial?.id,
      name: _name.text.trim(),
      materials: widget.initial?.materials ?? [],
      colors: widget.initial?.colors ?? parse(_colors),
      sizes: widget.initial?.sizes ?? parse(_sizes),
      variants: widget.initial?.variants ?? [],
      img: widget.initial?.img ?? '',
      stock: widget.initial?.stock,
    );
    try {
      await widget.onSave(product);
      if (!mounted) return;
      if (addAnother) {
        _name.clear();
        _colors.clear();
        _sizes.clear();
        _formKey.currentState!.reset();
      } else {
        Navigator.pop(context);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        if (addAnother) _nameFocusNode.requestFocus();
      }
    }
  }

  Widget _variantField({
    required TextEditingController controller,
    required String hint,
  }) => _liquidInputSurface(
    showBorder: false,
    minHeight: 40,
    verticalPadding: 0,
    child: Transform.translate(
      offset: const Offset(0, 7),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(addAnother: widget.initial == null),
        textAlignVertical: TextAlignVertical.center,
        style: const TextStyle(color: _ink, fontSize: 13, height: 1),
        decoration: InputDecoration(
          hintText: localizeAppText(hint),
          hintStyle: TextStyle(color: Color(0xff8da0ae), fontSize: 13),
          filled: false,
          isCollapsed: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final isNew = widget.initial == null;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: MediaQuery.sizeOf(context).height * .9,
        ),
        child: _FrostedSurface(
          borderRadius: BorderRadius.circular(26),
          tintColor: _popupTintColor,
          tintOpacity: _popupTintOpacity,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
          blurSigma: 26,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppText(
                          isNew ? 'Produk baru' : 'Ubah produk',
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _PopIconButton(
                        tooltip: localizeAppText('Tutup'),
                        visualDensity: VisualDensity.compact,
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        icon: const Icon(Icons.close, size: 18),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: .56),
                          foregroundColor: _muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _textField(
                    _name,
                    'Nama produk',
                    hint: 'mis. Tote Bag Kanvas',
                    autofocus: true,
                    focusNode: _nameFocusNode,
                    textOffset: const Offset(0, 6),
                    inputVerticalPadding: 0,
                    onSubmitted: () => _submit(addAnother: isNew),
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? 'Wajib diisi' : null,
                  ),
                  if (isNew) ...[
                    const SizedBox(height: 12),
                    const AppText(
                      'Warna',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                    const SizedBox(height: 5),
                    _variantField(
                      controller: _colors,
                      hint: 'mis. Hitam, Cokelat',
                    ),
                    const SizedBox(height: 10),
                    const AppText(
                      'Ukuran',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                    const SizedBox(height: 5),
                    _variantField(
                      controller: _sizes,
                      hint: 'mis. L, XL atau 38, 40',
                    ),
                    const SizedBox(height: 12),
                    const AppText(
                      'Varian opsional. Pisahkan beberapa warna atau ukuran dengan koma. Bisa diubah nanti di detail produk.',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ImportDialogPill(
                          label: 'Batal',
                          labelOffset: -1,
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                        ),
                        if (isNew)
                          _ImportDialogPill(
                            label: 'Simpan & tambah lagi',
                            labelOffset: -1,
                            onPressed: _saving
                                ? null
                                : () => _submit(addAnother: true),
                          ),
                        _ImportDialogPill(
                          label: 'Simpan',
                          blue: true,
                          labelOffset: -1,
                          onPressed: _saving
                              ? null
                              : () => _submit(addAnother: false),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductMaterialAdder extends StatefulWidget {
  const _ProductMaterialAdder({required this.catalog, required this.onAdd});

  final List<MaterialCost> catalog;
  final Future<void> Function(MaterialCost material) onAdd;

  @override
  State<_ProductMaterialAdder> createState() => _ProductMaterialAdderState();
}

class _ProductMaterialAdderState extends State<_ProductMaterialAdder> {
  final _name = TextEditingController();
  final _unit = TextEditingController();
  final _price = TextEditingController();
  final _qty = TextEditingController(text: '1');
  String? _selectedId;
  bool _manual = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _manual = widget.catalog.isEmpty;
    _selectedId = widget.catalog.firstOrNull?.id;
  }

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _price.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final qty = _parseDecimal(_qty.text);
    if (qty <= 0) return;
    MaterialCost material;
    if (_manual) {
      final name = _name.text.trim();
      if (name.isEmpty) return;
      material = MaterialCost(
        name: name,
        qty: qty,
        unit: _unit.text.trim(),
        price: _parseAmount(_price.text),
      );
    } else {
      final selected = widget.catalog
          .where((item) => item.id == _selectedId)
          .firstOrNull;
      if (selected == null) return;
      material = MaterialCost(
        name: selected.name,
        qty: qty,
        unit: selected.unit,
        price: selected.price,
        ref: selected.id,
      );
    }

    setState(() => _saving = true);
    try {
      await widget.onAdd(material);
      if (!mounted) return;
      _qty.text = '1';
      if (_manual) {
        _name.clear();
        _unit.clear();
        _price.clear();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _quantityField() => SizedBox(
    height: 35,
    child: _liquidInputSurface(
      minHeight: 35,
      child: Transform.translate(
        offset: const Offset(0, -4),
        child: TextField(
          controller: _qty,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _add(),
          textAlign: TextAlign.end,
          textAlignVertical: TextAlignVertical.center,
          style: const TextStyle(color: _ink, fontSize: 13, height: 1),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            constraints: BoxConstraints(minHeight: 35),
            hintText: localizeAppText('Qty'),
            hintStyle: TextStyle(color: Color(0xff8da0ae), fontSize: 13),
            filled: false,
            isCollapsed: true,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
        ),
      ),
    ),
  );

  Widget _catalogField() => _stockDropdown(
    value: _selectedId ?? '',
    label: null,
    height: 35,
    options: [
      for (final material in widget.catalog)
        (
          material.id,
          '${material.name} · ${material.unit} · ${formatMoney(material.price)}',
        ),
    ],
    onChanged: (value) => setState(() => _selectedId = value),
  );

  bool get _canAdd {
    if (_saving || _parseDecimal(_qty.text) <= 0) return false;
    if (_manual) return _name.text.trim().isNotEmpty;
    return widget.catalog.any((item) => item.id == _selectedId);
  }

  Widget _manualField(
    TextEditingController controller,
    String hint, {
    TextInputType? keyboard,
    TextAlign textAlign = TextAlign.start,
    bool groupThousands = false,
    VoidCallback? onSubmitted,
  }) => SizedBox(
    height: 35,
    child: _liquidInputSurface(
      minHeight: 35,
      child: Transform.translate(
        offset: const Offset(0, -4),
        child: TextField(
          controller: controller,
          keyboardType: keyboard,
          textAlign: textAlign,
          textInputAction: onSubmitted == null ? null : TextInputAction.done,
          onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
          textAlignVertical: TextAlignVertical.center,
          style: const TextStyle(color: _ink, fontSize: 13, height: 1),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            constraints: const BoxConstraints(minHeight: 35),
            hintText: localizeAppText(hint),
            hintStyle: const TextStyle(color: Color(0xff8da0ae), fontSize: 13),
            filled: false,
            isCollapsed: true,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          inputFormatters: groupThousands
              ? [_GroupedIntegerInputFormatter()]
              : null,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _LiquidGlassTabBar(
        tabs: const [
          ('catalog', 'Pilih dari Bahan Baku'),
          ('manual', 'Tambah manual'),
        ],
        equalWidths: true,
        selectedValue: _manual ? 'manual' : 'catalog',
        onSelected: (value) => setState(() => _manual = value == 'manual'),
      ),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, constraints) {
          final canFitManualRow = constraints.maxWidth >= 640;
          final canFitCatalogRow = constraints.maxWidth >= 540;
          final addButton = SizedBox(
            height: 38,
            child: _ImportDialogPill(
              label: 'Tambah',
              labelOffset: -1,
              onPressed: _canAdd ? _add : null,
              blue: true,
            ),
          );
          if (_manual) {
            final fields = canFitManualRow
                ? Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 159,
                            child: _manualField(
                              _name,
                              'Nama bahan / biaya',
                              onSubmitted: _add,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 35,
                            child: _manualField(
                              _qty,
                              'Qty',
                              textAlign: TextAlign.center,
                              keyboard: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              onSubmitted: _add,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 53,
                            child: _manualField(
                              _unit,
                              'Satuan',
                              onSubmitted: _add,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 53,
                            child: _manualField(
                              _price,
                              'Harga satuan',
                              keyboard: TextInputType.number,
                              groupThousands: true,
                              onSubmitted: _add,
                            ),
                          ),
                          const SizedBox(width: 8),
                          addButton,
                        ],
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 33,
                            child: _manualField(
                              _name,
                              'Nama bahan / biaya',
                              onSubmitted: _add,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 7,
                            child: _manualField(
                              _qty,
                              'Qty',
                              textAlign: TextAlign.center,
                              keyboard: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              onSubmitted: _add,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _manualField(
                              _unit,
                              'Satuan',
                              onSubmitted: _add,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Expanded(child: SizedBox.shrink()),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _manualField(
                              _price,
                              'Harga satuan',
                              keyboard: TextInputType.number,
                              groupThousands: true,
                              onSubmitted: _add,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerRight, child: addButton),
                    ],
                  );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [fields],
            );
          }

          final catalogField = _catalogField();
          final quantityField = _quantityField();
          if (canFitCatalogRow) {
            return Row(
              children: [
                Expanded(child: catalogField),
                const SizedBox(width: 8),
                SizedBox(width: 155, child: quantityField),
                const SizedBox(width: 8),
                addButton,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              catalogField,
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: quantityField),
                  const SizedBox(width: 8),
                  addButton,
                ],
              ),
            ],
          );
        },
      ),
    ],
  );
}

class _MaterialDialog extends StatefulWidget {
  const _MaterialDialog({
    this.initial,
    this.catalog = const [],
    this.category = MaterialCategory.bahanBaku,
  });

  final MaterialCost? initial;
  final List<MaterialCost> catalog;
  final MaterialCategory category;

  @override
  State<_MaterialDialog> createState() => _MaterialDialogState();
}

class _MaterialDialogState extends State<_MaterialDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _qty;
  late final TextEditingController _unit;
  late final TextEditingController _price;
  String _ref = '';

  @override
  void initState() {
    super.initState();
    final material = widget.initial;
    _name = TextEditingController(text: material?.name ?? '');
    _qty = TextEditingController(text: '${material?.qty.round() ?? 1}');
    _unit = TextEditingController(text: material?.unit ?? '');
    _price = TextEditingController(
      text: material == null
          ? ''
          : _formatAmountInput('${material.price.round()}'),
    );
    _ref = material?.ref ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _unit.dispose();
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final catalogItem = widget.catalog
        .where((item) => item.id == _ref)
        .firstOrNull;
    Navigator.pop(
      context,
      MaterialCost(
        id: widget.initial?.id,
        name: catalogItem?.name ?? _name.text.trim(),
        qty: _parseDecimal(_qty.text),
        unit: catalogItem?.unit ?? _unit.text.trim(),
        price: catalogItem?.price ?? _parseAmount(_price.text),
        ref: catalogItem?.id,
        category:
            catalogItem?.category ??
            widget.initial?.category ??
            widget.category,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.initial?.category ?? widget.category;
    final itemName = category == MaterialCategory.ongkosJahit
        ? 'ongkos jahit'
        : 'bahan';
    final title = '${widget.initial == null ? 'Tambah' : 'Ubah'} $itemName';
    return Center(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 440,
              maxHeight: MediaQuery.sizeOf(context).height * .9,
            ),
            child: Material(
              color: Colors.transparent,
              child: _FrostedSurface(
                borderRadius: BorderRadius.circular(26),
                tintColor: _popupTintColor,
                tintOpacity: _popupTintOpacity,
                padding: const EdgeInsets.all(24),
                blurSigma: 18,
                prominentShadow: true,
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: AppText(
                                title,
                                style: const TextStyle(
                                  color: _ink,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                            _PopIconButton(
                              tooltip: localizeAppText('Tutup'),
                              onPressed: () => Navigator.pop(context),
                              style: IconButton.styleFrom(
                                foregroundColor: _muted,
                                backgroundColor: Colors.white.withValues(
                                  alpha: .44,
                                ),
                                minimumSize: const Size(32, 32),
                                padding: EdgeInsets.zero,
                              ),
                              icon: const Icon(Icons.close, size: 17),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (widget.catalog.isNotEmpty)
                          DropdownButtonFormField<String>(
                            initialValue:
                                widget.catalog.any((item) => item.id == _ref)
                                ? _ref
                                : '',
                            decoration: InputDecoration(
                              labelText: localizeAppText(
                                'Pilih bahan tersimpan',
                              ),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: AppText('Isi bahan secara manual'),
                              ),
                              for (final material in widget.catalog)
                                DropdownMenuItem(
                                  value: material.id,
                                  child: AppText(
                                    '${material.name} · ${formatMoney(material.price)}',
                                  ),
                                ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _ref = value ?? '';
                                if (_ref.isNotEmpty) {
                                  final item = widget.catalog.firstWhere(
                                    (entry) => entry.id == _ref,
                                  );
                                  _name.text = item.name;
                                  _unit.text = item.unit;
                                  _price.text = _formatAmountInput(
                                    '${item.price.round()}',
                                  );
                                }
                              });
                            },
                          ),
                        if (widget.catalog.isNotEmpty)
                          const SizedBox(height: 10),
                        _textField(
                          _name,
                          'Nama bahan / biaya',
                          textOffset: const Offset(0, 8),
                          inputVerticalPadding: 0,
                          onSubmitted: _submit,
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? 'Wajib diisi'
                              : null,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _textField(
                                _qty,
                                'Qty',
                                textOffset: const Offset(0, 8),
                                inputVerticalPadding: 0,
                                keyboard: TextInputType.number,
                                integerOnly: true,
                                onSubmitted: _submit,
                                validator: (value) =>
                                    _parseDecimal(value ?? '') <= 0
                                    ? 'Qty > 0'
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _textField(
                                _unit,
                                'Satuan',
                                textOffset: const Offset(0, 7),
                                inputVerticalPadding: 0,
                                onSubmitted: _submit,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _textField(
                          _price,
                          'Harga satuan (Rp)',
                          textOffset: const Offset(0, 7),
                          inputVerticalPadding: 0,
                          keyboard: TextInputType.number,
                          groupThousands: true,
                          onSubmitted: _submit,
                        ),
                        const SizedBox(height: 22),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _ImportDialogPill(
                              label: 'Batal',
                              labelOffset: -2,
                              onPressed: () => Navigator.pop(context),
                            ),
                            const SizedBox(width: 8),
                            _ImportDialogPill(
                              label: 'Simpan',
                              blue: true,
                              labelOffset: -2,
                              onPressed: _submit,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final _pillFocusSide = WidgetStateProperty.resolveWith<BorderSide?>((states) {
  if (states.contains(WidgetState.focused)) {
    return const BorderSide(color: _blue, width: 1.5);
  }
  return BorderSide.none;
});

final _pillFocusOverlay = WidgetStateProperty.resolveWith<Color?>((states) {
  if (states.contains(WidgetState.focused)) {
    return _blue.withValues(alpha: .12);
  }
  return Colors.transparent;
});

class _PillFocusIndicator extends StatefulWidget {
  const _PillFocusIndicator({required this.child});

  final Widget child;

  @override
  State<_PillFocusIndicator> createState() => _PillFocusIndicatorState();
}

class _PillFocusIndicatorState extends State<_PillFocusIndicator> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(canRequestFocus: false, skipTraversal: true)
      ..addListener(_handleFocusChange);
  }

  void _handleFocusChange() => setState(() {});

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focusNode,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: _focusNode.hasFocus ? _blue : Colors.transparent,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _liquidInputSurface({
  required Widget child,
  bool showBorder = true,
  double minHeight = 40,
  double verticalPadding = 9,
}) => _LiquidInputSurface(
  showBorder: showBorder,
  minHeight: minHeight,
  verticalPadding: verticalPadding,
  child: child,
);

class _LiquidInputSurface extends StatefulWidget {
  const _LiquidInputSurface({
    required this.child,
    required this.showBorder,
    required this.minHeight,
    required this.verticalPadding,
  });

  final Widget child;
  final bool showBorder;
  final double minHeight;
  final double verticalPadding;

  @override
  State<_LiquidInputSurface> createState() => _LiquidInputSurfaceState();
}

class _LiquidInputSurfaceState extends State<_LiquidInputSurface> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(canRequestFocus: false, skipTraversal: true)
      ..addListener(_handleFocusChange);
  }

  void _handleFocusChange() => setState(() {});

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focusNode,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(99)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1421423a),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: _windowAwareBlur(
          sigmaX: 18,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: .72),
                  const Color(0xffe6f4fb).withValues(alpha: .68),
                ],
              ),
              border: Border.all(
                color: _focusNode.hasFocus
                    ? _blue
                    : widget.showBorder
                    ? Colors.white.withValues(alpha: .48)
                    : Colors.transparent,
                width: _focusNode.hasFocus ? 1.5 : 1,
              ),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: widget.minHeight),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: widget.verticalPadding,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Transform.translate(
                    offset: const Offset(0, 2),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _textField(
  TextEditingController controller,
  String? label, {
  TextInputType? keyboard,
  bool groupThousands = false,
  bool integerOnly = false,
  bool positiveDecimalOnly = false,
  String? suffixText,
  String? hint,
  bool autofocus = false,
  FocusNode? focusNode,
  double fontSize = 13,
  Offset textOffset = Offset.zero,
  double inputVerticalPadding = 9,
  String? helper,
  String? Function(String?)? validator,
  FormFieldErrorBuilder? errorBuilder,
  VoidCallback? onSubmitted,
}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    if (label != null)
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 5),
        child: AppText(
          label,
          style: const TextStyle(
            color: _muted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    _liquidInputSurface(
      verticalPadding: inputVerticalPadding,
      child: Transform.translate(
        offset: Offset(textOffset.dx, textOffset.dy + 1),
        child: TextFormField(
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          keyboardType: keyboard,
          textInputAction: onSubmitted == null ? null : TextInputAction.done,
          onFieldSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
          textAlignVertical: TextAlignVertical.center,
          style: TextStyle(
            color: _ink,
            fontFamily: 'Inter',
            fontSize: fontSize,
            height: 1,
          ),
          validator: validator,
          errorBuilder: errorBuilder,
          decoration: InputDecoration(
            hintText: hint == null ? null : localizeAppText(hint),
            hintStyle: TextStyle(
              color: const Color(0xff8da0ae),
              fontSize: fontSize,
            ),
            suffixText: suffixText,
            suffixStyle: const TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            filled: false,
            isCollapsed: true,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          inputFormatters: groupThousands
              ? [_GroupedIntegerInputFormatter()]
              : integerOnly
              ? [FilteringTextInputFormatter.digitsOnly]
              : positiveDecimalOnly
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
              : null,
        ),
      ),
    ),
    if (helper != null) ...[
      const SizedBox(height: 4),
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: AppText(
          helper,
          style: const TextStyle(color: _muted, fontSize: 11),
        ),
      ),
    ],
  ],
);

class _FrostedDropdownOption extends StatelessWidget {
  const _FrostedDropdownOption({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(99),
          hoverColor: Colors.white.withValues(alpha: .48),
          splashColor: Colors.white.withValues(alpha: .3),
          onTap: onTap,
          child: SizedBox(
            width: double.infinity,
            height: 40,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: AppText.raw(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _ink, fontSize: 13),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _stockDropdown({
  required String? label,
  required String value,
  required List<(String, String)> options,
  required ValueChanged<String> onChanged,
  double height = 44,
}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    if (label != null)
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 5),
        child: AppText(
          label,
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
      ),
    SizedBox(
      height: height,
      child: Builder(
        builder: (fieldContext) => _ButtonPop(
          enabled: options.isNotEmpty,
          intensity: .5,
          normalizeScaleByWidth: true,
          child: _liquidInputSurface(
            showBorder: false,
            minHeight: height,
            verticalPadding: 0,
            child: SizedBox.expand(
              child: InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: options.isEmpty
                    ? null
                    : () async {
                        final renderObject = fieldContext.findRenderObject();
                        final overlayObject = Overlay.of(fieldContext).context
                            .findRenderObject();
                        if (renderObject is! RenderBox ||
                            overlayObject is! RenderBox) {
                          throw StateError(
                            'Tidak bisa menentukan posisi pilihan $label.',
                          );
                        }
                        final origin = renderObject.localToGlobal(
                          Offset.zero,
                          ancestor: overlayObject,
                        );
                        final rect = origin & renderObject.size;
                        final availableHeight =
                            overlayObject.size.height - rect.bottom - 8;
                        if (availableHeight <= 0) {
                          throw StateError(
                            'Tidak ada ruang untuk membuka pilihan ${label ?? value}.',
                          );
                        }
                        final menuWidth = renderObject.size.width
                            .clamp(0.0, overlayObject.size.width - 16)
                            .toDouble();
                        final menuLeft = (rect.center.dx - menuWidth / 2)
                            .clamp(
                              8.0,
                              overlayObject.size.width - menuWidth - 8,
                            )
                            .toDouble();
                        final selected = await showGeneralDialog<String>(
                          context: fieldContext,
                          useRootNavigator: false,
                          barrierDismissible: true,
                          barrierLabel: MaterialLocalizations.of(fieldContext)
                              .modalBarrierDismissLabel,
                          barrierColor: Colors.transparent,
                          transitionDuration: const Duration(milliseconds: 240),
                          pageBuilder:
                              (
                                dialogContext,
                                animation,
                                secondaryAnimation,
                              ) => Stack(
                                children: [
                                  Positioned(
                                    left: menuLeft,
                                    top: rect.bottom,
                                    width: menuWidth,
                                    child: ClipRect(
                                      child: SizeTransition(
                                        axis: Axis.vertical,
                                        alignment: Alignment.topCenter,
                                        sizeFactor: CurvedAnimation(
                                          parent: animation,
                                          curve: Curves.easeOutCubic,
                                          reverseCurve: Curves.easeInCubic,
                                        ),
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxHeight: availableHeight,
                                          ),
                                          child: _FrostedSurface(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            tintColor: _popupTintColor,
                                            tintOpacity: .82,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 4,
                                            ),
                                            blurSigma: 18,
                                            child: SingleChildScrollView(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  for (final option in options)
                                                    _FrostedDropdownOption(
                                                      label: option.$2,
                                                      onTap: () =>
                                                          Navigator.pop(
                                                            dialogContext,
                                                            option.$1,
                                                          ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                        );
                        if (selected == null || !fieldContext.mounted) return;
                        onChanged(selected);
                      },
                child: Row(
                  children: [
                    Expanded(
                      child: Transform.translate(
                        offset: const Offset(0, -2),
                        child: AppText(
                          options
                                  .where((option) => option.$1 == value)
                                  .firstOrNull
                                  ?.$2 ??
                              '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _ink, fontSize: 13),
                        ),
                      ),
                    ),
                    Transform.translate(
                      offset: const Offset(0, -1),
                      child: const Icon(Icons.arrow_drop_down, color: _muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ],
);

String _formatAmountInput(String value) {
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]}.',
  );
}

class _FrostedCalendarDialog extends StatefulWidget {
  const _FrostedCalendarDialog({required this.initialDate});

  final DateTime initialDate;

  @override
  State<_FrostedCalendarDialog> createState() => _FrostedCalendarDialogState();
}

class _FrostedCalendarDialogState extends State<_FrostedCalendarDialog> {
  late DateTime _selectedDate;
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _visibleMonth = DateTime(widget.initialDate.year, widget.initialDate.month);
  }

  void _changeMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
  }

  @override
  Widget build(BuildContext context) => _FrostedSurface(
    borderRadius: BorderRadius.circular(28),
    tintColor: _popupTintColor,
    tintOpacity: _popupTintOpacity,
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
    blurSigma: 14,
    prominentShadow: true,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: AppText(
                MaterialLocalizations.of(context)
                    .formatMonthYear(_visibleMonth),
                style: const TextStyle(
                  color: _ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _PopIconButton(
              tooltip: localizeAppText('Bulan sebelumnya'),
              onPressed: () => _changeMonth(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            const SizedBox(width: 4),
            _PopIconButton(
              tooltip: localizeAppText('Bulan berikutnya'),
              onPressed: () => _changeMonth(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final day in ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'])
              Expanded(
                child: Center(
                  child: AppText(
                    day,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        _buildMonthGrid(),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _ImportDialogPill(
              label: 'Batal',
              labelOffset: 0,
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 8),
            _ImportDialogPill(
              label: 'Pilih',
              blue: true,
              labelOffset: 0,
              onPressed: () => Navigator.pop(context, _selectedDate),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _buildMonthGrid() {
    final firstWeekday = DateTime(
      _visibleMonth.year,
      _visibleMonth.month,
      1,
    ).weekday;
    final daysInMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    ).day;
    final cellCount = ((firstWeekday - 1 + daysInMonth + 6) ~/ 7) * 7;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisExtent: 42,
      ),
      itemCount: cellCount,
      itemBuilder: (context, index) {
        final day = index - firstWeekday + 2;
        if (day < 1 || day > daysInMonth) return const SizedBox.shrink();
        final date = DateTime(_visibleMonth.year, _visibleMonth.month, day);
        final selected =
            date.year == _selectedDate.year &&
            date.month == _selectedDate.month &&
            date.day == _selectedDate.day;
        return Padding(
          padding: const EdgeInsets.all(2),
          child: _ButtonPop(
            intensity: .45,
            child: Material(
              color: selected ? _blue : Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => _selectedDate = date),
                child: Center(
                  child: AppText(
                    '$day',
                    style: TextStyle(
                      color: selected ? Colors.white : _ink,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GroupedIntegerInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = _formatAmountInput(newValue.text);
    if (!newValue.selection.isValid) {
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }

    int formattedOffset(int originalOffset) {
      final safeOffset = originalOffset.clamp(0, newValue.text.length);
      final digitCount = newValue.text
          .substring(0, safeOffset)
          .replaceAll(RegExp(r'[^0-9]'), '')
          .length;
      if (digitCount == 0) return 0;

      var foundDigits = 0;
      for (var index = 0; index < formatted.length; index++) {
        if (formatted.codeUnitAt(index) >= 48 &&
            formatted.codeUnitAt(index) <= 57) {
          foundDigits++;
        }
        if (foundDigits == digitCount) return index + 1;
      }
      return formatted.length;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection(
        baseOffset: formattedOffset(newValue.selection.baseOffset),
        extentOffset: formattedOffset(newValue.selection.extentOffset),
        affinity: newValue.selection.affinity,
        isDirectional: newValue.selection.isDirectional,
      ),
      composing: TextRange.empty,
    );
  }
}

double _parseDecimal(String value) =>
    double.tryParse(value.replaceAll(',', '.').trim()) ?? 0;

double _parseAmount(String value) =>
    double.tryParse(value.replaceAll('.', '').replaceAll(',', '').trim()) ?? 0;
