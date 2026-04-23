import 'dart:io' show Platform;

import 'package:desktop_window_bootstrap/desktop_window_bootstrap.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('desktop_window_bootstrap/methods');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  testWidgets(
    'keeps the latest titlebar inset when refreshes resolve out of order',
    (tester) async {
      if (!Platform.isMacOS) {
        return;
      }

      var getTitlebarInsetCallCount = 0;
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) {
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
              _ => 20,
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
}

double _topPadding(WidgetTester tester) {
  final padding = tester.widget<Padding>(find.byType(Padding));
  return (padding.padding as EdgeInsets).top;
}
