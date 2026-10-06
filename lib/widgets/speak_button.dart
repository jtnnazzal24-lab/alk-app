import 'package:flutter/material.dart';

import '../services/voice_service.dart';
import '../l10n/app_strings.dart';

/// زر نطق عام لكبار السن: يُستخدم في كل شاشات البرنامج.
/// مثال: SpeakButton(text: 'حان وقت دوائك ...')
class SpeakButton extends StatefulWidget {
  final String text;
  final String languageTag;
  final bool slow;
  final double iconSize;

  const SpeakButton({
    super.key,
    required this.text,
    required this.languageTag,
    this.slow = true,
    this.iconSize = 22,
  });

  @override
  State<SpeakButton> createState() => _SpeakButtonState();
}

class _SpeakButtonState extends State<SpeakButton> {
  bool _speaking = false;

  Future<void> _toggle() async {
    final voice = VoiceService.instance;
    if (_speaking) {
      await voice.stop();
      if (mounted) setState(() => _speaking = false);
      return;
    }
    if (mounted) setState(() => _speaking = true);
    await voice.speak(widget.text,
        languageTag: widget.languageTag, slow: widget.slow);
    if (mounted) setState(() => _speaking = false);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _speaking ? 'إيقاف الصوت'.tr : 'استمع'.tr,
      icon: Icon(_speaking ? Icons.stop_circle : Icons.volume_up,
          size: widget.iconSize),
      onPressed: widget.text.isEmpty ? null : _toggle,
    );
  }
}

/// بطاقة "اقرأ لي هذه الصفحة" — تُوضع أعلى أي شاشة لكبار السن.
class ReadPageAloud extends StatelessWidget {
  final String text;
  final String languageTag;

  const ReadPageAloud(
      {super.key, required this.text, required this.languageTag});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.hearing),
        title: Text('اقرأ لي بصوت بطيء'.tr),
        subtitle: Text('اضغط زر السماعة لسماع الشرح'.tr),
        trailing: SpeakButton(text: text, languageTag: languageTag),
      ),
    );
  }
}
