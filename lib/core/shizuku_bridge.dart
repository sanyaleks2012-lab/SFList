import 'package:flutter/services.dart';

class ShizukuStatus {
  const ShizukuStatus(this.running, this.granted);
  final bool running;
  final bool granted;
}

class ShizukuBridge {
  static const _channel = MethodChannel('sflist/shizuku');

  static String gameDataDir(String pkg) =>
      '/storage/emulated/0/Android/data/$pkg/files/mod/gamedata';

  static Future<ShizukuStatus> status() async {
    final m = await _channel.invokeMapMethod<String, dynamic>('status') ?? {};
    return ShizukuStatus(m['running'] == true, m['granted'] == true);
  }

  static Future<void> request() => _channel.invokeMethod('request');

  static Future<String> read(String path) async =>
      await _channel.invokeMethod<String>('read', {'path': path}) ?? '';

  static Future<void> write(String path, String content, {bool backup = true}) =>
      _channel.invokeMethod('write', {
        'path': path,
        'content': content,
        'backup': backup,
      });

  static Future<List<String>> list(String dir) async =>
      await _channel.invokeListMethod<String>('list', {'dir': dir}) ?? [];
}