import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shizuku_bridge.dart';

abstract final class Storage {
  /// Доступ к файлам по пути.
  /// Android 11+: «Доступ ко всем файлам» (MANAGE_EXTERNAL_STORAGE),
  /// Android 10 и ниже: обычное разрешение на storage.
  static Future<bool> ensureAllFiles() async {
    final all = Permission.manageExternalStorage;
    if (await all.isGranted) return true;
    if ((await all.request()).isGranted) return true;

    final legacy = Permission.storage;
    if (await legacy.isGranted) return true;
    return (await legacy.request()).isGranted;
  }

  static String _stripBom(String text) =>
      text.startsWith('﻿') ? text.substring(1) : text;

  static Future<String> read(String path, {required bool viaShizuku}) async {
    final text = viaShizuku
        ? await ShizukuBridge.read(path)
        : await File(path).readAsString();
    return _stripBom(text);
  }

  /// Сохраняет файл. Копия оригинала `<path>.bak` создаётся один раз
  /// (если её ещё нет) и больше не перезаписывается, поэтому исходник не теряется.
  static Future<void> write(String path, String text, {required bool viaShizuku}) async {
    if (viaShizuku) {
      await ShizukuBridge.write(path, text);
      return;
    }
    final file = File(path);
    final bak = File('$path.bak');
    if (await file.exists() && !await bak.exists()) {
      await file.copy(bak.path);
    }

    // Пишем во временный файл и переименовываем: если приложение убьют
    // посреди записи, исходный файл останется целым.
    final tmp = File('$path.tmp');
    try {
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(path);
    } catch (_) {
      // На некоторых файловых системах rename поверх существующего файла не работает.
      await file.writeAsString(text, flush: true);
      if (await tmp.exists()) await tmp.delete();
    }
  }

  /// Какие из [names] лежат в папке [dir] (режим «Файлы»).
  static Future<Set<String>> existing(String dir, Iterable<String> names) async {
    final found = <String>{};
    for (final n in names) {
      if (await File('$dir/$n').exists()) found.add(n);
    }
    return found;
  }
}

abstract final class Prefs {
  static const _pkgKey = 'lastPackage';
  static const _dirKey = 'lastDir';
  static const _shizukuKey = 'lastModeShizuku';

  static Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  static Future<String?> lastPackage() async => (await _p).getString(_pkgKey);
  static Future<void> setLastPackage(String pkg) async =>
      (await _p).setString(_pkgKey, pkg);

  static Future<String?> lastDir() async => (await _p).getString(_dirKey);
  static Future<void> setLastDir(String dir) async => (await _p).setString(_dirKey, dir);

  static Future<bool> lastModeShizuku() async => (await _p).getBool(_shizukuKey) ?? false;
  static Future<void> setLastModeShizuku(bool v) async => (await _p).setBool(_shizukuKey, v);
}
