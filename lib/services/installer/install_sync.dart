import 'package:flutter/foundation.dart';
import 'store_update_service.dart';

class InstallSync {
  InstallSync._();

  static final active = <String, ValueNotifier<bool>>{};
  static final paused = <String, ValueNotifier<bool>>{};
  static final progress = <String, ValueNotifier<double>>{};
  static final preparing = <String, ValueNotifier<bool>>{};
  static final isChecking = <String, ValueNotifier<bool>>{};
  static final cachedCheck = <String, StoreUpdateCheck?>{};

  static final checkVersion = ValueNotifier<int>(0);

  static void register(String pkg) {
    active.putIfAbsent(pkg, () => ValueNotifier(false));
    paused.putIfAbsent(pkg, () => ValueNotifier(false));
    progress.putIfAbsent(pkg, () => ValueNotifier(0.0));
    preparing.putIfAbsent(pkg, () => ValueNotifier(false));
    isChecking.putIfAbsent(pkg, () => ValueNotifier(true));
  }

  static void bumpCheck() {
    checkVersion.value++;
  }
}
