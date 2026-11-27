import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_diary/controllers/diary_controller.dart';
import 'package:my_diary/models/diary_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'diary entries are isolated by user and migrate legacy entries',
    () async {
      SharedPreferences.setMockInitialValues({
        'entries': jsonEncode([
          {
            'id': 'old',
            'title': 'Old note',
            'text': 'Local note',
            'date': 'Nov 18, 2026',
            'mood': '😊',
            'photo': '',
          },
        ]),
      });

      final firstUserEntries = await DiaryStore.all('user-a');
      expect(firstUserEntries.single.title, 'Old note');

      await DiaryStore.save('user-b', [
        DiaryEntry(
          id: 'new',
          title: 'Private note',
          text: '',
          date: 'Nov 18, 2026',
          mood: '😊',
        ),
      ]);

      expect((await DiaryStore.all('user-a')).single.id, 'old');
      expect((await DiaryStore.all('user-b')).single.id, 'new');
    },
  );
}
