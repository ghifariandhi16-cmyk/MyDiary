import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import '../controllers/auth_controller.dart';
import '../controllers/diary_controller.dart';
import '../controllers/reminder_controller.dart';
import '../models/diary_entry.dart';
import '../models/mood_log.dart';
import '../theme/app_colors.dart';
import 'empty_state.dart';
import 'entry_editor.dart';

class HomePage extends StatefulWidget {
  final AuthController authController;
  final String userId;
  final String email;
  final String userName;

  const HomePage({
    super.key,
    required this.authController,
    required this.userId,
    required this.email,
    required this.userName,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _searchController = TextEditingController();
  int tab = 0;
  List<DiaryEntry> entries = [];
  List<MoodLog> moodLogs = [];
  String todayMood = '😊';
  String searchQuery = '';
  DateTime focusedDay = DateTime.now();
  DateTime? selectedDay;
  StreamSubscription<FirebaseException>? _syncErrorSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _entriesSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _moodsSubscription;
  int reminderHour = 21;
  int reminderMinute = 0;
  bool reminder = true;
  bool darkMode = false;
  bool showCalendar = true;
  bool _reminderConfigured = false;
  bool _entriesSyncReady = false;
  bool _moodsSyncReady = false;
  bool _entriesFromCache = false;
  bool _moodsFromCache = false;
  bool _entriesHavePendingWrites = false;
  bool _moodsHavePendingWrites = false;
  String? _syncErrorMessage;
  String displayName = 'Diary User';

  @override
  void initState() {
    super.initState();
    displayName = widget.userName;
    _syncErrorSubscription = DiaryStore.syncErrors.listen((error) {
      if (mounted) {
        setState(() => _syncErrorMessage = error.message ?? error.code);
      }
      _showMessage(
        'Sinkronisasi cloud gagal. Catatan lokal tetap tersedia: '
        '${error.message ?? error.code}',
      );
    });
    _load();
  }

  @override
  void dispose() {
    unawaited(_syncErrorSubscription?.cancel());
    unawaited(_entriesSubscription?.cancel());
    unawaited(_moodsSubscription?.cancel());
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final e = await DiaryStore.all(widget.userId);
    final p = await SharedPreferences.getInstance();
    final savedReminder = p.getBool(_settingKey('reminder')) ?? true;
    final savedHour = p.getInt(_settingKey('reminder_hour')) ?? 21;
    final savedMinute = p.getInt(_settingKey('reminder_minute')) ?? 0;
    if (mounted) {
      setState(() {
        entries = e;
        todayMood = p.getString(_settingKey('today_mood')) ?? '😊';
        reminder = savedReminder;
        reminderHour = savedHour;
        reminderMinute = savedMinute;
        darkMode = p.getBool(_settingKey('dark_mode')) ?? false;
        displayName = widget.userName;
      });
    }

    if (!_reminderConfigured) {
      _reminderConfigured = true;
      if (savedReminder) {
        final scheduled = await _scheduleReminder(showPermissionMessage: false);
        if (!scheduled) {
          await p.setBool(_settingKey('reminder'), false);
          if (mounted) setState(() => reminder = false);
        }
      }
    }

    try {
      final syncedEntries = await DiaryStore.syncEntries(widget.userId);
      var syncedMoods = await DiaryStore.moodLogs(widget.userId);
      final hasTodayMood = syncedMoods.any((log) => log.dateKey == _todayKey());
      final savedTodayMood = p.getString(_settingKey('today_mood'));
      if (!hasTodayMood && savedTodayMood != null) {
        final legacyMood = MoodLog(dateKey: _todayKey(), mood: savedTodayMood);
        syncedMoods = [legacyMood, ...syncedMoods];
        await DiaryStore.saveMoodLog(widget.userId, legacyMood);
      }
      if (!mounted) return;
      final todayLogs = syncedMoods
          .where((log) => log.dateKey == _todayKey())
          .toList();
      final todayLog = todayLogs.isEmpty ? null : todayLogs.first;
      setState(() {
        entries = syncedEntries;
        moodLogs = syncedMoods;
        if (todayLog != null) todayMood = todayLog.mood;
      });
      _startCloudListeners();
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(() => _syncErrorMessage = error.message ?? error.code);
      }
      _showMessage(
        'Sinkronisasi cloud gagal. Catatan lokal tetap tersedia: '
        '${error.message ?? error.code}',
      );
    }
  }

  void _startCloudListeners() {
    _entriesSubscription ??= DiaryStore.watchEntries(widget.userId).listen(
      (snapshot) async {
        try {
          final remote = await DiaryStore.cacheRemoteEntries(
            widget.userId,
            snapshot.docs,
          );
          if (mounted) {
            setState(() {
              entries = remote;
              _entriesSyncReady = true;
              _entriesFromCache = snapshot.metadata.isFromCache;
              _entriesHavePendingWrites = snapshot.metadata.hasPendingWrites;
              _syncErrorMessage = null;
            });
          }
        } on FirebaseException catch (error) {
          if (mounted) {
            setState(() => _syncErrorMessage = error.message ?? error.code);
          }
          _showMessage(
            'Sinkronisasi diary gagal: ${error.message ?? error.code}',
          );
        }
      },
      onError: (Object error) {
        if (mounted) setState(() => _syncErrorMessage = error.toString());
        _showMessage('Sinkronisasi diary gagal: $error');
      },
    );
    _moodsSubscription ??= DiaryStore.watchMoodLogs(widget.userId).listen(
      (snapshot) async {
        try {
          final remote = await DiaryStore.cacheRemoteMoodLogs(
            widget.userId,
            snapshot.docs,
          );
          if (!mounted) return;
          final todayLogs = remote
              .where((log) => log.dateKey == _todayKey())
              .toList();
          setState(() {
            moodLogs = remote;
            if (todayLogs.isNotEmpty) todayMood = todayLogs.first.mood;
            _moodsSyncReady = true;
            _moodsFromCache = snapshot.metadata.isFromCache;
            _moodsHavePendingWrites = snapshot.metadata.hasPendingWrites;
            _syncErrorMessage = null;
          });
        } on FirebaseException catch (error) {
          if (mounted) {
            setState(() => _syncErrorMessage = error.message ?? error.code);
          }
          _showMessage(
            'Sinkronisasi mood gagal: ${error.message ?? error.code}',
          );
        }
      },
      onError: (Object error) {
        if (mounted) setState(() => _syncErrorMessage = error.toString());
        _showMessage('Sinkronisasi mood gagal: $error');
      },
    );
  }

  String _settingKey(String key) => '${widget.userId}_$key';

  String _todayKey() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _newEntry([DiaryEntry? entry]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EntryEditor(userId: widget.userId, entry: entry),
      ),
    );
    await _load();
  }

  Future<void> _mood(String mood) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_settingKey('today_mood'), mood);
    final log = MoodLog(dateKey: _todayKey(), mood: mood);
    setState(() {
      todayMood = mood;
      moodLogs = [
        log,
        ...moodLogs.where((saved) => saved.dateKey != log.dateKey),
      ];
    });
    try {
      await DiaryStore.saveMoodLog(widget.userId, log);
    } on FirebaseException catch (error) {
      _showMessage(
        'Mood tersimpan di perangkat, tetapi gagal disinkronkan: '
        '${error.message ?? error.code}',
      );
    }
  }

  Future<void> _toggleDarkMode() async {
    final p = await SharedPreferences.getInstance();
    final next = !darkMode;
    await p.setBool(_settingKey('dark_mode'), next);
    if (mounted) setState(() => darkMode = next);
  }

  Future<void> _deleteAllEntries() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus semua diary?'),
        content: const Text('Semua catatan akan dihapus dari perangkat ini.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await DiaryStore.deleteAllEntries(widget.userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Semua diary berhasil dihapus.')),
        );
      }
    } on FirebaseException catch (error) {
      _showMessage(
        'Diary dihapus dari perangkat, tetapi gagal disinkronkan: '
        '${error.message ?? error.code}',
      );
    }
    if (mounted) setState(() => entries = []);
  }

  Future<bool> _scheduleReminder({bool showPermissionMessage = true}) async {
    try {
      final granted = await ReminderController.scheduleDaily(
        hour: reminderHour,
        minute: reminderMinute,
      );
      if (!granted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_settingKey('reminder'), false);
        if (mounted) setState(() => reminder = false);
        if (showPermissionMessage) {
          _showMessage('Izin notifikasi belum diberikan.');
        }
      }
      return granted;
    } on PlatformException catch (error) {
      if (showPermissionMessage) {
        _showMessage('Pengingat gagal dijadwalkan: $error');
      }
      return false;
    }
  }

  Future<void> _toggleReminder(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled) {
      final scheduled = await _scheduleReminder();
      if (!scheduled || !mounted) return;
    } else {
      await ReminderController.cancel();
    }
    await prefs.setBool(_settingKey('reminder'), enabled);
    if (mounted) setState(() => reminder = enabled);
  }

  Future<void> _selectReminderTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: reminderHour, minute: reminderMinute),
    );
    if (time == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_settingKey('reminder_hour'), time.hour);
    await prefs.setInt(_settingKey('reminder_minute'), time.minute);
    if (mounted) {
      setState(() {
        reminderHour = time.hour;
        reminderMinute = time.minute;
      });
    }
    if (reminder) await _scheduleReminder();
  }

  String get _reminderTimeLabel =>
      TimeOfDay(hour: reminderHour, minute: reminderMinute).format(context);

  DateTime _dateForEntry(DiaryEntry entry) {
    if (entry.dateKey.isNotEmpty) {
      return DateTime.tryParse(entry.dateKey) ?? DateTime(2000);
    }
    try {
      return DateFormat('MMM d, yyyy', 'en_US').parse(entry.date);
    } on FormatException {
      return DateTime(2000);
    }
  }

  List<DiaryEntry> _entriesForDay(DateTime day) =>
      entries.where((entry) => isSameDay(_dateForEntry(entry), day)).toList();

  List<DiaryEntry> get _filteredEntries => entries.where((entry) {
    final matchesDay =
        selectedDay == null || isSameDay(_dateForEntry(entry), selectedDay);
    return entry.matchesSearch(searchQuery) && matchesDay;
  }).toList();

  Map<String, int> _weeklyMoodCounts() =>
      MoodLog.countWithinLastDays(moodLogs, DateTime.now());

  List<DiaryEntry> get _recentEntries {
    final recent = [...entries]
      ..sort((a, b) => _dateForEntry(b).compareTo(_dateForEntry(a)));
    return recent.take(3).toList();
  }

  int get _entriesThisWeek {
    final today = DateTime.now();
    final start = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 6));
    return entries.where((entry) {
      final date = _dateForEntry(entry);
      return !date.isBefore(start) &&
          !date.isAfter(DateTime(today.year, today.month, today.day));
    }).length;
  }

  String get _mostFrequentWeeklyMood {
    final counts = _weeklyMoodCounts();
    final topMood = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return topMood.value == 0 ? 'Belum ada' : topMood.key;
  }

  int get _writingStreak {
    final writtenDays = entries
        .map(_dateForEntry)
        .map((date) => DateTime(date.year, date.month, date.day))
        .toSet();
    final today = DateTime.now();
    var cursor = DateTime(today.year, today.month, today.day);
    if (!writtenDays.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!writtenDays.contains(cursor)) return 0;
    }

    var streak = 0;
    while (writtenDays.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  String get _syncStatusLabel {
    if (_syncErrorMessage != null) return 'Sinkronisasi gagal';
    if (!_entriesSyncReady || !_moodsSyncReady) return 'Memeriksa sinkronisasi';
    if (_entriesFromCache ||
        _moodsFromCache ||
        _entriesHavePendingWrites ||
        _moodsHavePendingWrites) {
      return 'Menunggu koneksi untuk sinkron';
    }
    return 'Tersimpan di cloud';
  }

  Color get _syncStatusColor {
    if (_syncErrorMessage != null) return Colors.redAccent;
    if (!_entriesSyncReady ||
        !_moodsSyncReady ||
        _entriesFromCache ||
        _moodsFromCache ||
        _entriesHavePendingWrites ||
        _moodsHavePendingWrites) {
      return const Color(0xFFB7791F);
    }
    return teal;
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_dashboard(), _diaryList(), _moodPage(), _profilePage()];
    final scaffoldBg = darkMode
        ? const Color(0xFF111827)
        : const Color(0xFFF7FAF9);
    final cardColor = darkMode ? const Color(0xFF1F2937) : Colors.white;
    final textColor = darkMode ? Colors.white : ink;
    final mutedColor = darkMode ? const Color(0xFFB9C5D1) : muted;
    return Scaffold(
      backgroundColor: scaffoldBg,
      body: SafeArea(
        child: IndexedStack(index: tab, children: pages),
      ),
      floatingActionButton: tab == 0 || tab == 1
          ? FloatingActionButton(
              backgroundColor: teal,
              foregroundColor: Colors.white,
              elevation: 5,
              onPressed: () => _newEntry(),
              child: const Icon(Icons.add, size: 30),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: cardColor,
        elevation: 8,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: SizedBox(
          height: 66,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _nav(Icons.home_rounded, 'Home', 0, textColor, mutedColor),
              _nav(Icons.menu_book_rounded, 'Diary', 1, textColor, mutedColor),
              const SizedBox(width: 42),
              _nav(Icons.mood_rounded, 'Mood', 2, textColor, mutedColor),
              _nav(
                Icons.person_outline_rounded,
                'Profile',
                3,
                textColor,
                mutedColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nav(
    IconData icon,
    String label,
    int i,
    Color textColor,
    Color mutedColor,
  ) => InkWell(
    onTap: () => setState(() => tab = i),
    child: SizedBox(
      width: 60,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: tab == i ? teal : mutedColor, size: 22),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: tab == i ? teal : mutedColor,
              fontWeight: tab == i ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ],
      ),
    ),
  );
  Widget _dashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 95),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting(),
                      style: TextStyle(
                        color: darkMode ? Colors.white : ink,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          displayName,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: darkMode ? Colors.white : ink,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text('🌿', style: TextStyle(fontSize: 18)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'How are you feeling today?',
                      style: TextStyle(
                        color: darkMode ? const Color(0xFFCBD5E1) : muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: mint, width: 2),
                ),
                child: const Icon(Icons.spa_rounded, color: teal, size: 27),
              ),
            ],
          ),
          const SizedBox(height: 23),
          _syncStatusCard(),
          const SizedBox(height: 14),
          _weeklySummaryCard(),
          const SizedBox(height: 14),
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.event_note_rounded, color: teal, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        "Today's Diary",
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: ink,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      DateFormat('MMM d, yyyy').format(DateTime.now()),
                      style: const TextStyle(color: muted, fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                if (entries.isNotEmpty)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          entries.first.text.isEmpty
                              ? 'A little moment from your day, saved just for you.'
                              : entries.first.text,
                          maxLines: 6,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.55,
                            color: ink,
                          ),
                        ),
                      ),
                      if (entries.first.photo.isNotEmpty)
                        const SizedBox(width: 10),
                      if (entries.first.photo.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(entries.first.photo),
                            width: 75,
                            height: 95,
                            fit: BoxFit.cover,
                          ),
                        ),
                    ],
                  )
                else
                  const Text(
                    'Today was a beautiful reminder that small steps still move you forward. Take a moment to notice the little things that make you smile.',
                    style: TextStyle(fontSize: 11, height: 1.55, color: ink),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 36,
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: mint,
                      foregroundColor: deepTeal,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    onPressed: () => _newEntry(),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.edit_outlined, size: 15),
                        SizedBox(width: 7),
                        Text(
                          'Write New Entry',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.mood_outlined, color: teal, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'Mood Tracker',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: ink,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                const Text(
                  'How are you feeling?',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
                const SizedBox(height: 13),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _moodOption('😭', 'Very Bad', const Color(0xFFC7B7ED)),
                    _moodOption('😞', 'Bad', const Color(0xFF9BD5EF)),
                    _moodOption('😐', 'Okay', const Color(0xFF91D9C8)),
                    _moodOption('😊', 'Good', const Color(0xFFB8E5A0)),
                    _moodOption('🙂', 'Great', const Color(0xFFF5D18A)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _recentEntriesCard(),
          const SizedBox(height: 14),
          _sectionCard(
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: mint,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.notifications_none_rounded,
                    color: teal,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Reminder',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      SizedBox(height: 5),
                      const Text(
                        'Daily reflection time',
                        style: TextStyle(fontSize: 11, color: ink),
                      ),
                      Text(
                        'Every day at $_reminderTimeLabel',
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                      TextButton(
                        onPressed: _selectReminderTime,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Change time',
                          style: TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: reminder,
                  activeThumbColor: teal,
                  activeTrackColor: teal.withValues(alpha: 0.25),
                  onChanged: _toggleReminder,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Center(
            child: Text(
              'Made for your little moments ♡',
              style: TextStyle(color: muted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _syncStatusCard() => _sectionCard(
    child: Row(
      children: [
        Icon(
          _syncErrorMessage != null
              ? Icons.cloud_off_rounded
              : _syncStatusLabel == 'Tersimpan di cloud'
              ? Icons.cloud_done_rounded
              : Icons.cloud_sync_rounded,
          color: _syncStatusColor,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _syncStatusLabel,
                style: TextStyle(
                  color: darkMode ? Colors.white : ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                _syncErrorMessage == null
                    ? 'Catatan dan mood disinkronkan dengan akunmu'
                    : 'Data lokal tetap aman: $_syncErrorMessage',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: darkMode ? const Color(0xFFCBD5E1) : muted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Coba sinkronkan lagi',
          onPressed: _load,
          icon: Icon(Icons.refresh_rounded, color: _syncStatusColor, size: 20),
        ),
      ],
    ),
  );

  Widget _weeklySummaryCard() => _sectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Minggu ini',
          style: TextStyle(
            color: darkMode ? Colors.white : ink,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _summaryValue(
                icon: Icons.menu_book_rounded,
                value: '$_entriesThisWeek',
                label: 'catatan',
              ),
            ),
            Container(width: 1, height: 38, color: mint),
            Expanded(
              child: _summaryValue(
                icon: Icons.mood_rounded,
                value: _mostFrequentWeeklyMood,
                label: 'mood terbanyak',
              ),
            ),
            Container(width: 1, height: 38, color: mint),
            Expanded(
              child: _summaryValue(
                icon: Icons.local_fire_department_rounded,
                value: '$_writingStreak hari',
                label: 'streak menulis',
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _summaryValue({
    required IconData icon,
    required String value,
    required String label,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Column(
      children: [
        Icon(icon, color: teal, size: 17),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: darkMode ? Colors.white : ink,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, fontSize: 9),
        ),
      ],
    ),
  );

  Widget _recentEntriesCard() => _sectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Catatan terbaru',
                style: TextStyle(
                  color: darkMode ? Colors.white : ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => tab = 1),
              child: const Text('Lihat semua'),
            ),
          ],
        ),
        if (_recentEntries.isEmpty)
          const Text(
            'Catatanmu akan muncul di sini setelah kamu menulis.',
            style: TextStyle(color: muted, fontSize: 11),
          )
        else
          for (final entry in _recentEntries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              onTap: () => _newEntry(entry),
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: mint,
                child: Text(entry.mood, style: const TextStyle(fontSize: 18)),
              ),
              title: Text(
                entry.title.isEmpty ? 'Catatan tanpa judul' : entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: darkMode ? Colors.white : ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                entry.text.isEmpty
                    ? entry.date
                    : '${entry.date} · ${entry.text}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: muted, fontSize: 10),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: teal,
                size: 18,
              ),
            ),
      ],
    ),
  );

  Widget _moodOption(String emoji, String label, Color color) {
    return GestureDetector(
      onTap: () => _mood(emoji),
      child: Column(
        children: [
          Container(
            width: 37,
            height: 37,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: todayMood == emoji ? deepTeal : Colors.transparent,
                width: 2,
              ),
              boxShadow: todayMood == emoji
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.7),
                        blurRadius: 0,
                        spreadRadius: 3,
                      ),
                    ]
                  : const [],
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 19)),
          ),
          const SizedBox(height: 7),
          Text(label, style: const TextStyle(fontSize: 9, color: muted)),
        ],
      ),
    );
  }

  Widget _sectionCard({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: darkMode ? const Color(0xFF1F2937) : Colors.white,
      borderRadius: BorderRadius.circular(19),
      boxShadow: darkMode
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ]
          : [
              BoxShadow(
                color: const Color(0xFF4C7970).withValues(alpha: 0.07),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
    ),
    child: child,
  );

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12
        ? 'Good morning,'
        : h < 17
        ? 'Good afternoon,'
        : 'Good evening,';
  }

  Widget _diaryList() {
    final filtered = _filteredEntries;
    return Column(
      children: [
        _header('My Diary', 'Search, browse, and revisit your moments.'),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => searchQuery = value),
            decoration: InputDecoration(
              hintText: 'Search diary entries',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: searchQuery.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => searchQuery = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: darkMode ? const Color(0xFF1F2937) : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => showCalendar = !showCalendar),
                icon: Icon(
                  showCalendar
                      ? Icons.calendar_month_rounded
                      : Icons.calendar_today_rounded,
                ),
                label: Text(showCalendar ? 'Hide calendar' : 'Show calendar'),
              ),
              const Spacer(),
              if (selectedDay != null)
                TextButton(
                  onPressed: () => setState(() => selectedDay = null),
                  child: const Text('Show all dates'),
                ),
            ],
          ),
        ),
        if (showCalendar)
          SizedBox(
            height: 310,
            child: TableCalendar<DiaryEntry>(
              firstDay: DateTime(2000),
              lastDay: DateTime(2100),
              focusedDay: focusedDay,
              selectedDayPredicate: (day) =>
                  selectedDay != null && isSameDay(selectedDay, day),
              eventLoader: _entriesForDay,
              startingDayOfWeek: StartingDayOfWeek.monday,
              rowHeight: 36,
              daysOfWeekHeight: 22,
              calendarStyle: const CalendarStyle(
                markerDecoration: BoxDecoration(
                  color: teal,
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: deepTeal,
                  shape: BoxShape.circle,
                ),
                todayDecoration: BoxDecoration(
                  color: Color(0xFF8EDACD),
                  shape: BoxShape.circle,
                ),
                outsideDaysVisible: false,
              ),
              onDaySelected: (selected, focused) {
                setState(() {
                  selectedDay = selected;
                  focusedDay = focused;
                });
              },
              onPageChanged: (focused) => setState(() => focusedDay = focused),
            ),
          ),
        Expanded(
          child: filtered.isEmpty
              ? EmptyState(
                  icon: Icons.menu_book_rounded,
                  title: entries.isEmpty
                      ? 'Your story starts here'
                      : 'No matching entries',
                  subtitle: entries.isEmpty
                      ? 'Write your first diary entry and keep this moment forever.'
                      : 'Try another search or date.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(18),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final entry = filtered[index];
                    return _sectionCard(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: () => _newEntry(entry),
                        leading: CircleAvatar(
                          backgroundColor: mint,
                          child: Text(
                            entry.mood,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                        title: Text(
                          entry.title.isEmpty ? 'Untitled entry' : entry.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: darkMode ? Colors.white : ink,
                          ),
                        ),
                        subtitle: Text(
                          '${entry.date}  •  ${entry.text}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: darkMode ? const Color(0xFFCBD5E1) : muted,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right, color: teal),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _moodPage() {
    final counts = _weeklyMoodCounts();
    final largestCount = counts.values.fold<int>(
      0,
      (largest, moodCount) => moodCount > largest ? moodCount : largest,
    );
    final total = counts.values.fold<int>(
      0,
      (totalCount, moodCount) => totalCount + moodCount,
    );
    return SingleChildScrollView(
      child: Column(
        children: [
          _header('Mood Tracker', 'Small check-ins matter.'),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _sectionCard(
                  child: Column(
                    children: [
                      Text(
                        'How are you feeling today?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: darkMode ? Colors.white : ink,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...[
                        ('😭', 'Very Bad'),
                        ('😞', 'Bad'),
                        ('😐', 'Okay'),
                        ('😊', 'Good'),
                        ('🙂', 'Great'),
                      ].map(
                        (mood) => ListTile(
                          onTap: () => _mood(mood.$1),
                          leading: Text(
                            mood.$1,
                            style: const TextStyle(fontSize: 28),
                          ),
                          title: Text(
                            mood.$2,
                            style: TextStyle(
                              color: darkMode ? Colors.white : ink,
                            ),
                          ),
                          trailing: todayMood == mood.$1
                              ? const Icon(Icons.check_circle, color: teal)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _sectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your last 7 days',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: darkMode ? Colors.white : ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$total mood check-ins',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      for (final mood in [
                        ('😭', 'Very Bad'),
                        ('😞', 'Bad'),
                        ('😐', 'Okay'),
                        ('😊', 'Good'),
                        ('🙂', 'Great'),
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(
                            children: [
                              Text(
                                mood.$1,
                                style: const TextStyle(fontSize: 20),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 68,
                                child: Text(
                                  mood.$2,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: darkMode ? Colors.white : ink,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: largestCount == 0
                                      ? 0
                                      : counts[mood.$1]! / largestCount,
                                  minHeight: 8,
                                  borderRadius: BorderRadius.circular(8),
                                  color: teal,
                                  backgroundColor: mint,
                                ),
                              ),
                              SizedBox(
                                width: 28,
                                child: Text(
                                  '${counts[mood.$1]}',
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (total == 0)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Your mood history will appear here after a check-in.',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profilePage() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      children: [
        const SizedBox(height: 20),
        Container(
          width: 94,
          height: 94,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [teal, Color(0xFF78D7C2)]),
          ),
          child: const Icon(
            Icons.person_rounded,
            color: Colors.white,
            size: 50,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          displayName,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: darkMode ? Colors.white : ink,
          ),
        ),
        Text(
          'My private little world',
          style: TextStyle(color: darkMode ? const Color(0xFFCBD5E1) : muted),
        ),
        const SizedBox(height: 25),
        _sectionCard(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.lock_outline, color: teal),
                title: const Text('Change password'),
                subtitle: const Text('Kirim tautan reset ke email akun'),
                onTap: _sendPasswordReset,
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.color_lens_rounded, color: teal),
                title: Text(darkMode ? 'Dark mode aktif' : 'Dark mode'),
                subtitle: Text(
                  darkMode ? 'Tema gelap sedang aktif' : 'Aktifkan tema gelap',
                ),
                trailing: Switch(
                  value: darkMode,
                  onChanged: (_) {
                    _toggleDarkMode();
                  },
                ),
                onTap: _toggleDarkMode,
              ),
              const Divider(),
              ListTile(
                leading: const Icon(
                  Icons.delete_forever_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text('Hapus semua diary'),
                subtitle: const Text('Kosongkan semua entri'),
                onTap: _deleteAllEntries,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
            label: const Text('Keluar dari akun'),
            style: OutlinedButton.styleFrom(
              foregroundColor: deepTeal,
              padding: const EdgeInsets.all(14),
            ),
          ),
        ),
      ],
    ),
  );
  Widget _header(String title, String subtitle) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  color: darkMode ? Colors.white : ink,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: darkMode ? const Color(0xFFCBD5E1) : muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 45,
          height: 45,
          decoration: const BoxDecoration(color: mint, shape: BoxShape.circle),
          child: const Icon(Icons.auto_stories_rounded, color: teal),
        ),
      ],
    ),
  );
  Future<void> _sendPasswordReset() async {
    try {
      await widget.authController.sendPasswordReset(widget.email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tautan reset password telah dikirim.')),
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Gagal mengirim email reset.')),
      );
    }
  }

  Future<void> _signOut() async {
    try {
      await ReminderController.cancel();
    } on PlatformException catch (error) {
      _showMessage(
        'Pengingat gagal dihentikan: ${error.message ?? error.code}',
      );
      return;
    }
    try {
      await widget.authController.signOut();
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Gagal keluar dari akun.')),
      );
    }
  }
}
