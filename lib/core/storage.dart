import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shizuku_bridge.dart';

abstract final class Storage {
  static Future<bool> ensureAllFiles() async {
    final p = Permission.manageExternalStorage;
    if (await p.isGranted) return true;
    return (await p.request()).isGranted;
  }

  static Future<String> read(String path, {required bool viaShizuku}) =>
      viaShizuku ? ShizukuBridge.read(path) : File(path).readAsString();

  static Future<void> write(String path, String text, {required bool viaShizuku}) async {
    if (viaShizuku) {
      await ShizukuBridge.write(path, text);
      return;
    }
    final f = File(path);
    if (await f.exists()) await f.copy('$path.bak');
    await f.writeAsString(text, flush: true);
  }
}

abstract final class Prefs {
  static const _pkgKey = 'lastPackage';

  static Future<String?> lastPackage() async =>
      (await SharedPreferences.getInstance()).getString(_pkgKey);

  static Future<void> setLastPackage(String pkg) async =>
      (await SharedPreferences.getInstance()).setString(_pkgKey, pkg);
}