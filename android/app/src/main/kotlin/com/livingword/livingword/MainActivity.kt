package com.livingword.livingword

import android.content.Context
import android.media.AudioManager
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Volume keys turn pages while a message is open (if the reader allows it).
 * The app tells us when to catch them ("enable"); each press is sent to the app ("key"),
 * and if the app does not use it, the volume changes as usual.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var catchVolumeKeys = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "livingword/volume_keys")
        ch.setMethodCallHandler { call, result ->
            if (call.method == "enable") {
                catchVolumeKeys = call.arguments as? Boolean ?: false
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        channel = ch
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        val up = keyCode == KeyEvent.KEYCODE_VOLUME_UP
        val down = keyCode == KeyEvent.KEYCODE_VOLUME_DOWN
        val ch = channel
        if (catchVolumeKeys && (up || down) && ch != null) {
            ch.invokeMethod("key", if (down) "down" else "up", object : MethodChannel.Result {
                override fun success(handled: Any?) {
                    if (handled != true) changeVolume(up)
                }
                override fun error(code: String, message: String?, details: Any?) = changeVolume(up)
                override fun notImplemented() = changeVolume(up)
            })
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (catchVolumeKeys &&
            (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)) {
            return true
        }
        return super.onKeyUp(keyCode, event)
    }

    private fun changeVolume(up: Boolean) {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audio.adjustSuggestedStreamVolume(
            if (up) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER,
            AudioManager.USE_DEFAULT_STREAM_TYPE,
            AudioManager.FLAG_SHOW_UI
        )
    }
}
