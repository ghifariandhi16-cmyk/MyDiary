class DiaryEntry {
  String id, title, text, date, mood, photo;
  String dateKey;
  DiaryEntry({
    required this.id,
    required this.title,
    required this.text,
    required this.date,
    required this.mood,
    this.photo = '',
    this.dateKey = '',
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'text': text,
    'date': date,
    'mood': mood,
    'photo': photo,
    'dateKey': dateKey,
  };

  Map<String, dynamic> toCloudJson() => {
    'title': title,
    'text': text,
    'date': date,
    'dateKey': dateKey,
    'mood': mood,
  };

  factory DiaryEntry.fromJson(Map<String, dynamic> j) => DiaryEntry(
    id: j['id'] ?? '',
    title: j['title'] ?? '',
    text: j['text'] ?? '',
    date: j['date'] ?? '',
    mood: j['mood'] ?? '😊',
    photo: j['photo'] ?? '',
    dateKey: j['dateKey'] ?? '',
  );

  factory DiaryEntry.fromCloudJson(String id, Map<String, dynamic> data) =>
      DiaryEntry(
        id: id,
        title: data['title'] as String? ?? '',
        text: data['text'] as String? ?? '',
        date: data['date'] as String? ?? '',
        mood: data['mood'] as String? ?? '😊',
        dateKey: data['dateKey'] as String? ?? '',
      );

  bool matchesSearch(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    return normalizedQuery.isEmpty ||
        title.toLowerCase().contains(normalizedQuery) ||
        text.toLowerCase().contains(normalizedQuery);
  }
}
