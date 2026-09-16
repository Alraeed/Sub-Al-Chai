import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/app_strings.dart';
import 'l10n/locale_controller.dart';
import 'mesh/mesh_service.dart';
import 'screens/home/home_shell.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'services/app_bootstrap.dart';
import 'services/messaging_service.dart';
import 'theme/app_palette.dart';
import 'theme/app_theme.dart';
import 'widgets/tea_wordmark.dart';

class SpillTheTeaApp extends StatelessWidget {
  const SpillTheTeaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (BuildContext context) => AppBootstrap.getInstance(),
        ),
        ChangeNotifierProvider(
          create: (BuildContext context) => LocaleController.getInstance(),
        ),
        ChangeNotifierProvider(
          create: (BuildContext context) => MeshService.getInstance(),
        ),
        ChangeNotifierProvider(
          create: (BuildContext context) => MessagingService.getInstance(),
        ),
      ],
      child: Consumer<LocaleController>(
        builder: (BuildContext context, LocaleController locale, Widget? _) {
          return MaterialApp(
            title: AppStrings.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark,
            // Arabic-first; the language toggle flips this (and the
            // text direction follows the locale automatically).
            locale: locale.lang.locale,
            supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (BuildContext context, Widget? child) {
              // Ambient lapis vignette behind every route.
              return DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: AppPalette.ambientGradient,
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const AppGate(),
          );
        },
      ),
    );
  }
}

/// Decides between onboarding (first launch) and the main shell.
class AppGate extends StatelessWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context) {
    final AppBootstrap bootstrap = context.watch<AppBootstrap>();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: bootstrap.ready
          ? (bootstrap.hasIdentity
              ? const HomeShell(key: ValueKey<String>('home'))
              : const OnboardingScreen(key: ValueKey<String>('onboarding')))
          : const _SplashLikeLoad(),
    );
  }
}

class _SplashLikeLoad extends StatelessWidget {
  const _SplashLikeLoad();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // The same lockup the onboarding screen opens with: cup mark,
            // Arabic name, Latin line.
            TeaWordmark(markSize: 92),
            SizedBox(height: 30),
            CircularProgressIndicator(color: AppPalette.brass),
          ],
        ),
      ),
    );
  }
}
