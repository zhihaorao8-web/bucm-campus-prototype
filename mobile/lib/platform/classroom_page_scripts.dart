import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../config/classroom_limits.dart';
import '../config/runtime_config.dart';
import 'classroom_api_reader.dart';
import 'test_diagnostics.dart';

/// Public adapter loading and bounded WebView results. Never reads credentials,
/// headers or WebView storage; commands remain the existing restricted protocol.
class ClassroomPageScripts {
  ClassroomPageScripts({AssetBundle? assets}) : assets = assets ?? rootBundle;
  final AssetBundle assets;
  String? _source, _entry;

  Future<Map<String, dynamic>> command(
    InAppWebViewController controller,
    Map<String, dynamic> command,
  ) async {
    _source ??= await assets.loadString(AppAssets.classroom);
    final value = await controller.evaluateJavascript(
      source: _source!.replaceFirst(
        '__CLASSROOM_COMMAND__',
        jsonEncode(command),
      ),
    );
    if (value is! String ||
        value.length > ClassroomLimits.bridgeResponseLength) {
      throw const FormatException('学校页面读取结果不支持');
    }
    return Map<String, dynamic>.from(jsonDecode(value) as Map);
  }

  Future<Map<String, dynamic>> entry(InAppWebViewController controller) async {
    _entry ??= await assets.loadString(AppAssets.classroomEntry);
    final value = await controller.evaluateJavascript(source: _entry!);
    if (value is! String ||
        value.length > ClassroomLimits.entryResponseLength) {
      throw const FormatException();
    }
    return Map<String, dynamic>.from(jsonDecode(value) as Map);
  }

  Future<Map<String, dynamic>> directory(
    InAppWebViewController controller,
    Map<String, Object> command,
  ) async {
    final adapter = await assets.loadString(AppAssets.recordingApi);
    final bridge = await assets.loadString(AppAssets.recordingBridge);
    final value = await controller
        .callAsyncJavaScript(
          functionBody:
              '$adapter\n${bridge.replaceFirst('__RECORDING_API_COMMAND__', jsonEncode(command))}',
        )
        .timeout(
          command['action'] == 'cancel'
              ? ClassroomLimits.cancelTimeout
              : ClassroomLimits.requestTimeout,
        );
    if (value?.error != null ||
        value?.value is! String ||
        (value!.value as String).length >
            ClassroomLimits.bridgeResponseLength) {
      TestDiagnostics.shared.record(TestEvent.bridgeFailed);
      throw const ClassroomApiFailure('error');
    }
    return Map<String, dynamic>.from(jsonDecode(value.value as String) as Map);
  }
}
