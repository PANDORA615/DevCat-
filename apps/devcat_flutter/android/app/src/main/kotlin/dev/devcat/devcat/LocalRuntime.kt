package dev.devcat.devcat

import android.content.Context
import android.os.StatFs
import android.system.Os
import android.system.OsConstants
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipInputStream

/** Installs only the image shipped and signed inside this APK; never downloads. */
class LocalRuntime(private val context: Context) {
    @Synchronized
    fun prepare(): Map<String, String> {
        val assets = context.assets.list("runtime")?.toSet() ?: emptySet()
        val machine = System.getProperty("os.arch") ?: ""
        val abi = when {
            machine.contains("aarch64") -> "arm64-v8a"
            machine.contains("x86_64") || machine.contains("amd64") -> "x86_64"
            machine.startsWith("arm") -> "armeabi-v7a"
            else -> error("Неподдерживаемая архитектура: $machine")
        }
        check(assets.contains("$abi.zip")) { "В APK отсутствует среда исполнения $abi." }
        val metadata = JSONObject(context.assets.open("runtime/$abi.json").bufferedReader().use { it.readText() })
        val digest = metadata.getString("sha256")
        val base = File(context.filesDir, "local-runtime")
        base.mkdirs()
        val root = File(base, "$abi-${digest.take(16)}")
        val complete = File(root, ".devcat-ready")
        if (!complete.isFile || complete.readText() != digest) {
            val needed = metadata.getLong("unpackedBytes") + 150L * 1024 * 1024
            check(StatFs(base.path).availableBytes >= needed) {
                "Для встроенных компиляторов нужно ещё ${needed / 1024 / 1024} МиБ свободного места."
            }
            val hasher = MessageDigest.getInstance("SHA-256")
            context.assets.open("runtime/$abi.zip").use { stream ->
                val block = ByteArray(1024 * 1024)
                while (true) {
                    val count = stream.read(block)
                    if (count < 0) break
                    hasher.update(block, 0, count)
                }
            }
            val actual = hasher.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
            check(actual == digest) { "Встроенный пакет повреждён. Переустанови APK из релиза." }
            val staging = File(base, ".$abi-installing")
            removeWithoutFollowingLinks(staging)
            staging.mkdirs()
            try {
                var bytes = 0L
                var count = 0
                var links = JSONObject()
                ZipInputStream(context.assets.open("runtime/$abi.zip").buffered()).use { zip ->
                    val block = ByteArray(256 * 1024)
                    while (true) {
                        val entry = zip.nextEntry ?: break
                        check(++count <= 150000) { "Слишком много файлов среды исполнения." }
                        val destination = inside(staging, entry.name)
                        if (entry.name == "_devcat_links.json") {
                            val text = StringBuilder()
                            val buffer = ByteArray(8192)
                            while (true) {
                                val n = zip.read(buffer)
                                if (n < 0) break
                                text.append(String(buffer, 0, n, Charsets.UTF_8))
                                check(text.length < 2 * 1024 * 1024)
                            }
                            links = JSONObject(text.toString())
                        } else if (entry.isDirectory) {
                            destination.mkdirs()
                        } else {
                            destination.parentFile!!.mkdirs()
                            destination.outputStream().use { out ->
                                while (true) {
                                    val n = zip.read(block)
                                    if (n < 0) break
                                    bytes += n
                                    check(bytes <= metadata.getLong("unpackedBytes") + 8 * 1024 * 1024)
                                    out.write(block, 0, n)
                                }
                            }
                            Os.chmod(destination.path, 0x1ED) // 0755; private app storage.
                        }
                        zip.closeEntry()
                    }
                }
                // Links are materialized last, so no archive write follows a link.
                links.keys().forEach { name ->
                    val destination = inside(staging, name)
                    val target = links.getString(name)
                    check(!target.contains('\u0000'))
                    destination.parentFile!!.mkdirs()
                    Os.symlink(target, destination.path)
                }
                for (name in listOf("dev", "proc", "sys", "tmp", "root", "work", "var/tmp")) {
                    File(staging, name).mkdirs()
                }
                File(staging, ".devcat-ready").writeText(digest)
                removeWithoutFollowingLinks(root)
                check(staging.renameTo(root)) { "Не удалось завершить подготовку компиляторов." }
                base.listFiles()?.filter { it != root }?.forEach { removeWithoutFollowingLinks(it) }
            } catch (error: Throwable) {
                removeWithoutFollowingLinks(staging)
                throw error
            }
        }
        val native = context.applicationInfo.nativeLibraryDir
        check(File(native, "libdevcat_proot.so").isFile && File(native, "libdevcat_loader.so").isFile) {
            "В APK отсутствует локальный загрузчик."
        }
        return mapOf("root" to root.path, "nativeLib" to native, "abi" to abi)
    }

    private fun inside(root: File, name: String): File {
        check(name.isNotEmpty() && !name.startsWith('/') && !name.contains('\\') && !name.contains('\u0000'))
        check(name.split('/').none { it == ".." || it == "." })
        val destination = File(root, name)
        check(destination.canonicalPath.startsWith(root.canonicalPath + File.separator))
        return destination
    }

    private fun removeWithoutFollowingLinks(file: File) {
        val stat = try { Os.lstat(file.path) } catch (_: Exception) { return }
        if (OsConstants.S_ISDIR(stat.st_mode)) {
            file.listFiles()?.forEach { removeWithoutFollowingLinks(it) }
        }
        check(file.delete()) { "Не удалось удалить незавершённую среду исполнения." }
    }
}
