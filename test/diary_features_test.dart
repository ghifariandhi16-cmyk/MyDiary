import 'package:flutter_test/flutter_test.dart';
import 'package:my_diary/models/diary_entry.dart';
import 'package:my_diary/models/mood_log.dart';

void main() {
  test('diary search matches title and body without case sensitivity', () {
    final entry = DiaryEntry(
      id: '1',
      title: 'A Quiet Morning',
      text: 'Coffee by the window',
      date: 'Nov 18, 2026',
      dateKey: '2026-11-18',
      mood: '😊',
      photo: 'local/photo.jpg',
    );

    expect(entry.matchesSearch('quiet'), isTrue);
    expect(entry.matchesSearch('WINDOW'), isTrue);
    expect(entry.matchesSearch('holiday'), isFalse);
    expect(entry.toCloudJson().containsKey('photo'), isFalse);
  });

  test('mood summary counts the last seven days and ignores future logs', () {
    final counts = MoodLog.countWithinLastDays(const [
      MoodLog(dateKey: '2026-11-12', mood: '😐'),
      MoodLog(dateKey: '2026-11-18', mood: '😊'),
      MoodLog(dateKey: '2026-11-19', mood: '😭'),
    ], DateTime(2026, 11, 18, 18));

    expect(counts['😐'], 1);
    expect(counts['😊'], 1);
    expect(counts['😭'], 0);
  });
}
