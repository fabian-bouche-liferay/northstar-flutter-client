import 'package:flutter/material.dart';

import '../app.dart';
import '../widgets/common.dart';

/// Entry gate (authorization code flow): users sign in with their Liferay
/// account before seeing any content; they then only see what their
/// permissions allow, and get their own offline copy.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    final repo = RepositoryScope.of(context, listen: false);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.signIn();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    final theme = Theme.of(context);
    final connection = repo.connection;
    final configured = connection.hasCredentials;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0B3D5C), Color(0xFF0B6E99)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Constrained(
                maxWidth: 420,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.auto_stories,
                          size: 48,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Northstar Enterprise Knowledge',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sign in with your Liferay account. You will see the '
                          'content your permissions allow, also offline.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                        if (repo.lastError != null &&
                            repo.lastError!.contains('Session expired'))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Your session has expired. Please sign in again.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ),
                        FilledButton.icon(
                          onPressed: _busy || !configured ? null : _signIn,
                          icon: _busy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.login),
                          label: const Text('Sign in with Liferay'),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Text(
                          configured
                              ? connection.baseUrl
                              : 'The Liferay connection is not configured.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              Navigator.pushNamed(context, Routes.settings),
                          icon: const Icon(Icons.settings_outlined, size: 18),
                          label: const Text('Connection settings'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
