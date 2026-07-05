import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'providers/app_provider.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const InodoroSmartApp());
}

class InodoroSmartApp extends StatelessWidget {
  const InodoroSmartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppProvider()..initialize(),
      child: MaterialApp(
        title: 'Inodoro Smart',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        builder: (context, child) {
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            child: DefaultTextStyle.merge(
              style: AppTheme.text(context).copyWith(
                decoration: TextDecoration.none,
                decorationColor: Colors.transparent,
              ),
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
        home: const HomeScreen(),
      ),
    );
  }
}
