import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_strings.dart';

/// Opens WhatsApp to let the user send feedback directly to the developer.
class FeedbackService {
  const FeedbackService();

  /// Developer WhatsApp number in international format without +.
  static const developerWhatsapp = '972592055302';

  /// Pre-filled feedback message template (بلغلة الواجهة الحالية).
  static String get _defaultMessage =>
      'مرحبًا، أودّ أن أشارك ملاحظتي حول تطبيق ALK:'.tr;

  Future<bool> openWhatsApp({String? message}) async {
    final text = message ?? _defaultMessage;
    final encoded = Uri.encodeComponent(text);
    final uri = Uri.parse('https://wa.me/$developerWhatsapp?text=$encoded');
    // FIX: do not gate on `canLaunchUrl` — on Android 11+ it returns false
    // for https links without <queries> visibility, which made the button
    // silently do nothing. Launch directly and fall back to the app scheme.
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return true;
    } catch (_) {
      // Fall through to the direct app-scheme attempt.
    }
    try {
      final appUri = Uri.parse(
        'whatsapp://send?phone=$developerWhatsapp&text=$encoded',
      );
      return await launchUrl(appUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}