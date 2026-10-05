import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'providers/theme_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/nav_provider.dart';
import 'services/api_service.dart';
import 'services/app_settings.dart';
import 'views/login_page.dart';

void main() async {
  // 1. Pastikan binding siap
  WidgetsFlutterBinding.ensureInitialized();

  // Alamat server & isi struk tersimpan (bisa diubah dari halaman login / admin)
  await ApiService.loadServerAddress();
  await AppSettings().loadCached();
  // Nama hari & bulan dalam bahasa Indonesia
  await initializeDateFormatting('id');
  Intl.defaultLocale = 'id';

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => NavProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

/// Tema global dari token warna, supaya tombol, input, dialog, dan snackbar
/// di semua halaman tampil seragam.
ThemeData buildAppTheme(ThemeProvider t) {
  final Brightness brightness =
      t.isDarkMode ? Brightness.dark : Brightness.light;
  final RoundedRectangleBorder radius10 =
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
  // fontFamily wajib ditulis: gaya tombol tidak mewarisi font dari tema
  const TextStyle buttonText = TextStyle(
      fontFamily: 'PlusJakartaSans', fontWeight: FontWeight.w600, fontSize: 14);

  return ThemeData(
    brightness: brightness,
    fontFamily: 'PlusJakartaSans',
    scaffoldBackgroundColor: t.backgroundColor,
    canvasColor: t.backgroundColor,
    cardColor: t.cardColor,
    dividerColor: t.borderColor,
    primaryColor: t.primaryColor,
    colorScheme: ColorScheme.fromSeed(
      seedColor: t.primaryColor,
      brightness: brightness,
      primary: t.primaryColor,
      onPrimary: Colors.white,
      surface: t.cardColor,
      onSurface: t.textColor,
      error: t.dangerColor,
    ),
    textTheme: ThemeData(brightness: brightness).textTheme.apply(
          fontFamily: 'PlusJakartaSans',
          bodyColor: t.textColor,
          displayColor: t.textColor,
        ),
    iconTheme: IconThemeData(color: t.secondaryTextColor),
    appBarTheme: AppBarTheme(
      backgroundColor: t.backgroundColor,
      foregroundColor: t.textColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: 'PlusJakartaSans',
        color: t.textColor,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: t.primaryColor,
        foregroundColor: Colors.white,
        disabledBackgroundColor: t.subtleColor,
        disabledForegroundColor: t.faintTextColor,
        elevation: 0,
        shape: radius10,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.textColor,
        side: BorderSide(color: t.fieldBorderColor),
        shape: radius10,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.primaryColor,
        textStyle: buttonText,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.cardColor,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      hintStyle: TextStyle(color: t.faintTextColor),
      labelStyle: TextStyle(color: t.secondaryTextColor),
      floatingLabelStyle: TextStyle(color: t.primaryColor),
      helperStyle: TextStyle(color: t.secondaryTextColor, fontSize: 12),
      prefixIconColor: t.secondaryTextColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: t.fieldBorderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: t.fieldBorderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: t.primaryColor, width: 1.6),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.cardColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: TextStyle(
        fontFamily: 'PlusJakartaSans',
        color: t.textColor,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: TextStyle(
        fontFamily: 'PlusJakartaSans',
        color: t.secondaryTextColor,
        fontSize: 14,
        height: 1.45,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.cardColor,
      surfaceTintColor: Colors.transparent,
      showDragHandle: false,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.cardColor,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: t.inkColor,
      contentTextStyle: TextStyle(
        fontFamily: 'PlusJakartaSans',
        color: t.onInkColor,
        fontSize: 14,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? t.primaryColor : null),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: t.primaryColor),
    dividerTheme: DividerThemeData(color: t.borderColor, space: 1),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: themeProvider.isDarkMode
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: MaterialApp(
            title: 'Kasir Men Gede',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(themeProvider),
            home: const LoginPage(),
          ),
        );
      },
    );
  }
}
