package com.SFRaidTeam.sflist

import android.content.pm.PackageManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import rikka.shizuku.Shizuku
import java.lang.reflect.Method

/**
 * Выполняет команды sh от имени shell через Shizuku.
 * Канал: "sflist/shizuku"
 */
class ShizukuChannel : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private val requestCode = 4242

    // Shizuku.newProcess приватный, поэтому вызываем через reflection
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
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    private fun shell(cmd: String, stdin: String? = null): Pair<Int, String> {
        val p = newProcess.invoke(null, arrayOf("sh", "-c", cmd), null, null) as Process
        if (stdin != null) {
            p.outputStream.use { it.write(stdin.toByteArray(Charsets.UTF_8)) }
        } else {
            p.outputStream.close()
        }
        val out = p.inputStream.bufferedReader(Charsets.UTF_8).readText()
        val err = p.errorStream.bufferedReader(Charsets.UTF_8).readText()
        val code = p.waitFor()
        return code to (if (out.isNotEmpty()) out else err)
    }

    private fun q(s: String) = "'" + s.replace("'", "'\\''") + "'"

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "status" -> {
                    val running = Shizuku.pingBinder()
                    val granted = running &&
                        Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
                    result.success(mapOf("running" to running, "granted" to granted))
                }

                "request" -> {
                    Shizuku.requestPermission(requestCode)
                    result.success(null)
                }

                "read" -> {
                    val path = call.argument<String>("path")!!
                    val (code, out) = shell("cat ${q(path)}")
                    if (code == 0) result.success(out)
                    else result.error("READ", out.ifBlank { "cat завершился с кодом $code" }, null)
                }

                "write" -> {
                    val path = call.argument<String>("path")!!
                    val content = call.argument<String>("content")!!
                    val backup = call.argument<Boolean>("backup") ?: true
                    val prefix = if (backup) "cp -f ${q(path)} ${q("$path.bak")} 2>/dev/null; " else ""
                    val (code, out) = shell(prefix + "cat > ${q(path)}", content)
                    if (code == 0) result.success(true)
                    else result.error("WRITE", out.ifBlank { "код $code" }, null)
                }

                "list" -> {
                    val dir = call.argument<String>("dir")!!
                    val (code, out) = shell("ls -1 ${q(dir)}")
                    val names = if (code == 0) out.lines().filter { it.isNotBlank() } else emptyList()
                    result.success(names)
                }

                else -> result.notImplemented()
            }
        } catch (e: Throwable) {
            result.error("SHIZUKU", e.message ?: e.javaClass.simpleName, null)
        }
    }
}