import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/ffmpeg/ffmpeg_runner.dart';
import '../../data/models/watermark_segment.dart';

/// 去水印工具页
///
/// 流程：选择视频 → 抽帧预览 → 时间轴 + 多段框选水印 → FFmpeg delogo 按时间段抹除
class WatermarkToolPage extends StatefulWidget {
  const WatermarkToolPage({super.key});

  @override
  State<WatermarkToolPage> createState() => _WatermarkToolPageState();
}

class _WatermarkToolPageState extends State<WatermarkToolPage> {
  String? _videoPath;
  double _duration = 0;
  int _videoWidth = 0;
  int _videoHeight = 0;
  double _currentTime = 0;
  String? _framePath;
  final List<WatermarkSegment> _segments = [];
  Rect? _draftBox;
  Offset? _dragStart;
  bool _extractingFrame = false;
  bool _processing = false;
  String? _resultPath;
  String? _lastError;

  @override
  void dispose() {
    _clearFrame();
    super.dispose();
  }

  Future<void> _clearFrame() async {
    final f = _framePath;
    if (f != null) {
      try {
        await File(f).delete();
      } catch (_) {}
    }
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      dialogTitle: '选择要去水印的视频',
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    await _clearFrame();
    if (!mounted) return;
    setState(() {
      _videoPath = path;
      _duration = 0;
      _currentTime = 0;
      _framePath = null;
      _segments.clear();
      _draftBox = null;
      _dragStart = null;
      _resultPath = null;
      _lastError = null;
    });
    await _loadVideo(path);
  }

  Future<void> _loadVideo(String path) async {
    try {
      final duration = await FFmpegRunner.getMediaDuration(path);
      final dims = await FFmpegRunner.getVideoDimensions(path);
      if (!mounted) return;
      setState(() {
        _duration = duration;
        _videoWidth = dims.$1;
        _videoHeight = dims.$2;
      });
      await _extractFrame(0);
    } catch (e) {
      debugPrint('[去水印] 读取视频失败: $e');
      if (mounted) {
        setState(() => _lastError = '读取视频失败: $e');
        _showMsg('读取视频失败: $e');
      }
    }
  }

  Future<void> _extractFrame(double t) async {
    final path = _videoPath;
    if (path == null) return;
    setState(() => _extractingFrame = true);
    try {
      final dir = await getTemporaryDirectory();
      // path_provider 返回的临时目录可能不存在（macOS 会清理 Caches），
      // ffmpeg 不会自建父目录，这里先确保目录存在，否则抽帧报“Could not open file”。
      await dir.create(recursive: true);
      final out = p.join(
        dir.path,
        'watermark_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await FFmpegRunner.extractFrame(
        inputPath: path,
        timestamp: t,
        outputPath: out,
      );
      await _clearFrame();
      if (!mounted) return;
      setState(() {
        _framePath = out;
        _currentTime = t;
        _extractingFrame = false;
        _lastError = null;
      });
    } catch (e) {
      debugPrint('[去水印] 抽帧失败: $e');
      if (mounted) {
        setState(() {
          _extractingFrame = false;
          _lastError = '抽帧失败: $e';
        });
        _showMsg('抽帧失败: $e');
      }
    }
  }

  /// 拖框结束 → 用当前时间 + 归一化框坐标生成一个水印段
  void _commitSegment(Size size) {
    final b = _draftBox;
    if (b == null || size.width <= 0 || size.height <= 0) return;
    final seg = WatermarkSegment(
      time: _currentTime,
      x: (b.left / size.width).clamp(0.0, 1.0),
      y: (b.top / size.height).clamp(0.0, 1.0),
      w: (b.width / size.width).clamp(0.0, 1.0),
      h: (b.height / size.height).clamp(0.0, 1.0),
    );
    setState(() {
      _segments.add(seg);
      _segments.sort((a, b) => a.time.compareTo(b.time));
      _draftBox = null;
      _dragStart = null;
    });
  }

  Future<void> _startRemove() async {
    final path = _videoPath;
    if (path == null || _segments.isEmpty || _duration <= 0) return;
    setState(() {
      _processing = true;
      _resultPath = null;
    });
    try {
      final dir = p.dirname(path);
      final base = p.basenameWithoutExtension(path);
      final ext = p.extension(path);
      final out = p.join(dir, '${base}_去水印$ext');
      await FFmpegRunner.removeWatermark(
        inputPath: path,
        outputPath: out,
        segments: _segments,
        duration: _duration,
        videoWidth: _videoWidth,
        videoHeight: _videoHeight,
      );
      if (!mounted) return;
      setState(() {
        _processing = false;
        _resultPath = out;
        _lastError = null;
      });
      _showMsg('去水印完成：$out');
    } catch (e) {
      debugPrint('[去水印] 去水印失败: $e');
      if (!mounted) return;
      setState(() {
        _processing = false;
        _lastError = '去水印失败: $e';
      });
      _showMsg('去水印失败: $e');
    }
  }

