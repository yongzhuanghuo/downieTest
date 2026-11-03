import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/license/license_client.dart';
import 'license_provider.dart';

/// 设备管理窗口：查看已绑定设备并解绑旧设备。
class DeviceDialog extends ConsumerStatefulWidget {
  const DeviceDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const DeviceDialog(),
    );
  }

  @override
  ConsumerState<DeviceDialog> createState() => _DeviceDialogState();
}

class _DeviceDialogState extends ConsumerState<DeviceDialog> {
  List<DeviceInfo>? _devices;
  bool _loading = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final devices =
        await ref.read(licenseNotifierProvider.notifier).listDevices();
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _loading = false;
      if (devices == null) _message = '无法连接服务器，请检查网络后重试';
    });
  }

  Future<void> _unbind(DeviceInfo device) async {
    final fp = device.deviceFp;
    if (fp == null || fp.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解绑设备'),
        content: Text('确定解绑「${device.deviceName ?? _short(fp)}」吗？'
            '该设备会释放一个授权名额。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('解绑'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final (success, message) =
        await ref.read(licenseNotifierProvider.notifier).unbindDevice(fp);
    if (!mounted) return;
    setState(() => _message = message);
    if (success) await _load();
  }

  String _short(String fp) => fp.length <= 12
      ? fp
      : '${fp.substring(0, 6)}***${fp.substring(fp.length - 6)}';

  String _date(String? value) {
    if (value == null || value.isEmpty) return '';
    return value.length >= 10 ? value.substring(0, 10) : value;
  }

  @override
  Widget build(BuildContext context) {
    final license = ref.watch(activatedLicenseProvider);
    final maxDevices = license?.payload.maxDevices ?? 4;
    return AlertDialog(
      title: Text('设备管理（${_devices?.length ?? 0}/$maxDevices）'),
      content: SizedBox(
        width: 400,
        height: 280,
        child: _loading
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : _devices == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_message ?? '设备列表加载失败'),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _load,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _devices!.isEmpty
                            ? const Center(child: Text('暂无绑定设备'))
                            : ListView.separated(
                                itemCount: _devices!.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final device = _devices![index];
                                  final fp = device.deviceFp ?? '';
                                  final current = device.isCurrent == true;
                                  return ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      current
                                          ? Icons.laptop_mac
                                          : Icons.devices_other,
                                      size: 18,
                                    ),
                                    title: Text(
                                      device.deviceName?.isNotEmpty == true
                                          ? device.deviceName!
                                          : _short(fp),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      [
                                        if (fp.isNotEmpty) _short(fp),
                                        if (current) '当前设备',
                                        if (_date(device.lastSeen).isNotEmpty)
                                          '最近 ${_date(device.lastSeen)}',
                                      ].join(' · '),
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                    trailing: current || fp.isEmpty
                                        ? null
                                        : TextButton(
                                            onPressed: () => _unbind(device),
                                            child: const Text('解绑'),
                                          ),
                                  );
                                },
                              ),
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _message!,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : _load,
          child: const Text('刷新'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
