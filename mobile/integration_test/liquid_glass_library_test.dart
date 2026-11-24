import 'dart:io';
import 'dart:ui' as ui;
import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/domain/library_seats.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:campus_schedule/ui/library_seat_bookings.dart';
import 'package:campus_schedule/ui/library_seat_query_page.dart';
import 'package:campus_schedule/ui/liquid_glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/library_seat_queries_test.dart'
    show FakeLibrarySeatReader, seat, enterLibraryArea, reveal;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'library focus optics preserve candidate selection without writes',
    (tester) async {
      expect(ui.ImageFilter.isShaderFilterSupported, isTrue);
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/liquid_glass.frag',
      );
      const booking = LibraryBooking(
        'synthetic-booking',
        '合成区域',
        'N001',
        '2099-10-10 10:00',
        '2099-10-10 12:00',
        2,
      );
      for (final dark in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          final reader = FakeLibrarySeatReader();
          reader.onSeats = (_, _) async => [seat(id: '1', label: 'N001')];
          reader.onBookings = (_, _, page) async =>
              LibraryBookingPage([booking], false, page: page, totalCount: 1);
          final capture = GlobalKey();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                currentAppearanceProvider.overrideWithValue(
                  const AppearanceSettings(),
                ),
                liquidGlassProgramProvider.overrideWith((ref) async => program),
              ],
              child: MaterialApp(
                theme: appTheme(dark ? Brightness.dark : Brightness.light),
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                supportedLocales: const [Locale('zh', 'CN')],
                locale: const Locale('zh', 'CN'),
                builder: (context, child) => MiuixThemeBridge(child: child!),
                home: Center(
                  child: SizedBox(
                    width: 320,
                    height: 720,
                    child: MediaQuery(
                      data: MediaQueryData(
                        textScaler: TextScaler.linear(scale),
                        disableAnimations: true,
                      ),
                      child: RepaintBoundary(
                        key: capture,
                        child: LibrarySeatQueryPage(
                          key: UniqueKey(),
                          reader: reader,
                          now: () => DateTime(2099, 10, 10, 9),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await enterLibraryArea(tester);
          await reveal(tester, find.text('N001'));
          await tester.tap(find.text('N001'));
          await tester.pumpAndSettle();
          final capsule = find.byKey(
            const ValueKey('library-selected-capsule'),
          );
          expect(
            find.descendant(
              of: capsule,
              matching: find.byType(LiquidGlassSurface),
            ),
            findsOneWidget,
          );
          expect(tester.getSize(capsule).height.isFinite, isTrue);
          if (scale == 2) {
            final paragraphs = find.descendant(
              of: capsule,
              matching: find.byType(RichText),
            );
            for (final element in paragraphs.evaluate()) {
              final paragraph = element.renderObject! as RenderParagraph;
              expect(paragraph.didExceedMaxLines, isFalse);
            }
          }
          expect(tester.takeException(), isNull);
          await captureLibrary(tester, capture, 'capsule', dark, scale);
          await tester.tap(find.byTooltip('清除选择'));
          await tester.pumpAndSettle();
          expect(capsule, findsNothing);
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, 800),
          );
          await tester.pumpAndSettle();
          await reveal(tester, find.text('我的预约'));
          await tester.tap(find.text('我的预约'));
          await tester.pumpAndSettle();
          final ticket = find.byType(LibraryBookingFocusTicket);
          await reveal(tester, ticket);
          expect(
            find.descendant(
              of: ticket,
              matching: find.byType(LiquidGlassSurface),
            ),
            findsOneWidget,
          );
          expect(tester.getSize(ticket).height.isFinite, isTrue);
          expect(tester.takeException(), isNull);
          await captureLibrary(tester, capture, 'ticket', dark, scale);
          expect(reader.reserveCalls, 0);
          expect(reader.cancelCalls, 0);
          await tester.pumpWidget(const SizedBox());
        }
      }
    },
  );
}

Future<void> captureLibrary(
  WidgetTester tester,
  GlobalKey capture,
  String role,
  bool dark,
  double scale,
) async {
  await tester.runAsync(() async {
    final boundary =
        capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '${Directory.systemTemp.path}/liquid-library-$role-${dark ? 'dark' : 'light'}-$scale.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
