import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photoe_zi/core/constants/studio_theme.dart';
import 'package:photoe_zi/features/tether_view/presentation/tether_workspace_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'tether_workspace',
        builder: (context, state) => const TetherWorkspaceScreen(),
      ),
    ],
  );
});

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 150 << 20; // 150 MB max RAM cache
  PaintingBinding.instance.imageCache.maximumSize = 200; // max 200 decoded image frames
  runApp(
    const ProviderScope(
      child: PhotoEZiApp(),
    ),
  );
}

class PhotoEZiApp extends ConsumerWidget {
  const PhotoEZiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'PhotoE-Zi — Pro Tether & Film Sim',
      debugShowCheckedModeBanner: false,
      theme: StudioTheme.darkTheme,
      darkTheme: StudioTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
