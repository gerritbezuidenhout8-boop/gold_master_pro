import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/journal_entry.dart';

/// Swappable journal persistence. Local-first by design: the default
/// stores everything on-device with no account. When Firebase is
/// connected (see docs/firebase_setup.md), a FirestoreJournalStore
/// implementing this same interface replaces [instance] after sign-in.
abstract class JournalStore {
  static JournalStore instance = LocalJournalStore();

  Future<List<JournalEntry>> load();
  Future<void> save(List<JournalEntry> entries);
}

/// On-device persistence via shared_preferences (JSON blob). Journal
/// volumes are small (hundreds of entries), so whole-list writes are
/// simpler and safe.
class LocalJournalStore implements JournalStore {
  static const String _key = 'gmp-journal-v1';

  @override
  Future<List<JournalEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    return [for (final m in list) JournalEntry.fromMap(m)];
  }

  @override
  Future<void> save(List<JournalEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode([for (final e in entries) e.toMap()]));
  }
}
