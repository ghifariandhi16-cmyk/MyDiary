import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/diary_entry.dart';
import '../models/mood_log.dart';

class DiaryStore {
  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  static final StreamController<FirebaseException> _syncErrors =
      StreamController<FirebaseException>.broadcast();

  static Stream<FirebaseException> get syncErrors => _syncErrors.stream;

  static CollectionReference<Map<String, dynamic>> _entries(String userId) =>
      _firestore.collection('users').doc(userId).collection('entries');

  static CollectionReference<Map<String, dynamic>> _moods(String userId) =>
      _firestore.collection('users').doc(userId).collection('moods');

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchEntries(
    String userId,
  ) => _entries(userId).snapshots(includeMetadataChanges: true);

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchMoodLogs(
    String userId,
  ) => _moods(userId).snapshots(includeMetadataChanges: true);

  static Future<List<DiaryEntry>> all(String userId) async {
    final p = await SharedPreferences.getInstance();
    final userKey = 'entries_$userId';
    final raw = p.getString(userKey);
    if (raw != null) {
      return _decode(raw);
    }

    final legacyRaw = p.getString('entries');
    if (legacyRaw == null) return [];

    await p.setString(userKey, legacyRaw);
    await p.remove('entries');
    return _decode(legacyRaw);
  }

  static Future<List<DiaryEntry>> syncEntries(String userId) async {
    final localEntries = await all(userId);
    final snapshot = await _entries(userId).get();
    final remoteIds = snapshot.docs.map((document) => document.id).toSet();
    final entriesToUpload = localEntries
        .where((entry) => !remoteIds.contains(entry.id))
        .toList();
    if (entriesToUpload.isNotEmpty) {
      _writeBatches(entriesToUpload, (entry) => _entries(userId).doc(entry.id));
    }

    return cacheRemoteEntries(userId, snapshot.docs);
  }

  static Future<List<DiaryEntry>> cacheRemoteEntries(
    String userId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
  ) async {
    final localEntries = await all(userId);
    final localPhotos = {
      for (final entry in localEntries) entry.id: entry.photo,
    };
    final remoteEntries = documents.map((doc) {
      final entry = DiaryEntry.fromCloudJson(doc.id, doc.data());
      entry.photo = localPhotos[entry.id] ?? '';
      return entry;
    });
    final entriesById = {for (final entry in localEntries) entry.id: entry};
    for (final entry in remoteEntries) {
      entriesById[entry.id] = entry;
    }
    final mergedEntries = entriesById.values.toList()
      ..sort((a, b) => _entryDateKey(b).compareTo(_entryDateKey(a)));
    await save(userId, mergedEntries);
    return mergedEntries;
  }

  static List<DiaryEntry> _decode(String raw) {
    try {
      return (jsonDecode(raw) as List)
          .map((e) => DiaryEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(String userId, List<DiaryEntry> entries) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      'entries_$userId',
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> upsertEntry(String userId, DiaryEntry entry) async {
    final entries = await all(userId);
    entries.removeWhere((saved) => saved.id == entry.id);
    entries.add(entry);
    await save(userId, entries);
    _enqueueWrite(_entries(userId).doc(entry.id).set(entry.toCloudJson()));
  }

  static Future<void> deleteEntry(String userId, String entryId) async {
    final entries = await all(userId);
    entries.removeWhere((entry) => entry.id == entryId);
    await save(userId, entries);
    _enqueueWrite(_entries(userId).doc(entryId).delete());
  }

  static Future<void> deleteAllEntries(String userId) async {
    await save(userId, []);
    final snapshot = await _entries(userId).get();
    for (var start = 0; start < snapshot.docs.length; start += 450) {
      final batch = _firestore.batch();
      final end = (start + 450).clamp(0, snapshot.docs.length);
      for (final document in snapshot.docs.sublist(start, end)) {
        batch.delete(document.reference);
      }
      _enqueueWrite(batch.commit());
    }
  }

  static Future<List<MoodLog>> moodLogs(String userId) async {
    final p = await SharedPreferences.getInstance();
    final key = 'mood_logs_$userId';
    final local = _decodeMoodLogs(p.getString(key) ?? '[]');
    final snapshot = await _moods(userId).get();
    final remoteDates = snapshot.docs.map((document) => document.id).toSet();
    final logsToUpload = local
        .where((log) => !remoteDates.contains(log.dateKey))
        .toList();
    for (var start = 0; start < logsToUpload.length; start += 450) {
      final batch = _firestore.batch();
      final end = (start + 450).clamp(0, logsToUpload.length);
      for (final log in logsToUpload.sublist(start, end)) {
        batch.set(_moods(userId).doc(log.dateKey), log.toJson());
      }
      _enqueueWrite(batch.commit());
    }

    return cacheRemoteMoodLogs(userId, snapshot.docs);
  }

  static Future<List<MoodLog>> cacheRemoteMoodLogs(
    String userId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
  ) async {
    final local = await _moodLogsLocal(userId);
    final logsByDate = {for (final log in local) log.dateKey: log};
    for (final document in documents) {
      final log = MoodLog.fromJson(document.data());
      logsByDate[log.dateKey] = log;
    }
    final merged = logsByDate.values.toList()
      ..sort((a, b) => b.dateKey.compareTo(a.dateKey));
    await _saveMoodLogs(userId, merged);
    return merged;
  }

  static Future<List<MoodLog>> _moodLogsLocal(String userId) async {
    final p = await SharedPreferences.getInstance();
    return _decodeMoodLogs(p.getString('mood_logs_$userId') ?? '[]');
  }

  static Future<void> saveMoodLog(String userId, MoodLog log) async {
    final p = await SharedPreferences.getInstance();
    final logs = _decodeMoodLogs(p.getString('mood_logs_$userId') ?? '[]');
    logs.removeWhere((saved) => saved.dateKey == log.dateKey);
    logs.add(log);
    await _saveMoodLogs(userId, logs);
    _enqueueWrite(_moods(userId).doc(log.dateKey).set(log.toJson()));
  }

  static Future<void> _saveMoodLogs(String userId, List<MoodLog> logs) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      'mood_logs_$userId',
      jsonEncode(logs.map((log) => log.toJson()).toList()),
    );
  }

  static List<MoodLog> _decodeMoodLogs(String raw) {
    try {
      return (jsonDecode(raw) as List)
          .map((item) => MoodLog.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } on FormatException {
      return [];
    } on TypeError {
      return [];
    }
  }

  static void _writeBatches(
    List<DiaryEntry> entries,
    DocumentReference<Map<String, dynamic>> Function(DiaryEntry) reference,
  ) {
    for (var start = 0; start < entries.length; start += 450) {
      final batch = _firestore.batch();
      final end = (start + 450).clamp(0, entries.length);
      for (final entry in entries.sublist(start, end)) {
        batch.set(reference(entry), entry.toCloudJson());
      }
      _enqueueWrite(batch.commit());
    }
  }

  static void _enqueueWrite(Future<void> operation) {
    unawaited(_observeWrite(operation));
  }

  static Future<void> _observeWrite(Future<void> operation) async {
    try {
      await operation;
    } on FirebaseException catch (error) {
      _syncErrors.add(error);
    }
  }

  static String _entryDateKey(DiaryEntry entry) {
    if (entry.dateKey.isNotEmpty) return entry.dateKey;
    return entry.date;
  }
}
