import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/session.dart';
import '../models/translation_record.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() {
    return _instance;
  }

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    // Initialize FFI for Windows/Linux
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'ai_translator.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDb,
      onConfigure: (db) async {
        // Enable foreign keys
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _createDb(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE records(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        source_text TEXT NOT NULL,
        translated_text TEXT NOT NULL,
        source_lang TEXT NOT NULL,
        input_audio_path TEXT,
        output_audio_path TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE
      )
    ''');
  }

  // --- Session Operations ---

  Future<int> createSession(String title) async {
    final db = await database;
    final session = Session(
      title: title,
      createdAt: DateTime.now(),
    );
    return await db.insert('sessions', session.toMap());
  }

  Future<List<Session>> getSessions() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'sessions', 
      orderBy: 'created_at DESC'
    );
    return List.generate(maps.length, (i) => Session.fromMap(maps[i]));
  }

  Future<void> deleteSession(int id) async {
    final db = await database;
    // Cascade delete is enabled, so records will be deleted automatically from DB.
    // However, we need to handle file deletion in the Provider/Service layer before calling this
    // or by querying records first.
    await db.delete(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- Record Operations ---

  Future<int> insertRecord(TranslationRecord record) async {
    final db = await database;
    return await db.insert('records', record.toMap());
  }

  Future<List<TranslationRecord>> getRecords(int sessionId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'records',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at ASC', // Order by input sequence
    );
    return List.generate(maps.length, (i) => TranslationRecord.fromMap(maps[i]));
  }

  Future<void> deleteRecord(int id) async {
    final db = await database;
    await db.delete(
      'records',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  Future<void> deleteRecords(List<int> ids) async {
    final db = await database;
    await db.delete(
      'records',
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }

  Future<TranslationRecord?> getRecord(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'records',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return TranslationRecord.fromMap(maps.first);
    }
    return null;
  }
}
