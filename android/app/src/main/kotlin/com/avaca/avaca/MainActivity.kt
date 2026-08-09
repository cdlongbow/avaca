package com.avaca.avaca

import com.github.dart_lang.jni.JniPlugin
import com.github.dart_lang.jni_flutter.JniFlutterPlugin
import com.mr.flutter.plugin.filepicker.FilePickerPlugin
import com.tekartik.sqflite.SqflitePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.flutter_plugin_android_lifecycle.FlutterAndroidLifecyclePlugin
import io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val plugins = flutterEngine.plugins

        if (!plugins.has(JniPlugin::class.java)) {
            plugins.add(JniPlugin())
        }
        if (!plugins.has(JniFlutterPlugin::class.java)) {
            plugins.add(JniFlutterPlugin())
        }
        if (!plugins.has(SharedPreferencesPlugin::class.java)) {
            plugins.add(SharedPreferencesPlugin())
        }
        if (!plugins.has(SqflitePlugin::class.java)) {
            plugins.add(SqflitePlugin())
        }
        if (!plugins.has(FilePickerPlugin::class.java)) {
            plugins.add(FilePickerPlugin())
        }
        if (!plugins.has(FlutterAndroidLifecyclePlugin::class.java)) {
            plugins.add(FlutterAndroidLifecyclePlugin())
        }
    }
}
