import 'package:flutter/material.dart';

import 'app.dart';
import 'data/connection_store.dart';
import 'data/knowledge_repository.dart';
import 'data/liferay_client.dart';
import 'data/scanner_settings.dart';
import 'data/session_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final connection = await ConnectionStore.load();
  final client = LiferayClient(
    connection: connection,
    // Signed-in user restored: the app reopens (even offline) without a new
    // sign-in while the refresh token is valid.
    session: await SessionStore.load(connection),
  );
  client.onSessionChanged = (s) => SessionStore.save(client.connection, s);
  final repository = KnowledgeRepository(client);
  await repository.loadCache(); // this user's offline copy, instant start
  await ScannerSettings.load();
  runApp(KnowledgeApp(repository: repository));
  repository.sync(); // then refresh from Liferay in the background
}
