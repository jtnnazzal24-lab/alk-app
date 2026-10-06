import 'package:local_auth/local_auth.dart';

/// App lock via device biometrics/passcode — port of the RN `expo-local-authentication`
/// flow used behind `patient.lockEnabled`.
class SecurityService {
  SecurityService._();

  static final SecurityService instance = SecurityService._();

  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isBiometricsAvailable() async {
    try {
      // canCheckBiometrics=true يعني وجود عتاد + بصمة/وجه مسجّلة فعلاً.
      // isDeviceSupported وحدها تعني دعم الجهاز فقط (قد لا توجد بصمة مسجّلة)،
      // فلا تكفي وحدها — وإلا دخلنا مسار البصمة على جهاز بلا بصمة فيفشل
      // الزر بصمت (يرجع authenticate=false فوراً بلا نافذة وبلا PIN).
      final enrolled = await _auth.canCheckBiometrics;
      if (enrolled) return true;
      try {
        final available = await _auth.getAvailableBiometrics();
        if (available.isNotEmpty) return true;
      } catch (_) {
        // تجاهل واعتمد على canCheckBiometrics أدناه.
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Prompts the user to unlock; resolves true on success.
  Future<bool> authenticate({required String localizedReason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
