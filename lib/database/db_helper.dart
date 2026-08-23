import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class MessageModel {
  final int? id;
  final String role;
  final String content;
  final String timestamp;

  MessageModel({
    this.id,
    required this.role,
    required this.content,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'role': role,
      'content': content,
      'timestamp': timestamp,
    };
  }

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id'],
      role: map['role'],
      content: map['content'],
      timestamp: map['timestamp'],
    );
  }
}

class DBHelper {
  static final DBHelper instance = DBHelper._init();
  static Database? _database;

  DBHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('google_studio.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            timestamp TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<int> insertMessage(MessageModel message) async {
    final db = await instance.database;
    return await db.insert('messages', message.toMap());
  }

  Future<List<MessageModel>> getAllMessages() async {
    final db = await instance.database;
    final result = await db.query('messages', orderBy: 'id ASC');
    return result.map((json) => MessageModel.fromMap(json)).toList();
  }

  Future<void> clearChatHistory() async {
    final db = await instance.database;
    await db.delete('messages');
  }
}
