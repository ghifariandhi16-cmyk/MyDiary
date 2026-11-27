class MoodLog {
  final String dateKey;
  final String mood;

  const MoodLog({required this.dateKey, required this.mood});

  Map<String, dynamic> toJson() => {'dateKey': dateKey, 'mood': mood};

  factory MoodLog.fromJson(Map<String, dynamic> json) => MoodLog(
    dateKey: json['dateKey'] as String? ?? '',
    mood: json['mood'] as String? ?? '😊',
  );

  static Map<String, int> countWithinLastDays(
    Iterable<MoodLog> logs,
    DateTime today, {
    int dayCount = 7,
  }) {
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final firstDay = normalizedToday.subtract(Duration(days: dayCount - 1));
    final counts = <String, int>{'😭': 0, '😞': 0, '😐': 0, '😊': 0, '🙂': 0};
    for (final log in logs) {
      final date = DateTime.tryParse(log.dateKey);
      if (date != null &&
          !date.isBefore(firstDay) &&
          !date.isAfter(normalizedToday) &&
          counts.containsKey(log.mood)) {
        counts[log.mood] = counts[log.mood]! + 1;
      }
    }
    return counts;
  }
}
