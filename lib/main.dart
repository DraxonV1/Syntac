import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/core/app_identity.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppIdentity.initializeFromPlatform();
  runApp(const SyntacApp());
}
