import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/settings/settings_provider.dart';
import 'shared/branding/app_brand.dart';
import 'shared/routes/app_routes.dart';
import 'shared/theme/app_theme.dart';
import 'shared/widgets/app_menu_bar.dart';

/// 应用根 Widget
class DownloApp extends ConsumerWidget {
  const DownloApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return AppMenuBar(
      child: MaterialApp.router(
        title: AppBrand.name,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        routerConfig: router,
      ),
    );
  }
}
