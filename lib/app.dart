import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'data/content_types.dart';
import 'data/knowledge_repository.dart';
import 'screens/entry_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/type_screen.dart';

/// Gives every widget access to the repository and rebuilds dependents when
/// it changes.
class RepositoryScope extends InheritedNotifier<KnowledgeRepository> {
  const RepositoryScope({
    super.key,
    required KnowledgeRepository repository,
    required super.child,
  }) : super(notifier: repository);

  /// With [listen] false (e.g. in initState), the caller is not rebuilt on
  /// repository changes.
  static KnowledgeRepository of(BuildContext context, {bool listen = true}) =>
      (listen
              ? context.dependOnInheritedWidgetOfExactType<RepositoryScope>()
              : context.getInheritedWidgetOfExactType<RepositoryScope>())!
          .notifier!;
}

/// The QR scanner needs a mobile camera (Android / iOS app).
bool get scannerAvailable =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Route helpers: URLs are shareable and work after a reload, e.g.
/// `/#/type/nmgfaqs`, `/#/entry/KB-NX400-014`, `/#/search?q=E217`.
class Routes {
  static String type(ContentType t) => '/type/${t.restPath}';
  static String entry(String erc) => '/entry/${Uri.encodeComponent(erc)}';
  static const scan = '/scan';
  static const settings = '/settings';
  static const login = '/login';
  static String search([String q = '']) =>
      q.isEmpty ? '/search' : '/search?q=${Uri.encodeQueryComponent(q)}';
}

class KnowledgeApp extends StatefulWidget {
  const KnowledgeApp({super.key, required this.repository});

  final KnowledgeRepository repository;

  static const seed = Color(0xFF0B3D5C);

  @override
  State<KnowledgeApp> createState() => _KnowledgeAppState();
}

class _KnowledgeAppState extends State<KnowledgeApp> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  KnowledgeRepository get repository => widget.repository;

  @override
  void initState() {
    super.initState();
    repository.lastReport.addListener(_onSynced);
  }

  @override
  void dispose() {
    repository.lastReport.removeListener(_onSynced);
    super.dispose();
  }

  /// Tells the user what an incremental synchronization changed.
  void _onSynced() {
    final report = repository.lastReport.value;
    if (report == null || !report.hasChanges || report.initial) return;
    _messenger.currentState?.showSnackBar(
      SnackBar(content: Text('Knowledge base updated: $report.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: KnowledgeApp.seed,
        brightness: b,
      ),
      useMaterial3: true,
      cardTheme: const CardThemeData(margin: EdgeInsets.zero),
    );
    return RepositoryScope(
      repository: repository,
      child: MaterialApp(
        title: 'Northstar Knowledge',
        scaffoldMessengerKey: _messenger,
        debugShowCheckedModeBanner: false,
        theme: theme(Brightness.light),
        darkTheme: theme(Brightness.dark),
        onGenerateInitialRoutes: (name) => repository.requiresSignIn
            ? [_route(const RouteSettings(name: Routes.login))!]
            : [
                _route(const RouteSettings(name: '/'))!,
                if (name != '/' && name.isNotEmpty)
                  _route(RouteSettings(name: name)) ??
                      _route(const RouteSettings(name: '/'))!,
              ],
        onGenerateRoute: _route,
      ),
    );
  }

  Route<void>? _route(RouteSettings settings) {
    final uri = Uri.parse(settings.name ?? '/');
    final seg = uri.pathSegments;
    Widget? page;
    // Sign-in gate: without a user session only the login page and the
    // connection settings are reachable.
    final open =
        seg.isNotEmpty && (seg.first == 'login' || seg.first == 'settings');
    if (repository.requiresSignIn && !open) {
      page = const LoginScreen();
    } else if (seg.isNotEmpty && seg.first == 'login') {
      page = const LoginScreen();
    } else if (seg.isEmpty) {
      page = const HomeScreen();
    } else if (seg.first == 'type' && seg.length == 2) {
      final type = contentTypesByPath[seg[1]];
      if (type != null) page = TypeScreen(type: type);
    } else if (seg.first == 'entry' && seg.length == 2) {
      page = EntryScreen(erc: seg[1]);
    } else if (seg.first == 'scan' && scannerAvailable) {
      page = const ScanScreen();
    } else if (seg.first == 'settings') {
      page = const SettingsScreen();
    } else if (seg.first == 'search') {
      page = SearchScreen(initialQuery: uri.queryParameters['q'] ?? '');
    }
    if (page == null) return null;
    return MaterialPageRoute(settings: settings, builder: (_) => page!);
  }
}
