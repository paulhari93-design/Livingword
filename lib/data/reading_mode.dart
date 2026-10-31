import 'package:flutter/foundation.dart';

import 'prefs.dart';

/// ⋮ → Advanced settings → Page mode.
@immutable
class PageModeSettings {
  const PageModeSettings({this.on = true, this.sideways = true, this.animate = true});

  /// Messages are shown as pages (like Kindle) instead of scrolling.
  final bool on;

  /// Swipe left / right turns the page (off: swipe up / down turns the page).
  final bool sideways;

  /// The page slides while turning (off: the next page just appears, like Kindle).
  final bool animate;

  PageModeSettings copyWith({bool? on, bool? sideways, bool? animate}) => PageModeSettings(
        on: on ?? this.on,
        sideways: sideways ?? this.sideways,
        animate: animate ?? this.animate,
      );

  @override
  bool operator ==(Object other) =>
      other is PageModeSettings && other.on == on && other.sideways == sideways && other.animate == animate;

  @override
  int get hashCode => Object.hash(on, sideways, animate);
}

class PageModeController extends ValueNotifier<PageModeSettings> {
  PageModeController() : super(const PageModeSettings()) {
    _load();
  }

  Future<void> _load() async {
    try {
      value = PageModeSettings(
        on: await Prefs.instance.getBool('page_mode') ?? true, // pages are the default
        sideways: true, // (pages always turn left / right)
        animate: await Prefs.instance.getBool('page_mode_animate') ?? true, // the page curl is on by default
      );
    } catch (_) {}
  }

  Future<void> set(PageModeSettings s) async {
    value = s;
    try {
      await Prefs.instance.set('page_mode', s.on);
      await Prefs.instance.set('page_mode_sideways', s.sideways);
      await Prefs.instance.set('page_mode_animate', s.animate);
    } catch (_) {}
  }
}

final pageMode = PageModeController();

/// ⋮ → Page turning on / off. Turning it on also turns the page animation on;
/// it can be switched off in அ / T → Layout.
void setPageTurning(bool on) =>
    pageMode.set(on ? pageMode.value.copyWith(on: true, animate: true) : pageMode.value.copyWith(on: false));
