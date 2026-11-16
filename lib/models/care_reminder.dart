/// The two litter-box notifications PurrClean sends.
enum LitterAlert {
  /// The cat used the box and did their business.
  catVisit('cat_visit', 'visit'),

  /// The box has not been cleaned for 2 weeks.
  cleanOverdue('litter_cleaning', 'clean_overdue');

  const LitterAlert(this.prefKey, this.type);

  /// Key used by Settings -> Notification Preferences (LocalProfileStore).
  final String prefKey;

  /// Value of data['type'] in the push message sent by the Cloud Function.
  final String type;
}

/// How long ago the owner last cleaned the litter box.
class CleaningStatus {
  const CleaningStatus({
    required this.lastCleaned,
    required this.daysSinceClean,
    required this.overdue,
  });

  /// Days without cleaning before the reminder is sent.
  /// The Cloud Function (litter_notifications.js) uses the same number.
  static const int cleanAfterDays = 14;

  final DateTime lastCleaned;
  final int daysSinceClean;
  final bool overdue;

  int get daysLeft =>
      (cleanAfterDays - daysSinceClean).clamp(0, cleanAfterDays).toInt();
}