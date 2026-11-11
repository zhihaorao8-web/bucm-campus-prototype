import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:campus_schedule/platform/classroom_access.dart';
import 'package:campus_schedule/ui/classroom_course_page.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'schedule_test.dart' show sample;

// Render a synthetic login surface without a browser or school credentials.
class LoginSurfacePlatform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => LoginSurface(params);
}

class LoginSurface extends PlatformInAppWebViewWidget {
  LoginSurface(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => Text(
    params.initialUrlRequest?.url.toString() == vpnEntry
        ? '合成 WebVPN 登录界面'
        : '合成学校登录界面',
  );
  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      throw UnimplementedError();
  @override
  void dispose() {}
}

void main() {
  for (final directAvailable in [false, true]) {
    testWidgets('统一导入自动展示认证页，直连可用=$directAvailable', (tester) async {
      InAppWebViewPlatform.instance = LoginSurfacePlatform();
      final school = Course.fromJson(
        sample().toJson()..['dataSource'] = 'school',
      );
      final probes = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ClassroomCoursePage(
            course: school,
            importCourses: [school],
            onDetails: (_) {},
            probe: (url) async {
              probes.add(url);
              return AccessProbe(
                url == classroomProbe && !directAvailable
                    ? ProbeState.unavailable
                    : ProbeState.available,
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        probes,
        directAvailable ? [classroomProbe] : [classroomProbe, vpnEntry],
      );
      expect(find.text('学校官方页面'), findsOneWidget);
      expect(
        find.text(directAvailable ? '合成学校登录界面' : '合成 WebVPN 登录界面'),
        findsOneWidget,
      );
      expect(find.text('打开学校页面'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
  for (final dark in [false, true]) {
    testWidgets(
      'course secondary page preserves details and live placeholder dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final synthetic = Course.fromJson(
          sample().toJson()..['dataSource'] = 'synthetic',
        );
        var opened = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(dark ? Brightness.dark : Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: ClassroomCoursePage(
              course: synthetic,
              onDetails: (_) => opened = true,
            ),
          ),
        );
        expect(find.text('示例教师'), findsOneWidget);
        await tester.tap(find.text('查看完整课程信息'));
        expect(opened, isTrue);
        await tester.tap(find.text('直播'));
        await tester.pumpAndSettle();
        expect(find.textContaining('学校直播暂未开放'), findsOneWidget);
        expect(find.text('连接学校录播'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
