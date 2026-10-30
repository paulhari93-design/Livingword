import 'package:flutter/services.dart';

import '../data/prefs.dart';
import 'package:flutter/foundation.dart';

/// Volume up / down turn pages in a message (one-hand reading). Android only.
///
/// The reader that is on screen registers itself; the newest registered reader gets
/// the keys. With no reader open, the keys change the volume as usual.
class VolumeKeys {
  VolumeKeys._();

  static const _channel = MethodChannel('livingword/volume_keys');
  static final List<bool Function(bool down)> _handlers = [];
  static bool _listening = false;

  /// The setting (Advanced settings), on by default.
  static final enabled = ValueNotifier<bool>(true);

  static Future<void> loadSetting() async {
    try {
      enabled.value = await Prefs.instance.getBool('volume_keys') ?? true;
    } catch (_) {}
  }

  static Future<void> setEnabled(bool on) async {
    enabled.value = on;
    await Prefs.instance.set('volume_keys', on);
    await _update();
  }

  /// [handler] gets true for volume down (next page), false for volume up (previous);
  /// it returns false if it did not use the key (then the volume changes).
  static void attach(bool Function(bool down) handler) {
    _handlers.add(handler);
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'key' || _handlers.isEmpty || !enabled.value) return false;
        return _handlers.last(call.arguments == 'down');
      });
    }
    _update();
  }

  static void detach(bool Function(bool down) handler) {
    _handlers.remove(handler);
    _update();
  }

  static Future<void> _update() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod('enable', enabled.value && _handlers.isNotEmpty);
    } catch (_) {}
  }
}
