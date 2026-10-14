import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app.dart';
import '../data/auth_flow.dart';
import '../data/connection.dart';
import '../data/connection_store.dart';
import '../data/liferay_client.dart';
import '../data/session.dart';
import '../widgets/common.dart';

/// Connection settings: Liferay URL, CMS space and OAuth 2 client, stored on
/// this device. Lets a colleague use a shared build with their own client.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

enum CheckStatus { ok, warning, error }

/// One step of the connection test.
class ConnectionCheck {
  const ConnectionCheck(this.status, this.label, this.detail);

  final CheckStatus status;
  final String label;
  final String detail;
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _form = GlobalKey<FormState>();
  // One client ID per mode, kept separately (user sign-in / service account).
  late final TextEditingController _url,
      _space,
      _userClientId,
      _serviceClientId,
      _secret;
  bool _showSecret = false;
  late AuthMode _mode;
  bool _busy = false;
  List<ConnectionCheck>? _checks;

  @override
  void initState() {
    super.initState();
    final c = RepositoryScope.of(context, listen: false).connection;
    _url = TextEditingController(text: c.liferayUrl);
    _space = TextEditingController(text: c.spaceErc);
    _userClientId = TextEditingController(text: c.userClientId);
    _serviceClientId = TextEditingController(text: c.serviceClientId);
    _secret = TextEditingController(text: c.serviceClientSecret);
    _mode = c.authMode;
  }

  @override
  void dispose() {
    for (final c in [_url, _space, _userClientId, _serviceClientId, _secret]) {
      c.dispose();
    }
    super.dispose();
  }

  Connection get _draft => Connection(
    liferayUrl: _url.text.trim(),
    spaceErc: _space.text.trim(),
    authMode: _mode,
    userClientId: _userClientId.text.trim(),
    serviceClientId: _serviceClientId.text.trim(),
    serviceClientSecret: _secret.text.trim(),
  );

