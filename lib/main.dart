import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/scanner_screen.dart';
import 'screens/linen_detail_screen.dart';
import 'screens/garment_detail_screen.dart';
import 'models/linen.dart';
import 'models/garment_tag.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthService(),
      child: const LoveMobiApp(),
    ),
  );
}

class LoveMobiApp extends StatelessWidget {
  const LoveMobiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Love Mobi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.grey,
        brightness: Brightness.light,
      ),
      home: const AuthGate(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/home': (_) => const HomeScreen(),
        '/scanner': (ctx) {
          final mode = ModalRoute.of(ctx)?.settings.arguments as String?;
          return ScannerScreen(mode: mode);
        },
        '/linen-detail': (ctx) {
          final linen = ModalRoute.of(ctx)!.settings.arguments as LinenItem;
          return LinenDetailScreen(linen: linen);
        },
        '/garment-detail': (ctx) {
          final tag = ModalRoute.of(ctx)!.settings.arguments as GarmentTag;
          return GarmentDetailScreen(tag: tag);
        },
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final auth = context.read<AuthService>();
    final loggedIn = await auth.tryAutoLogin();
    if (!mounted) return;

    if (loggedIn) {
      Navigator.of(context).pushReplacementNamed('/home');
    } else {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
