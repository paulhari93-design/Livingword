import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/cloud.dart';
import '../data/prefs.dart';
import '../data/profile.dart';
import '../l10n.dart';

/// ⋮ → கருத்து தெரிவி / Feedback.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

enum _Step { choose, write, sent }

class _FeedbackScreenState extends State<FeedbackScreen> {
  static const maxLetters = 200;

  _Step _step = _Step.choose;
  bool _withContact = false;
  bool _sending = false;
  final _text = TextEditingController();
  final _name = TextEditingController();
  final _contact = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    _name.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    if (_withContact && (_name.text.trim().isEmpty || _contact.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Tr('பெயரையும் தொடர்பையும் உள்ளிடவும் / Please enter your name and contact'),
      ));
      return;
    }
    setState(() => _sending = true);
    try {
      final info = await PackageInfo.fromPlatform();
      final last = await Prefs.instance.getString('last_message');
      await Cloud.instance.sendFeedback(
        text: text,
        name: _withContact ? _name.text.trim() : null,
        contact: _withContact ? _contact.text.trim() : null,
        about: {
          'app': '${info.version} (${info.buildNumber})',
          'android': Platform.operatingSystemVersion,
          'profile': appProfile.englishOnly ? 'English only' : 'English + Tamil',
          'reading': last ?? '',
        },
      );
      if (mounted) setState(() => _step = _Step.sent);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Tr('அனுப்ப முடியவில்லை. இணைய இணைப்பைச் சரிபார்க்கவும். / '
            'Could not send. Please check your internet connection.'),
      ));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _message(IconData icon, String text, {Widget? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Tr(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.5)),
            if (action != null) ...[const SizedBox(height: 20), action],
          ],
        ),
      ),
    );
  }

  Widget _choose() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Tr(
          'பதில் பெற உங்கள் பெயரையும் தொடர்பையும் (தொலைபேசி அல்லது மின்னஞ்சல்) தர விரும்புகிறீர்களா, '
          'அல்லது பெயர் இல்லாமல் அனுப்ப விரும்புகிறீர்களா?\n\n'
          'Would you like to give your name and contact (phone or email) to receive a reply, '
          'or stay anonymous?',
          style: TextStyle(fontSize: 16, height: 1.5),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          icon: const Icon(Icons.person_outline),
          label: const Tr('பெயர், தொடர்பு தருகிறேன் / Give my name and contact'),
          onPressed: () => setState(() {
            _withContact = true;
            _step = _Step.write;
          }),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.visibility_off_outlined),
          label: const Tr('பெயர் இல்லாமல் அனுப்பு / Stay anonymous'),
          onPressed: () => setState(() {
            _withContact = false;
            _step = _Step.write;
          }),
        ),
      ],
    );
  }

  Widget _write() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_withContact) ...[
          TextField(
            controller: _name,
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: tr('பெயர் / Name'),
              border: const OutlineInputBorder(),
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contact,
            maxLength: 80,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: tr('தொலைபேசி அல்லது மின்னஞ்சல் / Phone or email'),
              border: const OutlineInputBorder(),
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _text,
          maxLength: maxLetters,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          minLines: 4,
          maxLines: 8,
          autofocus: !_withContact,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: tr('உங்கள் கருத்து / Your feedback'),
            hintText: tr('எ.கா. 63-0318 பத்தி 12-ல் தவறான வார்த்தை / '
                'e.g. a wrong word in 63-0318, paragraph 12'),
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 4),
        Tr(
          'நீங்கள் கடைசியாக வாசித்த இடம் தானாகச் சேர்க்கப்படும். / '
          'The place you were reading last is added automatically.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          icon: _sending
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send),
          label: const Tr('அனுப்பு / Send'),
          onPressed: _sending || _text.text.trim().isEmpty ? null : _send,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (_step) {
      _Step.choose => _choose(),
      _Step.write => _write(),
      _Step.sent => _message(
          Icons.check_circle_outline,
          'நன்றி! உங்கள் கருத்து அனுப்பப்பட்டது. / Thank you! Your feedback has been sent.',
          action: FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Tr('சரி / OK'),
          ),
        ),
    };
    return Scaffold(
      appBar: AppBar(title: const Tr('கருத்து தெரிவி / Feedback')),
      body: SafeArea(child: body),
    );
  }
}
