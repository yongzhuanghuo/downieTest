import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite 数据库封装
///
/// 桌面端 (macOS/Windows/Linux) 使用 sqflite_common_ffi，
/// 移动端可自动切换至原生 sqflite 实现。
class AppDatabase {
  AppDatabase._();

  static const _dbName = 'downlo_pro.db';
  static const _dbVersion = 1;

  static Database? _instance;

  /// 获取数据库单例（桌面端 FFI 初始化）
  static Future<Database> get instance async {
    if (_instance != null) return _instance!;

    // 桌面平台：初始化 FFI 工厂
    try {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    } catch (_) {
      // 非桌面平台忽略
    }

    final dbPath = p.join(await getDatabasesPath(), _dbName);
    _instance = await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: _onCreate,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
    return _instance!;
  }

  /// 数据库结构
  static Future<void> _onCreate(Database db, int version) async {
    // 下载历史表（所有任务，含未完成）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS downloads (
        id TEXT PRIMARY KEY,
        url TEXT NOT NULL,
        title TEXT,
        thumb_url TEXT,
        format_id TEXT NOT NULL,
        format_label TEXT,
        height INTEGER DEFAULT 0,
        ext TEXT,
        file_size INTEGER DEFAULT 0,
        downloaded_bytes INTEGER DEFAULT 0,
        speed INTEGER DEFAULT 0,
        output_path TEXT,
        status INTEGER NOT NULL DEFAULT 0,
        error_message TEXT,
        retry_count INTEGER DEFAULT 0,
        source TEXT,
        created_at INTEGER NOT NULL,
        started_at INTEGER,
        completed_at INTEGER
      )
    ''');

    // 设置项索引（按创建时间倒序查历史）
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_downloads_created ON downloads(created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_downloads_status ON downloads(status)',
    );
  }

  /// 仅用于测试：关闭数据库
  static Future<void> closeForTest() async {
    await _instance?.close();
    _instance = null;
  }
}
