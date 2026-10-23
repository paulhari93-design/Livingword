import 'package:flutter/material.dart';

import '../data/cloud.dart';
import '../data/library.dart';
import '../data/local_files.dart';
import 'main_menu_screen.dart';

/// Asks the user to download the Messages and/or the Bible to the phone.
///
/// [firstRun]: shown once after the welcome screen; continues to the main menu.
/// Otherwise it is opened from the main menu and returns true when done.
class DownloadScreen extends StatefulWidget {
  final bool offerMessages;
  final bool offerBible;
  final bool firstRun;

  const DownloadScreen({
    super.key,
    this.offerMessages = true,
    this.offerBible = true,
    this.firstRun = false,
  });

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  late bool _messages = widget.offerMessages;
  late bool _bible = widget.offerBible;
  bool _busy = false;
  String _status = '';
  double? _progress;
  String? _error;

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_messages) {
        setState(() => _status = 'செய்திகள் பதிவிறக்கம்… / Downloading messages…');
        await Cloud.instance.syncMessages(
          onProgress: (d, t) => setState(() => _progress = t == 0 ? null : d / t),
        );
        await LocalFiles.instance.setMessagesDownloaded(true);
        Library.instance.reload();
      }
      if (_bible) {
        setState(() {
          _status = 'வேதாகமம் பதிவிறக்கம்… / Downloading Bible…';
          _progress = null;
        });
        await Cloud.instance.downloadBible(
          onProgress: (d, t) => setState(() => _progress = d / t),
        );
      }
      await LocalFiles.instance.markSetupDone();
      if (!mounted) return;
      _finish(true);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'பதிவிறக்கம் தோல்வி. இணைய இணைப்பைச் சரிபார்த்து மீண்டும் முயலவும்.\n'
            'Download failed. Check your internet connection and try again.';
      });
    }
  }

  Future<void> _later() async {
    await LocalFiles.instance.markSetupDone();
    if (mounted) _finish(false);
  }

  void _finish(bool downloaded) {
    if (widget.firstRun) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainMenuScreen()),
      );
    } else {
      Navigator.of(context).pop(downloaded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.firstRun,
        title: const Text('பதிவிறக்கம் / Download'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'வாசிக்க, கீழே உள்ளவற்றை உங்கள் கைபேசியில் பதிவிறக்கவும். '
              'பின்பு இணையம் இல்லாமலும் வாசிக்கலாம்.\n\n'
              'Download to your phone to read. After that, no internet is needed.',
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 20),
            if (widget.offerMessages)
              CheckboxListTile(
                value: _messages,
                onChanged: _busy ? null : (v) => setState(() => _messages = v ?? false),
                title: const Text('செய்திகள் / Messages'),
                subtitle: const Text('புதிய செய்திகள் தானாகவே வரும் / New messages arrive automatically'),
              ),
            if (widget.offerBible)
              CheckboxListTile(
                value: _bible,
                onChanged: _busy ? null : (v) => setState(() => _bible = v ?? false),
                title: const Text('பரிசுத்த வேதாகமம் / Holy Bible'),
                subtitle: const Text('தமிழ் + English (KJV) · ~17 MB'),
              ),
            const SizedBox(height: 24),
            if (_busy) ...[
              Text(_status, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 24),
            ],
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: theme.colorScheme.error, height: 1.5)),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(
              onPressed: _busy || (!_messages && !_bible) ? null : _download,
              icon: const Icon(Icons.download),
              label: const Text('பதிவிறக்கு / Download'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _later,
              child: const Text('பின்னர் / Later'),
            ),
          ],
        ),
      ),
    );
  }
}
