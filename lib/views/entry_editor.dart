import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../controllers/diary_controller.dart';
import '../models/diary_entry.dart';
import '../theme/app_colors.dart';

class EntryEditor extends StatefulWidget {
  final String userId;
  final DiaryEntry? entry;
  const EntryEditor({super.key, required this.userId, this.entry});
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  late TextEditingController title, text;
  String mood = '😊', photo = '';
  final picker = ImagePicker();
  bool saving = false;
  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    title = TextEditingController(text: e?.title ?? '');
    text = TextEditingController(text: e?.text ?? '');
    mood = e?.mood ?? '😊';
    photo = e?.photo ?? '';
  }

  Future<void> _photo() async {
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (x != null) setState(() => photo = x.path);
  }

  Future<void> _delete() async {
    if (widget.entry == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus entry ini?'),
        content: const Text('Catatan ini akan dihapus permanen dari diary.'),
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
    await DiaryStore.deleteEntry(widget.userId, widget.entry!.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _save() async {
    setState(() => saving = true);
    final e = DiaryEntry(
      id: widget.entry?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: title.text.trim(),
      text: text.text.trim(),
      date: DateFormat('MMM d, yyyy').format(DateTime.now()),
      mood: mood,
      photo: photo,
      dateKey: DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );
    await DiaryStore.upsertEntry(widget.userId, e);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.entry == null ? 'New Diary Entry' : 'Edit Diary Entry',
      ),
      actions: [
        if (widget.entry != null)
          IconButton(
            onPressed: _delete,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Colors.redAccent,
            ),
          ),
        IconButton(
          onPressed: _save,
          icon: const Icon(Icons.check_rounded, color: teal),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now()),
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
            decoration: const InputDecoration(
              hintText: 'Give this memory a title',
              border: InputBorder.none,
            ),
          ),
          const Divider(),
          TextField(
            controller: text,
            minLines: 8,
            maxLines: 18,
            decoration: const InputDecoration(
              hintText: 'Dear diary, today I feel...',
              border: InputBorder.none,
            ),
            style: const TextStyle(height: 1.6, color: ink),
          ),
          const SizedBox(height: 15),
          const Text(
            'How did you feel?',
            style: TextStyle(fontWeight: FontWeight.w700, color: ink),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            children: ['😭', '😞', '😐', '😊', '🙂']
                .map(
                  (m) => ChoiceChip(
                    label: Text(m, style: const TextStyle(fontSize: 20)),
                    selected: mood == m,
                    onSelected: (_) => setState(() => mood = m),
                    selectedColor: mint,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _photo,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(photo.isEmpty ? 'Add a photo' : 'Change photo'),
          ),
          if (photo.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Image.file(File(photo), height: 180, fit: BoxFit.cover),
              ),
            ),
          const SizedBox(height: 22),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(saving ? 'Saving...' : 'Save Entry'),
              style: FilledButton.styleFrom(
                backgroundColor: teal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
