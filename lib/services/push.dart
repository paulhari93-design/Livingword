import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../data/profile.dart';

/// Phone notifications for new messages (Firebase Cloud Messaging).
///
/// The upload tool sends one notification to the topic "new_messages" whenever a
/// new message is published. Corrections are uploaded silently (no notification).
class Push {
  Push._();

  static const topic = 'new_messages'; // English + Tamil readers (Tamil and English news)
  static const topicEnglish = 'new_messages_en'; // English-only readers (English news only)

  /// Increases whenever a notification arrives while the app is open, or the user
  /// taps one. The main menu listens to this and checks for new messages.
  static final ValueNotifier<int> pings = ValueNotifier<int>(0);

  static Future<void> init() async {
    if (Firebase.apps.isEmpty) return;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission(); // Android 13+ asks "Allow notifications?"
      await updateTopics();
      FirebaseMessaging.onMessage.listen((_) => pings.value++);
      FirebaseMessaging.onMessageOpenedApp.listen((_) => pings.value++);
    } catch (e) {
      debugPrint('Push init failed: $e');
    }
  }

  /// Subscribes to the right notifications for the chosen profile.
  static Future<void> updateTopics() async {
    if (Firebase.apps.isEmpty) return;
    try {
      final fm = FirebaseMessaging.instance;
      if (appProfile.englishOnly) {
        await fm.subscribeToTopic(topicEnglish);
        await fm.unsubscribeFromTopic(topic);
      } else {
        await fm.subscribeToTopic(topic);
        await fm.unsubscribeFromTopic(topicEnglish);
      }
    } catch (e) {
      debugPrint('Push topics failed: $e');
    }
  }
}
