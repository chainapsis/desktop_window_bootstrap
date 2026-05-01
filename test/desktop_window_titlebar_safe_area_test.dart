import 'dart:io' show Platform;

import 'package:desktop_window_bootstrap/desktop_window_bootstrap.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('desktop_window_bootstrap/methods');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  testWidgets(
    'keeps the latest titlebar inset when refreshes resolve out of order',
    (tester) async {
      if (!Platform.isMacOS) {
        return;
      }

      var getTitlebarInsetCallCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            if (call.method != 'getTitlebarInset') {
              return null;
            }

            getTitlebarInsetCallCount += 1;
            return switch (getTitlebarInsetCallCount) {
              1 => Future<double>.delayed(
                const Duration(milliseconds: 40),
                () => 10,
              ),
              2 => Future<double>.delayed(
                const Duration(milliseconds: 10),
                () => 20,
              ),
              _ => 20.0,
            };
          });

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: DesktopWindowTitlebarSafeArea(child: SizedBox()),
        ),
      );
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: DesktopWindowTitlebarSafeArea(
            isEnabled: false,
            child: SizedBox(),
          ),
        ),
      );
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: DesktopWindowTitlebarSafeArea(child: SizedBox()),
        ),
      );

      await tester.pump(const Duration(milliseconds: 10));
      expect(_topPadding(tester), 20);

      await tester.pump(const Duration(milliseconds: 30));
      expect(_topPadding(tester), 20);
    },
    skip: !Platform.isMacOS,
  );

  test('forwards Windows client-area layout arguments', () async {
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          capturedCall = call;
          return true;
        });

    final applied = await DesktopWindowBootstrap.applyWindowsClientAreaLayout(
      windowSize: const Size(1080, 720),
      minimumWindowSize: const Size(1080, 720),
      contentTopInset: 32,
      resize: false,
      center: true,
    );

    expect(applied, isTrue);
    expect(capturedCall?.method, 'applyWindowsClientAreaLayout');
    final arguments = capturedCall?.arguments as Map<Object?, Object?>;
    expect(arguments['width'], 1080);
    expect(arguments['height'], 720);
    expect(arguments['minimumWidth'], 1080);
    expect(arguments['minimumHeight'], 720);
    expect(arguments['contentTopInset'], 32);
    expect(arguments['enforceAspectRatio'], isTrue);
    expect(arguments['resize'], isFalse);
    expect(arguments['center'], isTrue);
  }, skip: !Platform.isWindows);

  test('reads Windows client-area size', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          expect(call.method, 'getWindowsClientAreaSize');
          return <String, Object?>{'width': 1080.0, 'height': 688.0};
        });

    final size = await DesktopWindowBootstrap.getWindowsClientAreaSize();

    expect(size, const Size(1080, 688));
  }, skip: !Platform.isWindows);
}

double _topPadding(WidgetTester tester) {
  final padding = tester.widget<Padding>(find.byType(Padding));
  return (padding.padding as EdgeInsets).top;
}
