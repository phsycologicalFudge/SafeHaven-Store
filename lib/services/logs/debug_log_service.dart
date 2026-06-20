import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DebugLog {
  DebugLog._();

  static const MethodChannel _channel = MethodChannel('safehaven/debug');
  static bool _enabled = false;

  static bool get enabled => _enabled;

  static Future<void> init() async {
    try {
      _enabled = await _channel.invokeMethod<bool>('getDebugLogging') ?? false;
    } catch (_) {
      _enabled = false;
    }
  }

  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      await _channel.invokeMethod('setDebugLogging', {'enabled': value});
    } catch (_) {}
  }

  static Future<bool> hasLog() async {
    try {
      return await _channel.invokeMethod<bool>('hasLog') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clearLog() async {
    try {
      await _channel.invokeMethod('clearLog');
    } catch (_) {}
  }

  static Future<void> shareLog() async {
    try {
      await _channel.invokeMethod('shareLog');
    } catch (_) {}
  }

  static void installCrashHandlers() {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      crash('Flutter', '${details.exceptionAsString()}\n${details.stack}');
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      crash('Dart', '$error\n$stack');
      return true;
    };
  }

  static void crash(String tag, String msg) {
    try {
      _channel.invokeMethod('writeCrashLog', {'tag': tag, 'msg': msg});
    } catch (_) {}
  }

  static void e(String tag, String msg, [Object? error, StackTrace? stack]) {
    if (!_enabled) return;
    _write(tag, 'E', _format(msg, error, stack));
  }

  static void w(String tag, String msg, [Object? error, StackTrace? stack]) {
    if (!_enabled) return;
    _write(tag, 'W', _format(msg, error, stack));
  }

  static void d(String tag, String msg) {
    if (!_enabled) return;
    _write(tag, 'D', msg);
  }

  static String _format(String msg, Object? error, StackTrace? stack) {
    final buf = StringBuffer(msg);
    if (error != null) buf.write('\n$error');
    if (stack != null) buf.write('\n$stack');
    return buf.toString();
  }

  static void _write(String tag, String level, String msg) {
    try {
      _channel.invokeMethod('writeDebugLog', {
        'tag': tag,
        'level': level,
        'msg': msg,
      });
    } catch (_) {}
  }
}