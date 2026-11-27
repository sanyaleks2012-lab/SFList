package com.SFRaidTeam.sflist

import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import rikka.shizuku.Shizuku
import java.lang.reflect.InvocationTargetException
import java.lang.reflect.Method
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** Ошибка выполнения команды в shell Shizuku (текст попадёт в Dart как message). */
private class ShellException(message: String) : Exception(message)

/**
 * Выполняет команды sh от имени shell через Shizuku.
 * Канал: "sflist/shizuku"
 *
 * Методы: status, request, read, write, list.
 * Все блокирующие операции идут в фоновом потоке, ответ возвращается в главном.
 */
class ShizukuChannel : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private val main = Handler(Looper.getMainLooper())
    private val io: ExecutorService = Executors.newSingleThreadExecutor()
    private val requestCode = 4242

    /** Ответ на «request», пока пользователь не нажмёт «Разрешить/Отклонить» в Shizuku. */
    private var pendingRequest: MethodChannel.Result? = null

    private val permissionListener =
        Shizuku.OnRequestPermissionResultListener { code, grantResult ->
            main.post {
                if (code == requestCode) {
                    val r = pendingRequest
                    pendingRequest = null
                    r?.success(grantResult == PackageManager.PERMISSION_GRANTED)
                }
            }
        }

    // Shizuku.newProcess приватный (с API 13.1), поэтому вызываем через reflection.
    // Для release-сборки нужны keep-правила из proguard-rules.pro, иначе R8 удалит метод.
    private val newProcess: Method by lazy {
        Shizuku::class.java
            .getDeclaredMethod(
                "newProcess",
                Array<String>::class.java,
                Array<String>::class.java,
                String::class.java
            )
            .apply { isAccessible = true }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "sflist/shizuku")
        channel.setMethodCallHandler(this)
        Shizuku.addRequestPermissionResultListener(permissionListener)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Shizuku.removeRequestPermissionResultListener(permissionListener)
        channel.setMethodCallHandler(null)
        pendingRequest?.success(false)
        pendingRequest = null
        io.shutdown()
    }

    /** sh -c «cmd»; stderr сливается в stdout, чтобы не было взаимной блокировки пайпов. */
    private fun shell(cmd: String, stdin: String? = null): Pair<Int, String> {
        val process: Process = try {
            newProcess.invoke(null, arrayOf("sh", "-c", "($cmd) 2>&1"), null, null) as Process
        } catch (e: InvocationTargetException) {
            throw e.targetException ?: e
        }
        if (stdin != null) {
            process.outputStream.use { it.write(stdin.toByteArray(Charsets.UTF_8)) }
        } else {
            process.outputStream.close()
        }
        val out = process.inputStream.bufferedReader(Charsets.UTF_8).readText()
        val code = process.waitFor()
        return code to out
    }

    private fun q(s: String) = "'" + s.replace("'", "'\\''") + "'"

    private fun describe(e: Throwable): String = when (e) {
        is ShellException -> e.message ?: "Ошибка shell"
        is NoSuchMethodException ->
            "Shizuku.newProcess недоступен (версия Shizuku API или R8 вырезал метод)"
        is InvocationTargetException -> describe(e.targetException ?: e)
        else -> e.message ?: e.javaClass.simpleName
    }

    /** Выполняет [block] в фоне и возвращает результат Flutter в главном потоке. */
    private fun runIo(result: MethodChannel.Result, block: () -> Any?) {
        io.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (e: Throwable) {
                val message = describe(e)
                main.post { result.error("SHIZUKU", message, null) }
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> runIo(result) {
                val running = Shizuku.pingBinder()
                val granted = running &&
                    Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
                mapOf("running" to running, "granted" to granted)
            }

            "request" -> {
                try {
                    when {
                        !Shizuku.pingBinder() -> result.success(false)
                        Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED ->
                            result.success(true)
                        // Пользователь выбрал «Отклонить и не спрашивать» — диалога не будет.
                        Shizuku.shouldShowRequestPermissionRationale() -> result.success(false)
                        else -> {
                            pendingRequest?.success(false)
                            pendingRequest = result
                            Shizuku.requestPermission(requestCode)
                        }
                    }
                } catch (e: Throwable) {
                    pendingRequest = null
                    result.error("SHIZUKU", describe(e), null)
                }
            }

            "read" -> {
                val path = call.argument<String>("path")!!
                runIo(result) {
                    val (code, out) = shell("cat ${q(path)}")
                    if (code != 0) {
                        throw ShellException(out.ifBlank { "cat завершился с кодом $code" })
                    }
                    out
                }
            }

            "write" -> {
                val path = call.argument<String>("path")!!
                val content = call.argument<String>("content")!!
                val backup = call.argument<Boolean>("backup") ?: true
                runIo(result) {
                    // Копия оригинала создаётся один раз и больше не перезаписывается.
                    val bak = "$path.bak"
                    val prefix =
                        if (backup) "[ -e ${q(bak)} ] || cp ${q(path)} ${q(bak)}; " else ""
                    val (code, out) = shell(prefix + "cat > ${q(path)}", content)
                    if (code != 0) {
                        throw ShellException(out.ifBlank { "запись завершилась с кодом $code" })
                    }
                    true
                }
            }

            "list" -> {
                val dir = call.argument<String>("dir")!!
                runIo(result) {
                    val (code, out) = shell("ls -1 ${q(dir)}")
                    if (code != 0) {
                        throw ShellException(out.ifBlank { "ls завершился с кодом $code" })
                    }
                    out.lines().filter { it.isNotBlank() }
                }
            }

            else -> result.notImplemented()
        }
    }
}
