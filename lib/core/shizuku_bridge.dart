import 'package:flutter/services.dart';

/// Ошибка моста Shizuku с читаемым текстом (вместо `PlatformException(...)`).
class ShizukuException implements Exception {
  const ShizukuException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ShizukuStatus {
  const ShizukuStatus(this.running, this.granted);
  final bool running;
  final bool granted;
}

class ShizukuBridge {
  static const _channel = MethodChannel('sflist/shizuku');

  static final _packageRe = RegExp(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$');

  /// Допустимое имя пакета Android (com.example.game).
  static bool isValidPackage(String pkg) => _packageRe.hasMatch(pkg);

  static String gameDataDir(String pkg) =>
      '/storage/emulated/0/Android/data/$pkg/files/mod/gamedata';

  static Future<T> _call<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PlatformException catch (e) {
      throw ShizukuException(e.message ?? e.code);
    } on MissingPluginException {
      throw const ShizukuException('Мост Shizuku недоступен в этой сборке');
    }
  }

  static Future<ShizukuStatus> status() => _call(() async {
        final m = await _channel.invokeMapMethod<String, dynamic>('status') ?? {};
        return ShizukuStatus(m['running'] == true, m['granted'] == true);
      });

  /// Запрашивает доступ и ждёт ответа пользователя в приложении Shizuku.
  /// `false` — доступ не выдан (отклонён, или Shizuku не запущен).
  static Future<bool> request() =>
      _call(() async => await _channel.invokeMethod<bool>('request') ?? false);

  static Future<String> read(String path) => _call(
        () async => await _channel.invokeMethod<String>('read', {'path': path}) ?? '',
      );

  /// Перед записью один раз создаёт `<path>.bak` (если его ещё нет) при [backup].
  static Future<void> write(String path, String content, {bool backup = true}) =>
      _call(() async {
        await _channel.invokeMethod<bool>('write', {
          'path': path,
          'content': content,
          'backup': backup,
        });
      });

  static Future<List<String>> list(String dir) => _call(
        () async => await _channel.invokeListMethod<String>('list', {'dir': dir}) ?? <String>[],
      );
}
