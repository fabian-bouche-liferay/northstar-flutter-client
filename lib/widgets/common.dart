import 'package:flutter/material.dart';

import '../app.dart';
import '../data/entry.dart';
import '../data/knowledge_repository.dart';

/// Centers content and caps its width on large screens.
class Constrained extends StatelessWidget {
  const Constrained({super.key, required this.child, this.maxWidth = 960});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}

class TypeAvatar extends StatelessWidget {
  const TypeAvatar({super.key, required this.entry, this.size = 40});

  final Entry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = entry.type.color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size / 4),
      ),
      child: Icon(entry.type.icon, color: color, size: size * 0.55),
    );
  }
}

/// Colored badge for lifecycle / confidentiality / severity values.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  static Color lifecycleColor(String? key) => switch (key) {
    'current' => const Color(0xFF2E7D32),
    'draft' => const Color(0xFF1565C0),
    'superseded' => const Color(0xFFEF6C00),
    'deprecated' => const Color(0xFFC62828),
    _ => const Color(0xFF757575),
  };

  static Color confidentialityColor(String? key) => switch (key) {
    'public' => const Color(0xFF00838F),
    'internal' => const Color(0xFF6A1B9A),
    'confidential' => const Color(0xFFC62828),
    _ => const Color(0xFF757575),
  };

  static Color severityColor(String? key) => switch (key) {
    'high' => const Color(0xFFC62828),
    'medium' => const Color(0xFFEF6C00),
    _ => const Color(0xFF757575),
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class EntryTile extends StatelessWidget {
  const EntryTile({super.key, required this.entry, this.showType = false});

  final Entry entry;
  final bool showType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = [
      if (showType) entry.type.singular,
      if (entry.code != entry.title) entry.code,
      if (entry.type.facts.isNotEmpty) entry.text(entry.type.facts.first.key),
    ].whereType<String>().toSet().join('  ·  ');
    final lifecycle = entry.lifecycleKey;
    return ListTile(
      leading: TypeAvatar(entry: entry),
      title: Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        details,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      trailing: lifecycle != null && lifecycle != 'current'
          ? StatusBadge(
              entry.lifecycleName ?? lifecycle,
              color: StatusBadge.lifecycleColor(lifecycle),
            )
          : const Icon(Icons.chevron_right),
      onTap: () => Navigator.pushNamed(context, Routes.entry(entry.erc)),
    );
  }
}

/// Shows sync progress and the offline banner.
class SyncStatusBar extends StatelessWidget {
  const SyncStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    final theme = Theme.of(context);
    switch (repo.state) {
      case SyncState.syncing:
        return const LinearProgressIndicator(minHeight: 3);
      case SyncState.offline:
        final when = repo.syncedAt == null
            ? 'No offline copy available yet.'
            : 'Showing content synced on ${formatDate(repo.syncedAt!)} at '
                  '${_hhmm(repo.syncedAt!)}.';
        return Material(
          color: theme.colorScheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Row(
              children: [
                Icon(
                  Icons.cloud_off,
                  size: 18,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Tooltip(
                    message: repo.lastError ?? '',
                    child: Text(
                      'Offline mode. $when',
                      style: TextStyle(
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                ),
                TextButton(onPressed: repo.sync, child: const Text('Retry')),
              ],
            ),
          ),
        );
      case SyncState.notConfigured:
        return Material(
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Row(
              children: [
                Icon(
                  Icons.link_off,
                  size: 18,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Liferay connection not configured.',
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.pushNamed(context, Routes.settings),
                  child: const Text('Configure'),
                ),
              ],
            ),
          ),
        );
      case SyncState.signedOut:
        return Material(
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Row(
              children: [
                Icon(
                  Icons.lock_clock_outlined,
                  size: 18,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your session has ended.',
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pushNamedAndRemoveUntil(
                    context,
                    Routes.login,
                    (_) => false,
                  ),
                  child: const Text('Sign in'),
                ),
              ],
            ),
          ),
        );
      case SyncState.idle:
      case SyncState.online:
        return const SizedBox.shrink();
    }
  }
}

String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String syncLabel(KnowledgeRepository repo) => switch (repo.state) {
  SyncState.syncing => 'Synchronizing…',
  SyncState.offline => 'Offline',
  SyncState.notConfigured => 'Not connected',
  SyncState.signedOut => 'Signed out',
  _ when repo.syncedAt != null =>
    'Synced ${formatDate(repo.syncedAt!)} ${_hhmm(repo.syncedAt!)}',
  _ => 'Not synchronized',
};

/// Asks for confirmation, signs the user out (deleting their offline copy)
/// and goes back to the sign-in page.
Future<void> confirmSignOut(BuildContext context) async {
  final repo = RepositoryScope.of(context, listen: false);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.logout),
      title: const Text('Sign out?'),
      content: Text(
        'You will be signed out of ${repo.connection.baseUrl}. Your offline '
        'copy of the knowledge base will be deleted from this device.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await repo.signOut();
  if (context.mounted) {
    Navigator.pushNamedAndRemoveUntil(context, Routes.login, (_) => false);
  }
}

/// "Signed in as …" with a Sign out button (shown when a user is signed in).
class SignedInBar extends StatelessWidget {
  const SignedInBar({super.key, this.onDark = false});

  /// White text, for the gradient header.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final session = RepositoryScope.of(context).session;
    if (session == null) return const SizedBox.shrink();
    final color = onDark ? Colors.white : null;
    return Row(
      children: [
        Icon(Icons.account_circle_outlined, size: 20, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Signed in as ${session.userName}',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color),
          ),
        ),
        TextButton.icon(
          style: onDark
              ? TextButton.styleFrom(foregroundColor: Colors.white)
              : null,
          onPressed: () => confirmSignOut(context),
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}