  void _showMsg(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('去水印', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text(
                        '导入本地视频，框选水印位置，自动抹除（支持多段时间轴）',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _pickVideo,
                  icon: const Icon(Icons.video_library),
                  label: Text(_videoPath == null ? '选择视频' : '换一个视频'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_videoPath == null)
              _buildEmpty(theme)
            else ...[
              _buildPreview(theme),
              if (_lastError != null) ...[
                const SizedBox(height: 12),
                _buildError(theme),
              ],
              const SizedBox(height: 16),
              _buildTimeline(theme),
              const SizedBox(height: 16),
              _buildSegmentList(theme),
              const SizedBox(height: 16),
              _buildActionButton(theme),
              if (_resultPath != null) _buildResult(theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Container(
      height: 320,
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.branding_watermark_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              '点击「选择视频」开始',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '处理出错',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            _lastError!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: _framePath == null || _videoWidth == 0
          ? const SizedBox(
              height: 300,
              child: Center(child: CircularProgressIndicator()),
            )
          : AspectRatio(
              aspectRatio: _videoWidth / _videoHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                  return GestureDetector(
                    onPanStart: (d) => setState(() {
                      _dragStart = d.localPosition;
                      _draftBox = Rect.fromPoints(
                        d.localPosition,
                        d.localPosition,
                      );
                    }),
                    onPanUpdate: (d) => setState(() {
                      if (_dragStart != null) {
                        _draftBox = Rect.fromPoints(_dragStart!, d.localPosition);
                      }
                    }),
                    onPanEnd: (_) => _commitSegment(size),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(_framePath!), fit: BoxFit.fill),
                        CustomPaint(
                          painter: _BoxPainter(
                            segments: _segments,
                            draftBox: _draftBox,
                          ),
                        ),
                        if (_extractingFrame)
                          const ColoredBox(
                            color: Colors.black45,
                            child: Center(child: CircularProgressIndicator()),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildTimeline(ThemeData theme) {
    final max = _duration > 0 ? _duration : 1.0;
    final m = (_currentTime ~/ 60).toInt();
    final s = (_currentTime % 60).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('时间轴', style: theme.textTheme.titleSmall),
            const Spacer(),
            Text(
              '$m:${s.toString().padLeft(2, '0')} / '
              '${(_duration ~/ 60).toInt()}:${(_duration % 60).round().toString().padLeft(2, '0')}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        Slider(
          value: _currentTime.clamp(0.0, max),
          max: max,
          onChanged: (v) => setState(() => _currentTime = v),
          onChangeEnd: (v) => _extractFrame(v),
        ),
        Text(
          '拖动时间轴到水印出现的位置，在画面上按住鼠标拖框框住水印；'
          '水印换位置就再拖到对应时间重新框一次',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentList(ThemeData theme) {
    if (_segments.isEmpty) {
      return Text(
        '还没框选水印（拖框后这里会列出各段水印位置）',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('已框选的水印段', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        ..._segments.asMap().entries.map((e) {
          final i = e.key;
          final seg = e.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.crop_square, size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${seg.timeLabel} 起 · ${seg.posLabel}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: '删除这一段',
                  onPressed: () => setState(() => _segments.removeAt(i)),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildActionButton(ThemeData theme) {
    return FilledButton.icon(
      onPressed: _processing ? null : _startRemove,
      icon: _processing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.auto_fix_high),
      label: Text(_processing ? '去水印处理中...' : '开始去水印'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }

  Widget _buildResult(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '已导出：$_resultPath',
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// 在预览图上绘制水印框（已确认的段 + 正在拖的框）
class _BoxPainter extends CustomPainter {
  final List<WatermarkSegment> segments;
  final Rect? draftBox;

  const _BoxPainter({required this.segments, this.draftBox});

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = Colors.red.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final seg in segments) {
      final r = Rect.fromLTWH(
        seg.x * size.width,
        seg.y * size.height,
        seg.w * size.width,
        seg.h * size.height,
      );
      canvas.drawRect(r, fill);
      canvas.drawRect(r, border);
    }

    final d = draftBox;
    if (d != null) {
      canvas.drawRect(d, fill);
      canvas.drawRect(d, border);
    }
  }

  @override
  bool shouldRepaint(covariant _BoxPainter oldDelegate) => true;
}
