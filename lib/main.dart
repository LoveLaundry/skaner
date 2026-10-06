import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'nav/app_router.dart';
import 'nav/route_registry.dart';
import 'state/app_services.dart';
import 'ui/kit/toast.dart';

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
          builder: (context, child) => ToastHost(child: child!),
          home: AppRouter(services: services),
        );
      },
    );
  }
}

// PROBE-TRACKED-EDIT 1790597481
