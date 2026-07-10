import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/db/database.dart';
import 'services/background.dart';
import 'state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDb();
  // Background polling replaces the Monobank webhook (see background.dart).
  await registerBackgroundPolling();
  runApp(ProviderScope(
    overrides: [dbProvider.overrideWithValue(db)],
    child: const BudgetApp(),
  ));
}
