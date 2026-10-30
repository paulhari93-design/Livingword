import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// "Share as picture": the chosen words on a card, with where they are from,
/// shared to WhatsApp, Instagram, etc.
class ShareQuote {
  static const double _w = 1080; // pixels: square-ish card that looks good in chats
  static const double _pad = 90;

  static Future<void> share(
    BuildContext context, {
    required String quote,
    required String source, // "65-1204 The Rapture ¶12" / "John 3:16"
    required TextStyle style, // the reading font (Tamil / English) at any size
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final png = await _draw(quote.trim(), source, style);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/livingword_quote.png');
      await file.writeAsBytes(png, flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: '“${quote.trim()}”\n— $source',
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not share: $e')));
    }
  }

  static Future<List<int>> _draw(String quote, String source, TextStyle style) async {
    const bg = Color(0xFFFAF6EF); // warm cream
    const ink = Color(0xFF2B1D16);
    const accent = Color(0xFF7A2E2A); // the app's deep red
    final maxWidth = _w - 2 * _pad;

    // Big text for short quotes, smaller for long ones.
    final size = quote.length < 120 ? 54.0 : quote.length < 260 ? 44.0 : quote.length < 500 ? 36.0 : 30.0;
    final q = TextPainter(
      text: TextSpan(
        text: '“$quote”',
        style: style.copyWith(fontSize: size, height: 1.5, color: ink, backgroundColor: Colors.transparent),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 26,
      ellipsis: '…”',
    )..layout(maxWidth: maxWidth);
    final s = TextPainter(
      text: TextSpan(
        text: '— $source',
        style: style.copyWith(fontSize: 34, height: 1.4, color: accent, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 3,
    )..layout(maxWidth: maxWidth);
    const brand = TextSpan(
      text: 'LivingWord',
      style: TextStyle(fontSize: 26, color: Color(0xFF8A7B70), letterSpacing: 2),
    );
    final b = TextPainter(text: brand, textDirection: TextDirection.ltr)..layout();

    final double h = (_pad + 20 + q.height + 50 + s.height + 70 + b.height + _pad).clamp(_w * 0.6, 4000.0).toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Rect.fromLTWH(0, 0, _w, h), Paint()..color = bg);
    canvas.drawRect(Rect.fromLTWH(0, 0, 18, h), Paint()..color = accent);
    var y = _pad + 20;
    q.paint(canvas, Offset(_pad, y));
    y += q.height + 50;
    s.paint(canvas, Offset(_pad, y));
    b.paint(canvas, Offset(_w - _pad - b.width, h - _pad / 1.4 - b.height));

    final picture = recorder.endRecording();
    final image = await picture.toImage(_w.round(), h.round());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return data!.buffer.asUint8List();
  }
}
