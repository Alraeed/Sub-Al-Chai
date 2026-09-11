import 'package:intl/intl.dart';

/// Arabic-first time labels for bubbles and lists.
abstract final class TimeFormat {
  static String chatTime(int utcMs) {
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(utcMs).toLocal();
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime day = DateTime(t.year, t.month, t.day);
    if (day == today) {
      return DateFormat('HH:mm').format(t);
    }
    if (day == today.subtract(const Duration(days: 1))) {
      return 'امس';
    }
    return DateFormat('d MMM').format(t);
  }

  static String listTime(int utcMs) {
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(utcMs).toLocal();
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime day = DateTime(t.year, t.month, t.day);
    if (day == today) {
      return DateFormat('HH:mm').format(t);
    }
    if (day == today.subtract(const Duration(days: 1))) {
      return 'امس';
    }
    return DateFormat('d MMM').format(t);
  }
}