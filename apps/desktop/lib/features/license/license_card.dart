import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'license_provider.dart';

/// ===================================================================
/// PRO 升级对比对话框（统一入口）
/// 在首页「升级 PRO」、设置页「激活」、清晰度超限提示等多处调用
/// ===================================================================
Future<void> showProUpgradeDialog(BuildContext context, WidgetRef ref) async {
  final notifier = ref.read(licenseNotifierProvider.notifier);
  await showDialog<void>(
    context: context,
    builder: (ctx) => _UpgradeDialog(notifier: notifier),
  );
}

/// PRO 升级对话框（StatefulWidget，controller 生命周期由框架管理）
class _UpgradeDialog extends StatefulWidget {
  final LicenseNotifier notifier;
  const _UpgradeDialog({required this.notifier});

  @override
  State<_UpgradeDialog> createState() => _UpgradeDialogState();
}

class _UpgradeDialogState extends State<_UpgradeDialog> {
  final _ctrl = TextEditingController();
  bool _obscure = true;
  bool _activating = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    setState(() => _activating = true);
    final (ok, msg) = await widget.notifier.activate(_ctrl.text);
    if (!mounted) return;
    setState(() => _activating = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: ok
            ? Colors.amber.shade700
            : Theme.of(context).colorScheme.error,
      ),
    );
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.workspace_premium, color: Colors.amber),
          const SizedBox(width: 8),
          const Text('升级 PRO 永久版'),
          const Spacer(),
          Text(
            '¥30 买断',
            style: TextStyle(
              color: Colors.amber.shade700,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ==================== 功能对比表 ====================
              _buildComparisonTable(theme),
              const SizedBox(height: 20),
              // ==================== 激活码输入 ====================
              Text(
                '输入激活码',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ctrl,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: '激活码',
                  hintText: 'XXXXX-XXXXX-XXXXX-XXXXX',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.vpn_key, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.payment, size: 14,
                      color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '支持微信 / 支付宝 ¥30 买断，付款后获取激活码',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          icon: _activating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.bolt, size: 18),
          label: Text(_activating ? '激活中...' : '立即激活'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.amber.shade700,
          ),
          onPressed: _activating ? null : _activate,
        ),
      ],
    );
  }
}

