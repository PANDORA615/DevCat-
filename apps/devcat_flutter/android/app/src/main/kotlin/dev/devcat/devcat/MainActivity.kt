package dev.devcat.devcat

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val installer = Executors.newSingleThreadExecutor()
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val runtime = LocalRuntime(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.devcat/local-runtime")
            .setMethodCallHandler { call, result ->
                if (call.method != "prepare") {
                    result.notImplemented()
                } else {
                    installer.execute {
                        try {
                            val prepared = runtime.prepare()
                            runOnUiThread { result.success(prepared) }
                        } catch (error: Throwable) {
                            runOnUiThread { result.error("runtime", error.message, null) }
                        }
                    }
                }
            }
    }
}
