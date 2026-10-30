import 'package:flutter/foundation.dart';

import 'prefs.dart';

/// Which content the user reads: English only, or English + Tamil.
enum AppProfile { englishOnly, tamilEnglish }

/// The chosen profile (null until the user has chosen, on first install). Remembered.
class ProfileController extends ValueNotifier<AppProfile?> {
  ProfileController() : super(null);
  static const _key = 'profile';

  bool get englishOnly => value == AppProfile.englishOnly;

  Future<void> load() async {
    final saved = await Prefs.instance.getString(_key);
    value = AppProfile.values.where((p) => p.name == saved).firstOrNull;
  }

  Future<void> set(AppProfile p) async {
    value = p;
    await Prefs.instance.set(_key, p.name);
  }
}

final appProfile = ProfileController();
