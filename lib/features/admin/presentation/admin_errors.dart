import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/generated/app_localizations.dart';

String adminErrorMessage(AppLocalizations l10n, Object error) {
  if (error is PostgrestException) {
    if (error.code == '23505') return l10n.errorDuplicatePhone;
    if (error.code == '23514') return l10n.phoneInvalid;
    if (error.message.contains('Admins cannot change their own')) {
      return l10n.errorSelfChange;
    }
    if (error.code == '42501') return l10n.notAllowed;
  }
  final text = error.toString().toLowerCase();
  if (text.contains('socket') || text.contains('network')) {
    return l10n.errorNetwork;
  }
  return l10n.errorUnknown;
}

String roleLabel(AppLocalizations l10n, String role) => switch (role) {
  'admin' => l10n.roleAdmin,
  'manager' => l10n.roleManager,
  _ => l10n.roleEmployee,
};