  Future<void> _test() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _checks = null;
    });
    final repo = RepositoryScope.of(context, listen: false);
    // Authorization code: tests with the signed-in user's session, if it was
    // obtained with this very client.
    final session = repo.connection.sameClient(_draft) ? repo.session : null;
    final checks = await testConnection(_draft, session: session);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _checks = checks;
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final repo = RepositoryScope.of(context, listen: false);
    final changesOwner =
        !repo.connection.sameSource(_draft) ||
        (repo.session != null && !repo.connection.sameClient(_draft)) ||
        (_draft.authMode == AuthMode.clientCredentials &&
            repo.connection.clientId != _draft.clientId);
    if (changesOwner && repo.hasData) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Change the connection?'),
          content: const Text(
            'You will be signed out, and the offline copy of the knowledge '
            'base will be deleted from this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Change'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final done = repo.reconnect(_draft);
    if (!mounted) return;
    if (repo.requiresSignIn) {
      Navigator.pushNamedAndRemoveUntil(context, Routes.login, (_) => false);
    } else {
      Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
    }
    await done;
  }

  Future<void> _resetToDefaults() async {
    await ConnectionStore.clear();
    final defaults = Connection.fromBuild();
    setState(() {
      _url.text = defaults.liferayUrl;
      _space.text = defaults.spaceErc;
      _userClientId.text = defaults.userClientId;
      _serviceClientId.text = defaults.serviceClientId;
      _secret.text = defaults.serviceClientSecret;
      _mode = defaults.authMode;
      _checks = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String? required(String? v) =>
        v == null || v.trim().isEmpty ? 'Required' : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Liferay connection'),
        actions: [
          IconButton(
            tooltip: 'Reset to build defaults',
            icon: const Icon(Icons.restart_alt),
            onPressed: _busy ? null : _resetToDefaults,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Constrained(
          maxWidth: 640,
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Current user, with Sign out.
                if (RepositoryScope.of(context).session != null) ...[
                  Card.outlined(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                      child: const SignedInBar(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SegmentedButton<AuthMode>(
                  segments: const [
                    ButtonSegment(
                      value: AuthMode.authorizationCode,
                      icon: Icon(Icons.person_outline),
                      label: Text('User sign-in'),
                    ),
                    ButtonSegment(
                      value: AuthMode.clientCredentials,
                      icon: Icon(Icons.vpn_key_outlined),
                      label: Text('Service account'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() {
                    _mode = s.first;
                    _checks = null;
                  }),
                ),
                const SizedBox(height: 12),
                Text(
                  _mode == AuthMode.authorizationCode
                      ? 'Each user signs in with their Liferay account '
                            '(authorization code + PKCE). Use a public OAuth '
                            '2.0 client (no secret) whose callback URIs include '
                            '${AuthFlow.redirectUri()} (see the README).'
                      : 'The app uses a "Client Credentials" OAuth 2.0 client: '
                            'everyone sees what its client credential user '
                            'sees. For tests.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: 'Liferay URL',
                    hintText: 'https://liferay.example.com',
                    helperText: kIsWeb
                        ? 'Liferay must allow this site in its CORS settings.'
                        : null,
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) {
                      return kIsWeb && _mode == AuthMode.clientCredentials
                          ? null
                          : 'Required';
                    }
                    final uri = Uri.tryParse(value);
                    return uri == null || !uri.hasScheme || uri.host.isEmpty
                        ? 'Enter a full URL, e.g. https://liferay.example.com'
                        : null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _space,
                  decoration: const InputDecoration(
                    labelText: 'Space external reference code',
                    border: OutlineInputBorder(),
                  ),
                  validator: required,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  // A distinct key per mode: each field keeps its own value.
                  key: ValueKey(_mode),
                  controller: _mode == AuthMode.authorizationCode
                      ? _userClientId
                      : _serviceClientId,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'OAuth 2 client ID',
                    border: OutlineInputBorder(),
                  ),
                  validator: required,
                ),
                if (_mode == AuthMode.clientCredentials) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _secret,
                    autocorrect: false,
                    obscureText: !_showSecret,
                    decoration: InputDecoration(
                      labelText: 'OAuth 2 client secret',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _showSecret ? 'Hide' : 'Show',
                        icon: Icon(
                          _showSecret ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () =>
                            setState(() => _showSecret = !_showSecret),
                      ),
                    ),
                    validator: required,
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  _mode == AuthMode.clientCredentials
                      ? 'Stored on this device only (not encrypted).'
                      : 'No secret: your Liferay password is only entered on '
                            'the Liferay sign-in page.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                // Wraps on narrow phones instead of overflowing.
                OverflowBar(
                  alignment: MainAxisAlignment.spaceBetween,
                  overflowSpacing: 8,
                  overflowAlignment: OverflowBarAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _test,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.network_check),
                      label: const Text('Test connection'),
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save'),
                    ),
                  ],
                ),
                if (_checks != null) ...[
                  const SizedBox(height: 16),
                  Card.outlined(
                    child: Column(
                      children: [
                        for (final c in _checks!)
                          ListTile(
                            leading: Icon(
                              switch (c.status) {
                                CheckStatus.ok => Icons.check_circle,
                                CheckStatus.warning => Icons.warning_amber,
                                CheckStatus.error => Icons.error,
                              },
                              color: switch (c.status) {
                                CheckStatus.ok => Colors.green.shade700,
                                CheckStatus.warning => Colors.orange.shade800,
                                CheckStatus.error => theme.colorScheme.error,
                              },
                            ),
                            title: Text(c.label),
                            subtitle: Text(c.detail),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Checks a connection step by step: token, space content, search,
/// blueprints. Exposed for tests.
@visibleForTesting
Future<List<ConnectionCheck>> testConnection(
  Connection connection, {
  http.Client? httpClient,
  Session? session,
}) async {
  if (connection.authMode == AuthMode.authorizationCode && session == null) {
    return const [
      ConnectionCheck(
        CheckStatus.warning,
        'Sign-in required',
        'Save, then sign in: access is tested with your own account.',
      ),
    ];
  }
  final client = LiferayClient(
    connection: connection,
    httpClient: httpClient,
    session: session,
  );
  final checks = <ConnectionCheck>[];
  String explain(Object e) => switch (e) {
    LiferayException(statusCode: 400 || 401) =>
      'Rejected: check the client ID and secret.',
    LiferayException(statusCode: 403) =>
      'Forbidden: the OAuth 2 client lacks the scope.',
    LiferayException(statusCode: final code?) => 'HTTP $code',
    http.ClientException() =>
      kIsWeb
          ? 'Network error: check the URL and the CORS configuration of '
                'Liferay for this site.'
          : 'Network error: check the URL.',
    _ => '$e',
  };
  try {
    await client.accessToken();
    checks.add(
      ConnectionCheck(
        CheckStatus.ok,
        'OAuth 2 token',
        connection.authMode == AuthMode.clientCredentials
            ? 'Client credentials accepted.'
            : 'Signed in as ${client.session?.userName}.',
      ),
    );
  } catch (e) {
    checks.add(ConnectionCheck(CheckStatus.error, 'OAuth 2 token', explain(e)));
    client.close();
    return checks;
  }
  try {
    final json = await client.getJson(
      '/o/c/nmgproducts/scopes/'
      '${Uri.encodeComponent(connection.spaceErc)}?pageSize=1&fields=id',
    );
    checks.add(
      ConnectionCheck(
        CheckStatus.ok,
        'CMS content',
        '${json['totalCount']} products readable in ${connection.spaceErc}.',
      ),
    );
  } catch (e) {
    checks.add(
      ConnectionCheck(
        CheckStatus.error,
        'CMS content',
        e is LiferayException && (e.statusCode == 404 || e.statusCode == 409)
            ? 'Space "${connection.spaceErc}" not found.'
            : explain(e),
      ),
    );
  }
  try {
    await client.search('charger', pageSize: 1);
    checks.add(
      const ConnectionCheck(
        CheckStatus.ok,
        'Search',
        'Liferay search available.',
      ),
    );
  } catch (e) {
    checks.add(
      ConnectionCheck(
        CheckStatus.warning,
        'Search',
        '${explain(e)} The app will search its offline copy only.',
      ),
    );
  }
  try {
    final blueprints = await client.searchBlueprints();
    checks.add(
      ConnectionCheck(
        CheckStatus.ok,
        'Search blueprints',
        '${blueprints.length} blueprint(s) visible.',
      ),
    );
  } catch (e) {
    checks.add(
      ConnectionCheck(CheckStatus.warning, 'Search blueprints', explain(e)),
    );
  }
  client.close();
  return checks;
}
