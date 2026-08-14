import 'package:sqflite/sqflite.dart';

import '../storage/app_database.dart';
import '../../data/models/download_task.dart';

/// 下载任务 DAO
///
/// 负责 CRUD：增删改查下载任务。数据库持久化后，应用重启
/// 可以恢复未完成的任务（断点续传）和展示历史记录。
class DownloadsDao {
  DownloadsDao._();
  static final instance = DownloadsDao._();

  Future<Database> get _db => AppDatabase.instance;

  // ==================== C / U ====================

  /// 插入或替换（主键冲突=覆盖）
  Future<void> upsert(DownloadTask task) async {
    final db = await _db;
    await db.insert(
      'downloads',
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 批量 upsert
  Future<void> upsertAll(List<DownloadTask> tasks) async {
    final db = await _db;
    final batch = db.batch();
    for (final t in tasks) {
      batch.insert(
        'downloads',
        t.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// 仅更新状态/进度/错误等运行时字段（非空覆盖）
  Future<void> updateProgress(DownloadTask task) async {
    final db = await _db;
    await db.update(
      'downloads',
      {
        'status': task.status.index,
        'file_size': task.fileSize,
        'downloaded_bytes': task.downloadedBytes,
        'speed': task.speed,
        'output_path': task.outputPath,
        'error_message': task.error,
        'retry_count': task.retryCount,
        'started_at': task.startedAt?.millisecondsSinceEpoch,
        'completed_at': task.completedAt?.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  // ==================== R ====================

  /// 查询单个任务
  Future<DownloadTask?> findById(String id) async {
    final db = await _db;
    final rows = await db.query('downloads', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return DownloadTask.fromMap(rows.first);
  }

  /// 所有任务（按创建时间倒序，新→旧）
  Future<List<DownloadTask>> findAll({int? limit}) async {
    final db = await _db;
    final rows = await db.query(
      'downloads',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(DownloadTask.fromMap).toList();
  }

  /// 未完成任务（pending/downloading/merging）——应用重启后可恢复
  Future<List<DownloadTask>> findRunning() async {
    final db = await _db;
    final rows = await db.query(
      'downloads',
      where: 'status IN (?, ?, ?)',
      whereArgs: [
        DownloadStatus.pending.index,
        DownloadStatus.downloading.index,
        DownloadStatus.merging.index,
      ],
      orderBy: 'created_at ASC',
    );
    return rows.map(DownloadTask.fromMap).toList();
  }

  /// 已完成任务（下载页"已结束"）
  Future<List<DownloadTask>> findFinished({int limit = 200}) async {
    final db = await _db;
    final rows = await db.query(
      'downloads',
      where: 'status IN (?, ?, ?)',
      whereArgs: [
        DownloadStatus.completed.index,
        DownloadStatus.failed.index,
        DownloadStatus.cancelled.index,
      ],
      orderBy: 'completed_at DESC, created_at DESC',
      limit: limit,
    );
    return rows.map(DownloadTask.fromMap).toList();
  }

  /// 仅成功的历史记录（历史页）
  Future<List<DownloadTask>> findHistory({int limit = 200}) async {
    final db = await _db;
    final rows = await db.query(
      'downloads',
      where: 'status = ?',
      whereArgs: [DownloadStatus.completed.index],
      orderBy: 'completed_at DESC',
      limit: limit,
    );
    return rows.map(DownloadTask.fromMap).toList();
  }

  /// 指定状态计数
  Future<int> countByStatus(DownloadStatus status) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM downloads WHERE status = ?',
      [status.index],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  // ==================== D ====================

  /// 删除单个任务
  Future<void> deleteById(String id) async {
    final db = await _db;
    await db.delete('downloads', where: 'id = ?', whereArgs: [id]);
  }

  /// 清空已结束任务（downloads 页工具栏按钮）
  Future<int> deleteFinished() async {
    final db = await _db;
    return db.delete(
      'downloads',
      where: 'status IN (?, ?, ?)',
      whereArgs: [
        DownloadStatus.completed.index,
        DownloadStatus.failed.index,
        DownloadStatus.cancelled.index,
      ],
    );
  }
}
