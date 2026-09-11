import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/app_bootstrap.dart';
import 'theme/app_palette.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Warm, museum-grade tint for the system UI rather than the default accent.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: AppPalette.ground,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppPalette.ground,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Hive, identity (create/load), DB key, mesh start.
  await AppBootstrap.getInstance().init();

  runApp(const SpillTheTeaApp());
}