/// 功能对比表
Widget _buildComparisonTable(ThemeData theme) {
  const rows = <_CompareRow>[
    _CompareRow(icon: Icons.hd, label: '最高画质', free: '1080P', pro: '4K', proHighlight: true),
    _CompareRow(icon: Icons.download, label: '每日下载', free: '2 个', pro: '不限', proHighlight: true),
    _CompareRow(icon: Icons.devices, label: '设备绑定', free: '1 台', pro: '4 台', proHighlight: true),
    _CompareRow(icon: Icons.queue, label: '并发下载', free: '1 个', pro: '3 个', proHighlight: true),
    _CompareRow(icon: Icons.subtitles, label: '字幕下载', free: '✓', pro: '✓'),
    _CompareRow(icon: Icons.video_settings, label: '格式选择', free: '✓', pro: '✓'),
    _CompareRow(icon: Icons.headset_mic, label: '优先客服', free: '—', pro: '✓', proHighlight: true),
    _CompareRow(icon: Icons.update, label: '后续更新', free: '基础', pro: '全部', proHighlight: true),
  ];

  return Container(
    decoration: BoxDecoration(
      border: Border.all(color: theme.dividerColor),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      children: [
        // 表头
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(9),
              topRight: Radius.circular(9),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 28),
              const Expanded(flex: 2, child: Text('功能')),
              Expanded(
                flex: 2,
                child: Center(
                  child: Text('免费版',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
                ),
              ),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text('PRO 永久版',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade800,
                        )),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 行
        ...rows.asMap().entries.map((entry) {
          final i = entry.key;
          final r = entry.value;
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: i.isOdd
                  ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
                  : null,
            ),
            child: Row(
              children: [
                SizedBox(width: 28, child: Icon(r.icon, size: 16)),
                const SizedBox(width: 4),
                Expanded(flex: 2, child: Text(r.label, style: const TextStyle(fontSize: 13))),
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Text(r.free,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Text(
                      r.pro,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: r.proHighlight ? FontWeight.bold : null,
                        color: r.proHighlight ? Colors.amber.shade800 : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        // 价格行
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.06),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(9),
              bottomRight: Radius.circular(9),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 28),
              const Expanded(flex: 2, child: Text('价格')),
              const Expanded(
                flex: 2,
                child: Center(child: Text('免费', style: TextStyle(fontSize: 13))),
              ),
              Expanded(
                flex: 2,
                child: Center(
                  child: Text('¥30 买断',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade800,
                      )),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CompareRow {
  final IconData icon;
  final String label;
  final String free;
  final String pro;
  final bool proHighlight;

  const _CompareRow({
    required this.icon,
    required this.label,
    required this.free,
    required this.pro,
    this.proHighlight = false,
  });
}

/// ===================================================================
/// 会员信息 + 激活码输入卡片（用在设置页"关于"区域）
/// ===================================================================
class LicenseCard extends ConsumerStatefulWidget {
  const LicenseCard({super.key});

  @override
  ConsumerState<LicenseCard> createState() => _LicenseCardState();
}

class _LicenseCardState extends ConsumerState<LicenseCard> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final license = ref.watch(activatedLicenseProvider);
    final isPro = license?.isPro ?? false;

    return Column(
      children: [
        ListTile(
          leading: Icon(
            isPro ? Icons.workspace_premium : Icons.card_membership_outlined,
            color: isPro ? Colors.amber : theme.colorScheme.primary,
          ),
          title: Row(
            children: [
              const Text('许可证'),
              const SizedBox(width: 8),
              _badge(
                isPro ? 'PRO 永久版' : '免费版',
                isPro ? Colors.amber : theme.colorScheme.primary,
              ),
            ],
          ),
          subtitle: Text(
            isPro
                ? '已激活 · 支持 4K · 不限下载 · 最多 ${license?.maxDevices ?? 4} 台设备'
                : '每日 5 次下载 · 最高 1080P · 1 台设备',
          ),
          onTap: () => showProUpgradeDialog(context, ref),
          trailing: Text(
            isPro ? '管理' : '激活',
            style: TextStyle(color: theme.colorScheme.primary),
          ),
        ),
        if (license != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.vpn_key, size: 16),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '激活码: ${license.code}',
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.devices, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '已绑定 ${license.boundDevices.length}/${license.maxDevices} 台设备',
                      style: theme.textTheme.bodySmall,
                    ),
                    const Spacer(),
                    // 同步设备列表
                    InkWell(
                      onTap: () async {
                        final (ok, msg) = await ref
                            .read(licenseNotifierProvider.notifier)
                            .refreshDeviceList();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(msg),
                              backgroundColor: ok
                                  ? Colors.amber.shade700
                                  : theme.colorScheme.error,
                            ),
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sync, size: 14,
                                color: theme.colorScheme.primary),
                            const SizedBox(width: 2),
                            Text('同步',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.primary,
                                )),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...license.boundDevices.asMap().entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(left: 22, top: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${e.key + 1}. ${_fpShort(e.value)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            // 解绑按钮
                            InkWell(
                              onTap: () => _confirmUnbind(context, ref, e.value, theme),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Icon(Icons.link_off, size: 16,
                                    color: theme.colorScheme.error.withValues(alpha: 0.7)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _fpShort(String fp) {
    if (fp.length <= 12) return fp;
    return '${fp.substring(0, 6)}***${fp.substring(fp.length - 6)}';
  }

  /// 解绑确认对话框
  Future<void> _confirmUnbind(
    BuildContext context,
    WidgetRef ref,
    String deviceFp,
    ThemeData theme,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解绑设备'),
        content: Text(
          '确定要解绑设备 ${_fpShort(deviceFp)} 吗？\n\n'
          '解绑后该设备将无法使用 PRO 功能。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('解绑'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final (ok, msg) =
        await ref.read(licenseNotifierProvider.notifier).unbindDevice(deviceFp);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor:
              ok ? Colors.amber.shade700 : theme.colorScheme.error,
        ),
      );
    }
  }
}
