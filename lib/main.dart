import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb; // Library standar untuk cek Web/Mobile

import 'providers/theme_provider.dart';
import 'providers/cart_provider.dart';
import 'services/api_service.dart';
import 'views/login_page.dart';

void main() async {
  // 1. Pastikan binding siap
  WidgetsFlutterBinding.ensureInitialized();

  // Alamat server tersimpan (bisa diubah dari halaman login)
  await ApiService.loadServerAddress();

  // 2. Logika untuk membedakan Web dan Android
  if (kIsWeb) {
    print("Aplikasi berjalan di Browser (Web)");
    // Di sini biasanya renderer otomatis diatur oleh Flutter tools
  } else {
    print("Aplikasi berjalan di Mobile (Android/iOS)");
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: 'POS Babi Guling',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: const Color(0xFFEA7C69),
            scaffoldBackgroundColor: const Color(0xFFF9F9F9),
            fontFamily: 'Barlow',
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: const Color(0xFFEA7C69),
            scaffoldBackgroundColor: const Color(0xFF1F1D2B),
            cardColor: const Color(0xFF2D303E),
            dividerColor: const Color(0xFF393C49),
            fontFamily: 'Barlow',
          ),
          themeMode: themeProvider.isDarkMode
              ? ThemeMode.dark
              : ThemeMode.light,
          home: const LoginPage(),
        );
      },
    );
  }
}
