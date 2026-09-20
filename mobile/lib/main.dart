import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'core/services/update_service.dart';
import 'core/theme/aurora_theme.dart';
import 'state/auth_state.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/shell_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UpdateService.initVersion();

  // Safeguard MediaKit initialization to prevent unhandled native framework errors from blocking app launch
  try {
    MediaKit.ensureInitialized();
  } catch (e, st) {
    debugPrint('[Main] MediaKit initialization skipped or failed: $e\n$st');
  }

  // Global Flutter error handler
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[FlutterError] ${details.exceptionAsString()}');
  };

  runApp(const ProviderScope(child: MementoApp()));
}

class MementoApp extends ConsumerWidget {
  const MementoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    return MaterialApp(
      title: 'Memento',
      debugShowCheckedModeBanner: false,
      theme: AuroraTheme.darkTheme,
      home: authState.isLoading
          ? const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: AuroraColors.accent),
              ),
            )
          : authState.isAuthenticated
              ? const ShellScreen()
              : const LoginScreen(),
    );
  }
}
