import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';

/// "just now", "5m", "3h", "2d", then a date.
String timeAgo(BuildContext context, DateTime time) {
  final l10n = AppLocalizations.of(context);
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return l10n.justNow;
  if (diff.inHours < 1) return l10n.minutesAgo(diff.inMinutes);
  if (diff.inDays < 1) return l10n.hoursAgo(diff.inHours);
  if (diff.inDays < 7) return l10n.daysAgo(diff.inDays);
  final locale = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.yMMMd(locale).format(time);
}

/// Full date + time, e.g. for tooltips and the seen-by list.
String fullTime(BuildContext context, DateTime time) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.yMMMd(locale).add_jm().format(time);
}
