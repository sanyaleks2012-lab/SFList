# ShizukuChannel вызывает приватный Shizuku.newProcess через reflection.
# Без этих правил R8 вырезает метод в release-сборке (в debug всё работает).
-keep class rikka.shizuku.** { *; }
-keep class moe.shizuku.** { *; }
-dontwarn rikka.shizuku.**
-dontwarn moe.shizuku.**
