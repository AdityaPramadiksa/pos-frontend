import 'package:flutter/widgets.dart';

/// Lebar layar di bawah ini dianggap HP: layout satu kolom + navigasi bawah.
/// Tablet (yang dipakai kasir) tetap memakai layout lebar dengan sidebar.
const double kMobileBreakpoint = 700;

bool isMobile(BuildContext context) =>
    MediaQuery.sizeOf(context).width < kMobileBreakpoint;

/// Padding halaman: lebih rapat di HP supaya konten tidak terjepit.
double pagePadding(BuildContext context) => isMobile(context) ? 16 : 32;
