import 'package:flutter/material.dart';

import '../app.dart';
import '../data/connection.dart';
import '../data/content_types.dart';
import '../data/knowledge_repository.dart';
import '../widgets/common.dart';
import '../widgets/developer_settings.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final columns = width > 1000
        ? 4
        : (width > 700 ? 3 : (width > 420 ? 2 : 1));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _Header(repo: repo)),
          const SliverToBoxAdapter(child: SyncStatusBar()),
          if (!repo.hasData && repo.state != SyncState.syncing)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: repo.state == SyncState.notConfigured
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Configure the connection to your Liferay '
                              'server to download the knowledge base.',
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () =>
                                  Navigator.pushNamed(context, Routes.settings),
                              icon: const Icon(Icons.settings_outlined),
                              label: const Text('Configure the connection'),
                            ),
                          ],
                        )
                      : const Text(
                          'No content yet. Connect to the network and retry.',
                        ),
                ),
              ),
            )
          else ...[
            _sectionTitle(context, 'Browse by content type'),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: Constrained(
                  child: GridView.count(
                    // No implicit safe-area padding: the header already has it.
                    padding: EdgeInsets.zero,
                    crossAxisCount: columns,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: columns == 1 ? 4.6 : 1.9,
                    children: [
                      for (final t in contentTypes)
                        _TypeCard(type: t, count: repo.entriesOf(t).length),
                    ],
                  ),
                ),
              ),
            ),
            _sectionTitle(context, 'Browse by product'),
            SliverToBoxAdapter(
              child: Constrained(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in repo.products)
                        ActionChip(
                          avatar: Icon(
                            Icons.ev_station_outlined,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          // Country variants share a product code: use the ERC.
                          label: Text(
                            repo.products
                                        .where((o) => o.code == p.code)
                                        .length >
                                    1
                                ? p.erc.replaceFirst('PROD-', '')
                                : p.code,
                          ),
                          tooltip: p.title,
                          onPressed: () =>
                              Navigator.pushNamed(context, Routes.entry(p.erc)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => SliverToBoxAdapter(
    child: Constrained(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.repo});

  final KnowledgeRepository repo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0B3D5C), Color(0xFF0B6E99)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top + 24,
        16,
        24,
      ),
      child: Constrained(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_stories, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  // Long-press: hidden developer settings (scanner camera).
                  child: GestureDetector(
                    onLongPress: scannerAvailable
                        ? () => showDeveloperSettings(context)
                        : null,
                    child: Text(
                      'Northstar Enterprise Knowledge',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (scannerAvailable)
                  IconButton(
                    tooltip: 'Scan a QR code',
                    color: Colors.white,
                    onPressed: () => Navigator.pushNamed(context, Routes.scan),
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                _AccountMenu(repo: repo),
                IconButton(
                  tooltip: 'Synchronize',
                  color: Colors.white,
                  onPressed: repo.state == SyncState.syncing ? null : repo.sync,
                  icon: const Icon(Icons.sync),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${repo.totalCount} contents  ·  ${syncLabel(repo)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 8),
            const SignedInBar(onDark: true),
            const SizedBox(height: 12),
            SearchBar(
              hintText: 'Search articles, error codes, products…',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              onSubmitted: (q) =>
                  Navigator.pushNamed(context, Routes.search(q)),
              onTap: null,
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({required this.type, required this.count});

  final ContentType type;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, Routes.type(type)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: type.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(type.icon, color: type.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      type.label,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      type.description,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count',
                style: theme.textTheme.titleLarge?.copyWith(color: type.color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Signed-in user, connection settings and sign-out.
class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.repo});

  final KnowledgeRepository repo;

  @override
  Widget build(BuildContext context) {
    final session = repo.session;
    final who =
        session?.userName ??
        (repo.connection.authMode == AuthMode.clientCredentials
            ? 'Service account'
            : 'Not signed in');
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.person_outline),
          onPressed: null,
          child: Text(who),
        ),
        const Divider(height: 1),
        MenuItemButton(
          leadingIcon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.pushNamed(context, Routes.settings),
          child: const Text('Liferay connection'),
        ),
        if (session != null)
          MenuItemButton(
            leadingIcon: const Icon(Icons.logout),
            onPressed: () => confirmSignOut(context),
            child: const Text('Sign out'),
          ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: 'Account: $who',
        color: Colors.white,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: session == null
            ? const Icon(Icons.account_circle_outlined)
            : CircleAvatar(
                radius: 14,
                backgroundColor: Colors.white,
                child: Text(
                  session.userName.isEmpty
                      ? '?'
                      : session.userName[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF0B3D5C),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
      ),
    );
  }
}
