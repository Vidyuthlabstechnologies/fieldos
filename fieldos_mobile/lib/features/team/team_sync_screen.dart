/// "Team & sync": everything that connects this phone to the rest of the
/// company. Open to every role (cloud sync used to sit inside the
/// owner-only Settings screen, so a site engineer's phone could never sync).
///
/// Flow: sign in (own email) -> either put this phone's company on the
/// cloud (owner) or join a colleague's company with its join code -> sync
/// runs in the background from then on (see cloud_sync_bootstrap.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_bootstrap.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_service.dart';

class TeamSyncScreen extends ConsumerStatefulWidget {
  const TeamSyncScreen({super.key});

  @override
  ConsumerState<TeamSyncScreen> createState() => _TeamSyncScreenState();
}

class _TeamSyncScreenState extends ConsumerState<TeamSyncScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  bool? _linked;
  CloudCompany? _cloudCompany;
  List<CloudMember>? _roster;
  int _pending = 0;
  int _parked = 0;
  String? _lastSyncedAt;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  void _say(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _messageIsError = error;
    });
  }

  Future<void> _refresh() async {
    final service = ref.read(cloudSyncServiceProvider);
    final db = ref.read(appDatabaseProvider);
    final company = ref.read(sessionProvider).activeCompany;
    if (!service.isSignedIn) await service.restoreSession();
    final linked = company != null && await ref.read(cloudLinksProvider).isLinked(company.id);
    final pending = await db.syncOutboxDao.pendingCount();
    final parked = await db.syncOutboxDao.parkedCount();
    final last = await db.settingsDao.get('last_sync_at');
    CloudCompany? cloud;
    List<CloudMember>? roster;
    if (linked && service.isSignedIn) {
      try {
        cloud = await service.registerCompany(companyId: company.id, name: company.name);
        roster = await service.roster(company.id);
        await ref.read(sessionProvider.notifier).setLocalRole(company.id, cloud.role);
      } catch (_) {
        // Offline: keep showing local status; the team list needs a connection.
      }
    }
    if (!mounted) return;
    setState(() {
      _linked = linked;
      _cloudCompany = cloud;
      _roster = roster;
      _pending = pending;
      _parked = parked;
      _lastSyncedAt = (last == null || last.isEmpty) ? null : last;
    });
  }

  Future<void> _run(Future<void> Function() body) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await body();
    } catch (e, st) {
      // Supabase errors carry the server's own short message ("invalid join
      // code"); anything unexpected becomes a plain sentence.
      _say(friendlyError(e, st), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() => _run(() async {
        final email = _email.text.trim();
        if (!email.contains('@') || _password.text.length < 6) {
          _say('Enter your email and a password of at least 6 characters.', error: true);
          return;
        }
        final result = await ref.read(cloudSyncServiceProvider).enableSync(email: email, password: _password.text);
        switch (result.outcome) {
          case CloudSyncOutcome.signedIn:
            _say('Signed in as $email.');
          case CloudSyncOutcome.signedUp:
            _say('Account created for $email.');
          case CloudSyncOutcome.needsEmailConfirmation:
            _say('Check $email for a confirmation link, then sign in here.');
          case CloudSyncOutcome.failed:
            _say(result.error ?? 'Could not sign in.', error: true);
        }
        _password.clear();
        await ref.read(cloudSyncBootstrapProvider).ensureRunning();
        await _refresh();
      });

  Future<void> _afterLinked(String companyId) async {
    await ref.read(cloudLinksProvider).link(companyId);
    // Writes rejected before the company existed on the server were parked
    // after repeated failures; they can go through now.
    await ref.read(appDatabaseProvider).syncOutboxDao.retryParked();
    await ref.read(cloudSyncBootstrapProvider).ensureRunning();
  }

  Future<void> _registerCompany() => _run(() async {
        final company = ref.read(sessionProvider).activeCompany!;
        await ref.read(cloudSyncServiceProvider).registerCompany(companyId: company.id, name: company.name);
        await _afterLinked(company.id);
        _say('${company.name} is on the cloud. Share the join code with your team.');
        await _refresh();
      });

  Future<void> _joinCompany() => _run(() async {
        final code = _code.text.trim();
        if (code.isEmpty) {
          _say('Enter the join code from your company owner.', error: true);
          return;
        }
        final cloud = await ref.read(cloudSyncServiceProvider).joinCompany(code);
        await ref
            .read(sessionProvider.notifier)
            .adoptCloudCompany(id: cloud.companyId, name: cloud.name ?? 'Company', role: cloud.role);
        await _afterLinked(cloud.companyId);
        _code.clear();
        _say('Joined ${cloud.name ?? 'your company'}. Projects will appear after the first sync.');
        await _refresh();
      });

  Future<void> _syncNow() => _run(() async {
        final result = await ref.read(cloudSyncServiceProvider).syncNow();
        if (result.failed == 0) {
          await ref.read(appDatabaseProvider).settingsDao.set('last_sync_at', DateTime.now().toIso8601String());
          _say('Synced. ${result.succeeded} change${result.succeeded == 1 ? '' : 's'} sent, latest data received.');
        } else {
          _say('${result.succeeded} sent, ${result.failed} waiting. They will retry on the next sync.', error: true);
        }
        await _refresh();
      });

  Future<void> _signOut() => _run(() async {
        ref.read(cloudSyncBootstrapProvider).stop();
        await ref.read(cloudSyncServiceProvider).disableSync();
        _say('Signed out. This phone keeps working offline.');
        await _refresh();
      });

  Future<void> _deleteAccount() async {
    final email = ref.read(cloudSyncServiceProvider).email ?? 'this account';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your cloud account?'),
        content: Text(
          'This permanently deletes $email from FieldOS cloud.\n\n'
          'Companies where you are the only member are deleted from the cloud with all their records. '
          'Companies with other members keep their records, and ownership passes to another member.\n\n'
          'Data on this phone is not deleted. Uninstall the app to remove it.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      ref.read(cloudSyncBootstrapProvider).stop();
      await ref.read(cloudSyncServiceProvider).deleteAccount();
      await ref.read(cloudLinksProvider).clear();
      _say('Your cloud account is deleted. This phone keeps working offline.');
      await _refresh();
    });
  }

  Future<void> _resetCode(String companyId) => _run(() async {
        await ref.read(cloudSyncServiceProvider).regenerateJoinCode(companyId);
        _say('New join code created. The old code no longer works.');
        await _refresh();
      });

  Future<void> _changeRole(String companyId, CloudMember m, String role) => _run(() async {
        await ref.read(cloudSyncServiceProvider).setMemberRole(companyId: companyId, userId: m.userId, role: role);
        await _refresh();
      });

  static const _roleLabels = {
    'owner': 'Owner',
    'project_manager': 'Project manager',
    'site_engineer': 'Site engineer',
  };

  @override
  Widget build(BuildContext context) {
    final available = ref.watch(cloudSyncAvailableProvider);
    final service = ref.watch(cloudSyncServiceProvider);
    final session = ref.watch(sessionProvider);
    final company = session.activeCompany;

    final children = <Widget>[];
    if (!available) {
      children.add(const Text(
        'Team sync is not set up in this build of FieldOS. Everything still works offline on this phone.',
      ));
    } else if (!service.isSignedIn) {
      children.addAll(_signInSection());
    } else {
      children.add(Row(children: [
        const Icon(Icons.verified_user, size: 18, color: Brand.ok),
        const SizedBox(width: 8),
        Expanded(child: Text('Signed in as ${service.email ?? ''}')),
        TextButton(onPressed: _busy ? null : _signOut, child: const Text('Sign out')),
      ]));
      children.add(const SizedBox(height: 16));
      if (company == null || _linked == false) {
        children.addAll(_linkSection(company?.name, canRegister: company != null && session.role == Roles.owner));
      } else if (_linked == true) {
        children.addAll(_syncSection());
        children.add(const SizedBox(height: 24));
        children.addAll(_teamSection(company.id));
      } else {
        children.add(const Center(child: CircularProgressIndicator()));
      }
      children.addAll([
        const SizedBox(height: 32),
        const Divider(),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : _deleteAccount,
            icon: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
            label: Text('Delete my cloud account', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ),
      ]);
    }
    if (_message != null) {
      children.addAll([
        const SizedBox(height: 16),
        FormMessage(_message!, error: _messageIsError),
      ]);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Team & sync')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.all(16), children: children),
      ),
    );
  }

  List<Widget> _signInSection() => [
        Text('Sign in to share projects, daily reports, issues and chat with your team.',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('Use your own email. A new email creates an account automatically.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        TextField(
          controller: _email,
          decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.alternate_email)),
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.next,
          autocorrect: false,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _password,
          decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)),
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _signIn(),
          autocorrect: false,
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy ? null : _signIn, child: _busyOr('Sign in')),
      ];

  List<Widget> _linkSection(String? companyName, {required bool canRegister}) => [
        if (canRegister) ...[
          Text('Put $companyName on the cloud', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('You become the owner. Your team joins with a code you share from here.'),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _registerCompany,
            icon: const Icon(Icons.cloud_upload),
            label: _busyOr('Put company on the cloud'),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
        ],
        Text('Join your company', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('Ask the owner for the join code shown on their Team & sync screen.'),
        const SizedBox(height: 8),
        TextField(
          controller: _code,
          decoration: const InputDecoration(labelText: 'Join code', prefixIcon: Icon(Icons.key_outlined)),
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _joinCompany(),
          autocorrect: false,
          enableSuggestions: false,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _joinCompany,
          icon: const Icon(Icons.group_add),
          label: _busyOr('Join company'),
        ),
      ];

  List<Widget> _syncSection() {
    final lastAt = _lastSyncedAt == null ? null : DateTime.tryParse(_lastSyncedAt!);
    final last = lastAt == null ? 'never' : fmtDateTime(lastAt);
    return [
      Text('Sync', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      const Text('Runs automatically when the app opens and every few minutes while it is open.'),
      const SizedBox(height: 8),
      Text('Last synced: $last · Waiting to send: $_pending', style: Theme.of(context).textTheme.bodySmall),
      if (_parked > 0)
        Text('$_parked change${_parked == 1 ? '' : 's'} could not be sent after several tries.',
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      const SizedBox(height: 8),
      Row(children: [
        FilledButton.icon(onPressed: _busy ? null : _syncNow, icon: const Icon(Icons.sync), label: _busyOr('Sync now')),
        if (_parked > 0) ...[
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _run(() async {
                      await ref.read(appDatabaseProvider).syncOutboxDao.retryParked();
                      await _syncNow();
                    }),
            child: const Text('Retry failed'),
          ),
        ],
      ]),
    ];
  }

  List<Widget> _teamSection(String companyId) {
    final cloud = _cloudCompany;
    final isOwner = cloud?.role == 'owner';
    final code = cloud?.joinCode;
    return [
      Text('Team', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (code != null)
        Card(
          child: ListTile(
            title: const Text('Join code'),
            subtitle: SelectableText(code, style: const TextStyle(fontSize: 20, letterSpacing: 2, fontWeight: FontWeight.w600)),
            trailing: Wrap(children: [
              IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy),
                onPressed: () => Clipboard.setData(ClipboardData(text: code)),
              ),
              IconButton(
                tooltip: 'Share',
                icon: const Icon(Icons.share),
                onPressed: () => SharePlus.instance.share(ShareParams(
                  text: 'Join our company on FieldOS: open the app, go to Team & sync, sign in and enter join code $code',
                )),
              ),
              if (isOwner)
                IconButton(
                  tooltip: 'Make a new code',
                  icon: const Icon(Icons.refresh),
                  onPressed: _busy ? null : () => _resetCode(companyId),
                ),
            ]),
          ),
        ),
      if (_roster == null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('Connect to the internet to see your team.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        )
      else
        for (final m in _roster!)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person),
            title: Text(m.email),
            trailing: isOwner && m.role != 'owner'
                ? DropdownButton<String>(
                    value: m.role,
                    items: [
                      for (final r in ['project_manager', 'site_engineer'])
                        DropdownMenuItem(value: r, child: Text(_roleLabels[r]!)),
                    ],
                    onChanged: _busy ? null : (r) => r == null ? null : _changeRole(companyId, m, r),
                  )
                : Text(_roleLabels[m.role] ?? m.role),
          ),
    ];
  }

  Widget _busyOr(String label) => _busy
      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
      : Text(label);
}
