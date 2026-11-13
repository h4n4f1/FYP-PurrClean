/// The three litter-care jobs PurrClean reminds the owner about.
enum CareTask {
  /// Scoop / clean the litter box.
  cleanBox('litter_cleaning', 1001),

  /// Empty the waste drawer.
  wasteDisposal('waste_disposal', 1002),

  /// Top the litter up.
  refillLitter('litter_refill', 1003);

  const CareTask(this.prefKey, this.notificationId);

  /// Key used by Settings -> Notification Preferences (LocalProfileStore).
  final String prefKey;

  /// Fixed id so a repeat reminder replaces the old system notification
  /// instead of stacking.
  final int notificationId;
}

/// One reminder shown to the owner (as a popup or a system notification).
class CareReminder {
  const CareReminder({
    required this.task,
    required this.title,
    required this.message,
    this.urgent = false,
    this.progress,
  });

  final CareTask task;
  final String title;
  final String message;

  /// Red styling + shorter re-notify gap.
  final bool urgent;

  /// Optional 0.0 - 1.0 bar (used for the waste drawer).
  final double? progress;
}

/// Snapshot of how the litter box is doing. Shown on Home ("Litter Care")
/// and used to decide which reminders are due.
class CareStatus {
  const CareStatus({
    required this.wasteGrams,
    required this.wastePct,
    required this.visitsSinceClean,
    required this.hoursSinceClean,
    required this.highAmmonia,
    required this.daysSinceRefill,
    required this.lastClean,
    required this.lastWasteEmptied,
    required this.lastRefill,
    required this.due,
  });

  final double wasteGrams;
  final int wastePct; // 0 - 100
  final int visitsSinceClean;
  final int hoursSinceClean;
  final bool highAmmonia;
  final int daysSinceRefill;
  final DateTime lastClean;
  final DateTime lastWasteEmptied;
  final DateTime lastRefill;

  /// Tasks that are due right now.
  final Set<CareTask> due;

  bool isDue(CareTask task) => due.contains(task);
}