import 'package:flutter/material.dart';

import '../logic/sandy_logic.dart';
import '../l10n/app_strings.dart';
import '../services/deepseek_service.dart';

/// ALK assistant chat — uses the optional DeepSeek AI when the user has
/// configured an API key, otherwise falls back to local rule-based replies.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _thinking = false;
  final _messages = <({bool fromUser, String text})>[
    (fromUser: false, text: 'مرحبًا! أنا ALK، رفيقك الصحي. كيف أستطيع مساعدتك؟'.tr),
  ];

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _thinking) return;
    setState(() {
      _messages.add((fromUser: true, text: text));
      _thinking = true;
      _controller.clear();
    });
    _scrollToBottom();

    final result = await DeepSeekService.instance.chat(message: text);
    if (!mounted) return;
    final reply = result.hasText
        ? result.text!
        : _fallbackReply(text, result);

    setState(() {
      _messages.add((fromUser: false, text: reply));
      _thinking = false;
    });
    _scrollToBottom();
  }

  /// When DeepSeek is unavailable, answer locally so the app keeps working.
  String _fallbackReply(String text, DeepSeekResult result) {
    final local = sandyReply(text);
    if (result.isOffline) {
      return '$local\n\n(الذكاء الآلي غير متاح: ${result.offlineMessage}. '.tr;
    }
    if (result.isError) {
      return '$local\n\n(تنبيه من DeepSeek: ${result.errorMessage})'.tr;
    }
    return local;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiEnabled = DeepSeekService.instance.hasKey;
    return Scaffold(
      appBar: AppBar(title: Text('محادثة ALK'.tr)),
      body: Column(
        children: [
          if (!aiEnabled)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Icon(Icons.smart_toy_outlined,
                      size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'الذكاء الآلي غير مفعّل. ردود محلية فقط — فعّله من الإعدادات.'.tr,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final m = _messages[index];
                return Align(
                  alignment: m.fromUser
                      ? AlignmentDirectional.centerEnd
                      : AlignmentDirectional.centerStart,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: BoxDecoration(
                      color: m.fromUser
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: m.fromUser
                          ? null
                          : Border.all(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Text(
                      m.text,
                      style: TextStyle(
                        color: m.fromUser
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'اكتب رسالتك...'.tr,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _thinking
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton.filled(
                          onPressed: _send,
                          icon: const Icon(Icons.send),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
