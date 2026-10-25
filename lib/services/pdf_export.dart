import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// One block of the PDF: a title, an info line, a paragraph or a verse.
class PdfBlock {
  final InlineSpan span;
  final TextAlign align;
  final double spaceAfter; // points
  final bool lineBelow; // thin line under the block (after the heading)

  const PdfBlock(this.span, {this.align = TextAlign.left, this.spaceAfter = 10, this.lineBelow = false});
}

/// Makes a PDF that looks exactly like the app (Tamil letters, highlights, bold,
/// underline), by drawing each page with the app's own text engine, then lets the
/// user choose where to save it.
class PdfExport {
  // A4 in points, margins, and how sharp the pages are.
  static const double _w = 595, _h = 842, _margin = 48, _scale = 2.0;

  static Future<bool> save({required String fileName, required List<PdfBlock> blocks}) async {
    final pages = await _drawPages(blocks);
    final doc = pw.Document();
    for (final png in pages) {
      final image = pw.MemoryImage(png);
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
      ));
    }
    final bytes = await doc.save();
    final path = await FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(data: bytes, fileName: fileName, mimeTypesFilter: ['application/pdf']),
    );
    return path != null;
  }

  /// Runs [save] with "please wait" and "saved" messages.
  static Future<void> saveWithMessages(BuildContext context,
      {required String fileName, required List<PdfBlock> blocks}) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('PDF தயாராகிறது… / Making the PDF…'),
      duration: Duration(seconds: 30),
    ));
    try {
      final ok = await save(fileName: fileName, blocks: blocks);
      messenger.hideCurrentSnackBar();
      if (ok) {
        messenger.showSnackBar(const SnackBar(content: Text('PDF சேமிக்கப்பட்டது / PDF saved')));
      }
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('PDF could not be made: $e')));
    }
  }

  /// A safe file name: "53-0216 My Angel Shall Go Before Thee.pdf".
  static String fileName(String name) =>
      '${name.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim()}.pdf';

  /// Lays the blocks out on A4 pages (never cutting a line in half) and returns PNG pages.
  static Future<List<Uint8List>> _drawPages(List<PdfBlock> blocks) async {
    const contentWidth = _w - 2 * _margin;
    const bottomLimit = _h - _margin;

    final pages = <List<_Piece>>[[]];
    var y = _margin;

    for (final b in blocks) {
      final tp = TextPainter(
        text: b.span,
        textAlign: b.align,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: contentWidth);
      final lines = tp.computeLineMetrics();
      if (lines.isEmpty) continue;

      var from = 0; // first line not yet placed
      while (from < lines.length) {
        final top = lines[from].baseline - lines[from].ascent;
        // How many lines fit on this page?
        var to = from;
        while (to < lines.length) {
          final bottom = lines[to].baseline + lines[to].descent;
          if (y + (bottom - top) > bottomLimit) break;
          to++;
        }
        if (to == from) {
          if (y > _margin) {
            // Nothing fits: next page.
            pages.add([]);
            y = _margin;
            continue;
          }
          to = from + 1; // a single line taller than a page (should not happen)
        }
        final bottom = lines[to - 1].baseline + lines[to - 1].descent;
        pages.last.add(_Piece(tp, y, top, bottom));
        y += bottom - top;
        from = to;
        if (from < lines.length) {
          pages.add([]);
          y = _margin;
        }
      }
      if (b.lineBelow) {
        y += 8;
        pages.last.add(_Piece.line(y));
        y += 10;
      }
      y += b.spaceAfter;
    }

    final out = <Uint8List>[];
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].isEmpty) continue;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(_scale);
      canvas.drawRect(const Rect.fromLTWH(0, 0, _w, _h), Paint()..color = Colors.white);
      for (final p in pages[i]) {
        if (p.painter == null) {
          canvas.drawLine(Offset(_margin + 60, p.y), Offset(_w - _margin - 60, p.y),
              Paint()
                ..color = const Color(0xFFBBBBBB)
                ..strokeWidth = 0.8);
          continue;
        }
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(_margin - 4, p.y, contentWidth + 8, p.bottom - p.top));
        p.painter!.paint(canvas, Offset(_margin, p.y - p.top));
        canvas.restore();
      }
      // Page number
      final num = TextPainter(
        text: TextSpan(
            text: 'LivingWord · ${out.length + 1}',
            style: const TextStyle(fontSize: 8, color: Color(0xFF999999))),
        textDirection: TextDirection.ltr,
      )..layout();
      num.paint(canvas, Offset((_w - num.width) / 2, _h - _margin / 2 - num.height));

      final picture = recorder.endRecording();
      final image = await picture.toImage((_w * _scale).round(), (_h * _scale).round());
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      if (data != null) out.add(data.buffer.asUint8List());
    }
    return out;
  }

  /// Text styles for the PDF (black text on white paper).
  static const TextStyle body = TextStyle(fontSize: 12.5, height: 1.6, color: Colors.black);
  static const TextStyle title =
      TextStyle(fontSize: 19, height: 1.4, fontWeight: FontWeight.w700, color: Colors.black);
  static const TextStyle info = TextStyle(fontSize: 11, height: 1.5, color: Color(0xFF444444));

}

class _Piece {
  final TextPainter? painter;
  final double y, top, bottom;
  _Piece(this.painter, this.y, this.top, this.bottom);
  _Piece.line(this.y)
      : painter = null,
        top = 0,
        bottom = 0;
}
