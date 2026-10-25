import 'package:flutter/material.dart';

import '../data/library.dart';
import '../models/message.dart';

/// Swipe left / right to change message:
/// finger moves to the right = next message, to the left = previous message.
class MessageSwipe extends StatelessWidget {
  const MessageSwipe({super.key, required this.onNext, required this.onPrevious, required this.child});

  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v > 400) onNext();
        if (v < -400) onPrevious();
      },
      child: child,
    );
  }
}

/// The message before (step -1) or after (step +1) [current] in the list, in [lang].
Future<Message?> neighbourMessage(String code, String lang, int step) async {
  final list = await Library.instance.catalog(lang: lang);
  final i = list.indexWhere((m) => m.code.toUpperCase() == code.toUpperCase());
  final j = i + step;
  if (i < 0 || j < 0 || j >= list.length) return null;
  return Library.instance.message(list[j]);
}

/// Slides the new page in from the side it comes from.
Route<T> slideRoute<T>(Widget page, {required bool forward}) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween(begin: Offset(forward ? -1 : 1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
        child: child,
      ),
    );

void showEndOfList(BuildContext context, bool forward) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(forward
        ? 'இதுவே கடைசி செய்தி / This is the last message'
        : 'இதுவே முதல் செய்தி / This is the first message'),
    duration: const Duration(seconds: 1),
  ));
}
