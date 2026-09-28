import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'nav/app_router.dart';
import 'nav/route_registry.dart';
import 'state/app_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  AppRouteRegistry.install();
  final services = await AppServices.boot();
  runApp(LoveLaundryApp(services: services));
}

class LoveLaundryApp extends StatelessWidget {
  const LoveLaundryApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: services.theme,
      builder: (context, _) {
        return MaterialApp(
          title: 'Love Laundry Ops',
          debugShowCheckedModeBanner: false,
          theme: services.theme.materialTheme,
          home: AppRouter(services: services),
        );
      },
    );
  }
}
