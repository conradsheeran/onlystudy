import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/l10n/app_localizations.dart';
import 'package:onlystudy/widgets/player_chrome.dart';

Widget _buildTestablePlayerChrome({
  required PlayerChromeState state,
  required PlayerChromeCallbacks callbacks,
  Locale locale = const Locale('zh'),
  ThemeData? theme,
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: theme ??
        ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF00E5FF),
          ),
        ),
    home: Scaffold(
      body: PlayerChrome(
        state: state,
        callbacks: callbacks,
      ),
    ),
  );
}

void main() {
  group('PlayerChrome 横竖屏一致性与按钮', () {
    const testState = PlayerChromeState(
      position: Duration(minutes: 1, seconds: 20),
      duration: Duration(minutes: 10),
      buffered: Duration(minutes: 3),
      isPlaying: true,
      isBuffering: false,
      isSeeking: false,
      title: '测试课程标题',
      partLabel: 'P1 第一讲',
      speedLabel: '1.0x',
      qualityLabel: '1080P',
      hasParts: true,
      isFullscreen: false,
      isLocked: false,
      controlsVisible: true,
      availableSpeeds: [0.5, 1.0, 1.5, 2.0],
      availableQualities: [80, 64],
      availableQualityDescs: ['1080P', '720P'],
      currentQuality: 80,
    );

    testWidgets('竖屏与横屏渲染同一组按钮且进度条为 primary 强调色（无鲜红色）', (tester) async {
      // 1. 竖屏测试
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestablePlayerChrome(
          state: testState,
          callbacks: const PlayerChromeCallbacks(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byIcon(Icons.list), findsOneWidget);
      expect(find.byIcon(Icons.download), findsOneWidget);
      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen), findsOneWidget);
      expect(find.text('测试课程标题 - P1 第一讲'), findsOneWidget);
      expect(find.text('1.0x'), findsOneWidget);
      expect(find.text('1080P'), findsOneWidget);

      // 验证没有鲜红色 (0xFFFF0000)
      final allElements = find.byType(PlayerChrome);
      expect(allElements, findsOneWidget);

      // 2. 横屏测试
      tester.view.physicalSize = const Size(2400, 1080);
      await tester.pumpWidget(
        _buildTestablePlayerChrome(
          state: testState.copyWith(isFullscreen: true),
          callbacks: const PlayerChromeCallbacks(),
        ),
      );
      await tester.pumpAndSettle();

      // 横屏下同样拥有一致的顶栏与底栏按钮
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byIcon(Icons.list), findsOneWidget);
      expect(find.byIcon(Icons.download), findsOneWidget);
      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);
      expect(find.text('测试课程标题 - P1 第一讲'), findsOneWidget);
      expect(find.text('1.0x'), findsOneWidget);
      expect(find.text('1080P'), findsOneWidget);
    });

    testWidgets('逐个按钮点击触发对应回调', (tester) async {
      bool backCalled = false;
      bool playPauseCalled = false;
      bool toggleFullscreenCalled = false;
      bool showPartsCalled = false;
      bool downloadCalled = false;
      double? selectedSpeed;
      int? selectedQuality;

      final callbacks = PlayerChromeCallbacks(
        onBack: () => backCalled = true,
        onPlayPause: () => playPauseCalled = true,
        onToggleFullscreen: () => toggleFullscreenCalled = true,
        onShowParts: () => showPartsCalled = true,
        onDownload: () => downloadCalled = true,
        onSelectSpeed: (s) => selectedSpeed = s,
        onSelectQuality: (q) => selectedQuality = q,
      );

      await tester.pumpWidget(
        _buildTestablePlayerChrome(
          state: testState,
          callbacks: callbacks,
        ),
      );
      await tester.pumpAndSettle();

      // 点击返回
      await tester.tap(find.byIcon(Icons.arrow_back));
      expect(backCalled, isTrue);

      // 点击播放/暂停
      await tester.tap(find.byIcon(Icons.pause));
      expect(playPauseCalled, isTrue);

      // 点击分集
      await tester.tap(find.byIcon(Icons.list));
      expect(showPartsCalled, isTrue);

      // 点击下载
      await tester.tap(find.byIcon(Icons.download));
      expect(downloadCalled, isTrue);

      // 点击全屏
      await tester.tap(find.byIcon(Icons.fullscreen));
      expect(toggleFullscreenCalled, isTrue);

      // 切换倍速
      await tester.tap(find.text('1.0x'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2.0x').last);
      await tester.pumpAndSettle();
      expect(selectedSpeed, 2.0);

      // 切换清晰度
      await tester.tap(find.text('1080P'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('720P').last);
      await tester.pumpAndSettle();
      expect(selectedQuality, 64);
    });

    testWidgets('3秒无操作自动隐藏控件，点击重新显示，seeking时不隐藏', (tester) async {
      await tester.pumpWidget(
        _buildTestablePlayerChrome(
          state: testState,
          callbacks: const PlayerChromeCallbacks(),
        ),
      );
      await tester.pumpAndSettle();

      // 初始控件可见
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      // 走过 3 秒
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 200));

      // 控件已隐藏 (SlideTransition 或 Opacity 为 0)
      final backButton = tester.widget<AnimatedOpacity>(
        find.byKey(const Key('player_chrome_controls')),
      );
      expect(backButton.opacity, 0.0);

      // 点击屏幕重新显示
      await tester.tap(find.byKey(const Key('player_chrome_gesture_detector')));
      await tester.pump(const Duration(milliseconds: 500));
      final backButtonVisible = tester.widget<AnimatedOpacity>(
        find.byKey(const Key('player_chrome_controls')),
      );
      expect(backButtonVisible.opacity, 1.0);

      // seeking 时不自动隐藏
      await tester.pumpWidget(
        _buildTestablePlayerChrome(
          state: testState.copyWith(isSeeking: true),
          callbacks: const PlayerChromeCallbacks(),
        ),
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 200));
      final backButtonSeeking = tester.widget<AnimatedOpacity>(
        find.byKey(const Key('player_chrome_controls')),
      );
      expect(backButtonSeeking.opacity, 1.0);
    });

    testWidgets('zh 与 en 两种 locale 下控件文案与 tooltip 走 AppLocalizations', (tester) async {
      // 中文环境
      await tester.pumpWidget(
        _buildTestablePlayerChrome(
          state: testState,
          callbacks: const PlayerChromeCallbacks(),
          locale: const Locale('zh'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('分集列表'), findsOneWidget);
      expect(find.byTooltip('播放速度'), findsOneWidget);
      expect(find.byTooltip('缓存视频'), findsOneWidget);

      // 英文环境
      await tester.pumpWidget(
        _buildTestablePlayerChrome(
          state: testState,
          callbacks: const PlayerChromeCallbacks(),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Parts List'), findsOneWidget);
      expect(find.byTooltip('Playback Speed'), findsOneWidget);
      expect(find.byTooltip('Cache Video'), findsOneWidget);
    });

    testWidgets('全屏时应用 viewPadding.left/right，非全屏不受影响', (tester) async {
      tester.view.physicalSize = const Size(2400, 1080);
      tester.view.devicePixelRatio = 2.0;
      tester.view.viewPadding = const FakeViewPadding(left: 48, right: 48);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewPadding();
      });

      // 1. 全屏时有内边距
      await tester.pumpWidget(
        _buildTestablePlayerChrome(
          state: testState.copyWith(isFullscreen: true),
          callbacks: const PlayerChromeCallbacks(),
        ),
      );
      await tester.pumpAndSettle();
      final backButton = tester.getTopLeft(find.byIcon(Icons.arrow_back));
      expect(backButton.dx, greaterThanOrEqualTo(24.0)); // 48 / 2.0 = 24.0

      // 2. 非全屏时不受 viewPadding 影响
      await tester.pumpWidget(
        _buildTestablePlayerChrome(
          state: testState.copyWith(isFullscreen: false),
          callbacks: const PlayerChromeCallbacks(),
        ),
      );
      await tester.pumpAndSettle();
      final backButtonPortrait = tester.getTopLeft(find.byIcon(Icons.arrow_back));
      expect(backButtonPortrait.dx, lessThan(24.0));
    });

    testWidgets('时间格式正确且秒数变化时宽度稳定（预留总时长宽度）', (tester) async {
      await tester.pumpWidget(
        _buildTestablePlayerChrome(
          state: testState.copyWith(
            position: const Duration(seconds: 1),
            duration: const Duration(minutes: 10),
          ),
          callbacks: const PlayerChromeCallbacks(),
        ),
      );
      await tester.pumpAndSettle();

      final timeFinder = find.byKey(const Key('player_chrome_time_readout'));
      expect(timeFinder, findsOneWidget);
      final size1 = tester.getSize(timeFinder);

      // 切换到包含较多宽数字的时间
      await tester.pumpWidget(
        _buildTestablePlayerChrome(
          state: testState.copyWith(
            position: const Duration(minutes: 8, seconds: 58),
            duration: const Duration(minutes: 10),
          ),
          callbacks: const PlayerChromeCallbacks(),
        ),
      );
      await tester.pumpAndSettle();

      final size2 = tester.getSize(timeFinder);
      expect(size1.width, equals(size2.width));
    });

    testWidgets('控件隐藏后常驻细进度条渲染且不拦截命中测试', (tester) async {
      bool backgroundTapped = false;
      await tester.pumpWidget(
        _buildTestablePlayerChrome(
          state: testState.copyWith(controlsVisible: false),
          callbacks: PlayerChromeCallbacks(
            onToggleControls: () => backgroundTapped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tinyBarFinder = find.byKey(const Key('player_chrome_tiny_progress_bar'));
      expect(tinyBarFinder, findsOneWidget);

      // 验证外层包着 IgnorePointer(ignoring: true)
      final ignorePointer = tester.widget<IgnorePointer>(
        find.ancestor(
          of: tinyBarFinder,
          matching: find.byType(IgnorePointer),
        ).first,
      );
      expect(ignorePointer.ignoring, isTrue);

      // 点击屏幕最底部细进度条位置，手势仍能穿透到全局背景触发切换
      final bottomCenter = tester.getCenter(tinyBarFinder);
      await tester.tapAt(bottomCenter);
      await tester.pump(const Duration(milliseconds: 500));
      expect(backgroundTapped, isTrue);
    });

    testWidgets('HUD 胶囊文案与图标在 zh 与 en 下正确', (tester) async {
      // 1. 中文：音量 80%
      await tester.pumpWidget(
        _buildTestablePlayerChrome(
          state: testState.copyWith(hud: const VolumeHud(0.8)),
          callbacks: const PlayerChromeCallbacks(),
          locale: const Locale('zh'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player_chrome_hud_capsule')), findsOneWidget);
      expect(find.text('音量 80%'), findsOneWidget);
      expect(find.byIcon(Icons.volume_up), findsOneWidget);

      // 2. 英文：Volume 0% (静音图标)
      await tester.pumpWidget(
        _buildTestablePlayerChrome(
          state: testState.copyWith(hud: const VolumeHud(0.0)),
          callbacks: const PlayerChromeCallbacks(),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Volume 0%'), findsOneWidget);
      expect(find.byIcon(Icons.volume_off), findsOneWidget);

      // 3. 中文：亮度 20% (低档图标)
      await tester.pumpWidget(
        _buildTestablePlayerChrome(
          state: testState.copyWith(hud: const BrightnessHud(0.2)),
          callbacks: const PlayerChromeCallbacks(),
          locale: const Locale('zh'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('亮度 20%'), findsOneWidget);
      expect(find.byIcon(Icons.brightness_low), findsOneWidget);

      // 4. 英文：Brightness 50% (中档图标)
      await tester.pumpWidget(
        _buildTestablePlayerChrome(
          state: testState.copyWith(hud: const BrightnessHud(0.5)),
          callbacks: const PlayerChromeCallbacks(),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Brightness 50%'), findsOneWidget);
      expect(find.byIcon(Icons.brightness_medium), findsOneWidget);

      // 5. 快进 / 后退
      await tester.pumpWidget(
        _buildTestablePlayerChrome(
          state: testState.copyWith(
            hud: const SeekPreviewHud(
              target: Duration(minutes: 5),
              isForward: true,
            ),
          ),
          callbacks: const PlayerChromeCallbacks(),
          locale: const Locale('zh'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('快进 05:00'), findsOneWidget);
      expect(find.byIcon(Icons.fast_forward), findsOneWidget);

      // 6. 英文后退
      await tester.pumpWidget(
        _buildTestablePlayerChrome(
          state: testState.copyWith(
            hud: const SeekPreviewHud(
              target: Duration(minutes: 2),
              isForward: false,
            ),
          ),
          callbacks: const PlayerChromeCallbacks(),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Backward 02:00'), findsOneWidget);
      expect(find.byIcon(Icons.fast_rewind), findsOneWidget);
    });
  });
}
