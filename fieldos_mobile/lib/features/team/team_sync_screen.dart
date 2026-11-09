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

import 'package:fieldos_mobile/features/tasks/team_roster.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_bootstrap.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_service.dart';
import 'package:fieldos_mobile/l10n/language.dart';

class TeamSyncScreen extends ConsumerStatefulWidget {
  const TeamSyncScreen({super.key});

  @override
  ConsumerState<TeamSyncScreen> createState() => _TeamSyncScreenState();
}

/// The step after sign-in that needs the code we emailed.
enum _EmailCodeStep { confirmSignUp, resetPassword }

class _TeamSyncScreenState extends ConsumerState<TeamSyncScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _emailCode = TextEditingController();
  final _newPassword = TextEditingController();
  _EmailCodeStep? _codeStep;
  String _codeEmail = '';
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
    _emailCode.dispose();
    _newPassword.dispose();
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
        await saveRoster(db, company.id, roster, myUserId: service.userId);
        ref.invalidate(teamRosterProvider(company.id));
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
            _startCodeStep(_EmailCodeStep.confirmSignUp, email);
            _say('We sent a code to $email. Type it below to finish creating your account.');
            _password.clear();
            return;
          case CloudSyncOutcome.wrongPassword:
            _say('$email already has an account, and that password is not right for it. Try again, or tap '
                '"Forgot password?" to choose a new one.', error: true);
            return;
          case CloudSyncOutcome.failed:
            final cause = result.cause;
            _say(cause == null ? 'Could not sign in. Try again.' : friendlyError(cause, result.stack), error: true);
            return;
        }
        _password.clear();
        await _afterSignIn();
      });

  Future<void> _afterSignIn() async {
    await ref.read(cloudSyncBootstrapProvider).ensureRunning();
    await _refresh();
  }

  void _startCodeStep(_EmailCodeStep step, String email) => setState(() {
        _codeStep = step;
        _codeEmail = email;
        _emailCode.clear();
        _newPassword.clear();
      });

  void _leaveCodeStep() => setState(() {
        _codeStep = null;
        _message = null;
        _emailCode.clear();
        _newPassword.clear();
      });

  Future<void> _forgotPassword() => _run(() async {
        final email = _email.text.trim();
        if (!email.contains('@')) {
          _say('Type your email above first, then tap "Forgot password?" again.', error: true);
          return;
        }
        await ref.read(cloudSyncServiceProvider).sendPasswordResetCode(email);
        _startCodeStep(_EmailCodeStep.resetPassword, email);
        _say('If $email has an account, a code is on its way. Type it below with your new password.');
      });

  Future<void> _resendCode() => _run(() async {
        final service = ref.read(cloudSyncServiceProvider);
        if (_codeStep == _EmailCodeStep.resetPassword) {
          await service.sendPasswordResetCode(_codeEmail);
        } else {
          await service.resendSignUpCode(_codeEmail);
        }
        _emailCode.clear();
        _say('A new code is on its way to $_codeEmail. Codes stop working after an hour.');
      });

  Future<void> _submitCode() => _run(() async {
        final code = _emailCode.text.replaceAll(RegExp(r'\s'), '');
        if (!RegExp(r'^\d{6,10}$').hasMatch(code)) {
          _say('Type the code from the email: it is 6 digits.', error: true);
          return;
        }
        final service = ref.read(cloudSyncServiceProvider);
        if (_codeStep == _EmailCodeStep.resetPassword) {
          if (_newPassword.text.length < 6) {
            _say('Choose a new password of at least 6 characters.', error: true);
            return;
          }
          await service.resetPassword(email: _codeEmail, code: code, newPassword: _newPassword.text);
          _say('New password saved. Signed in as $_codeEmail.');
        } else {
          await service.confirmSignUp(email: _codeEmail, code: code);
          _say('Account created for $_codeEmail.');
        }
        setState(() {
          _codeStep = null;
          _emailCode.clear();
          _newPassword.clear();
        });
        await _afterSignIn();
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
        title: Text(tr('Delete your cloud account?')),
        content: Text(
          'This permanently deletes $email from FieldOS cloud.\n\n'
          'Companies where you are the only member are deleted from the cloud with all their records. '
          'Companies with other members keep their records, and ownership passes to another member.\n\n'
          'Data on this phone is not deleted. Uninstall the app to remove it.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Delete account')),
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

  Future<void> _removeMember(String companyId, CloudMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Remove from the team?')),
        content: Text(
          '${m.email} will stop getting this company\'s projects and cannot send anything new. '
          'Work they already recorded stays.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Remove')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await ref.read(cloudSyncServiceProvider).removeMember(companyId: companyId, userId: m.userId);
      _say('${m.email} is no longer on the team.');
      await _refresh();
    });
  }

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
      children.add(Text(tr('Team sync is not set up in this build of FieldOS. Everything still works offline on this phone.'),
      ));
    } else if (!service.isSignedIn) {
      children.addAll(_codeStep == null ? _signInSection() : _codeSection(_codeStep!));
    } else {
      children.add(Row(children: [
        const Icon(Icons.verified_user, size: 18, color: Brand.ok),
        const SizedBox(width: 8),
        Expanded(child: Text(trf('Signed in as {email}', {'email': service.email ?? ''}))),
        TextButton(onPressed: _busy ? null : _signOut, child: Text(tr('Sign out'))),
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
            label: Text(tr('Delete my cloud account'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
      appBar: AppBar(title: Text(tr('Team & sync'))),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.all(16), children: children),
      ),
    );
  }

  List<Widget> _signInSection() => [
        Text(tr('Sign in to share projects, daily reports, issues and chat with your team.'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(tr('Use your own email. A new email creates an account automatically.'),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        TextField(
          controller: _email,
          decoration: InputDecoration(labelText: tr('Email'), prefixIcon: Icon(Icons.alternate_email)),
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.next,
          autocorrect: false,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _password,
          decoration: InputDecoration(labelText: tr('Password'), prefixIcon: Icon(Icons.lock_outline)),
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _signIn(),
          autocorrect: false,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: _busy ? null : _forgotPassword, child: Text(tr('Forgot password?'))),
        ),
        FilledButton(onPressed: _busy ? null : _signIn, child: _busyOr('Sign in')),
      ];

  List<Widget> _codeSection(_EmailCodeStep step) {
    final reset = step == _EmailCodeStep.resetPassword;
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return [
      Text(reset ? tr('Choose a new password') : tr('Check your email'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(
        reset
            ? 'Type the code we emailed to $_codeEmail, and the new password for your cloud account.'
            : 'Type the code we emailed to $_codeEmail. It can take a minute to arrive; look in spam too.',
        style: muted,
      ),
      const SizedBox(height: 16),
      TextField(
        key: const Key('email-code'),
        controller: _emailCode,
        decoration: InputDecoration(labelText: tr('Code from the email'), prefixIcon: Icon(Icons.pin_outlined)),
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
        textInputAction: reset ? TextInputAction.next : TextInputAction.done,
        onSubmitted: reset ? null : (_) => _busy ? null : _submitCode(),
        autocorrect: false,
        enableSuggestions: false,
      ),
      if (reset) ...[
        const SizedBox(height: 8),
        TextField(
          key: const Key('new-cloud-password'),
          controller: _newPassword,
          decoration: InputDecoration(labelText: tr('New password'), prefixIcon: Icon(Icons.lock_outline)),
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _submitCode(),
          autocorrect: false,
        ),
      ],
      const SizedBox(height: 12),
      FilledButton(
        onPressed: _busy ? null : _submitCode,
        child: _busyOr(reset ? tr('Save new password') : tr('Confirm email')),
      ),
      const SizedBox(height: 4),
      Wrap(spacing: 8, children: [
        TextButton(onPressed: _busy ? null : _resendCode, child: Text(tr('Send a new code'))),
        TextButton(onPressed: _busy ? null : _leaveCodeStep, child: Text(tr('Back to sign in'))),
      ]),
      if (!reset)
        Text(tr('Got a link instead of a code? Open it, then come back and sign in.'), style: muted),
    ];
  }

  List<Widget> _linkSection(String? companyName, {required bool canRegister}) => [
        if (canRegister) ...[
          Text(trf('Put {company} on the cloud', {'company': companyName ?? ''}), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(tr('You become the owner. Your team joins with a code you share from here.')),
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
        Text(tr('Join your company'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(tr('Ask the owner for the join code shown on their Team & sync screen.')),
        const SizedBox(height: 8),
        TextField(
          controller: _code,
          decoration: InputDecoration(labelText: tr('Join code'), prefixIcon: Icon(Icons.key_outlined)),
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
      Text(tr('Sync'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(tr('Runs automatically when the app opens and every few minutes while it is open.')),
      const SizedBox(height: 8),
      Text(trf('Last synced: {last} · Waiting to send: {n}', {'last': last, 'n': _pending}), style: Theme.of(context).textTheme.bodySmall),
      if (_parked > 0)
        Text(trf('{n} changes could not be sent after several tries.', {'n': _parked}),
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
            child: Text(tr('Retry failed')),
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
      Text(tr('Team'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (code != null)
        Card(
          child: ListTile(
            title: Text(tr('Join code')),
            subtitle: SelectableText(code, style: const TextStyle(fontSize: 20, letterSpacing: 2, fontWeight: FontWeight.w600)),
            trailing: Wrap(children: [
              IconButton(
                tooltip: tr('Copy'),
                icon: const Icon(Icons.copy),
                onPressed: () => Clipboard.setData(ClipboardData(text: code)),
              ),
              IconButton(
                tooltip: tr('Share'),
                icon: const Icon(Icons.share),
                onPressed: () => SharePlus.instance.share(ShareParams(
                  text: 'Join our company on FieldOS: open the app, go to Team & sync, sign in and enter join code $code',
                )),
              ),
              if (isOwner)
                IconButton(
                  tooltip: tr('Make a new code'),
                  icon: const Icon(Icons.refresh),
                  onPressed: _busy ? null : () => _resetCode(companyId),
                ),
            ]),
          ),
        ),
      if (_roster == null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(tr('Connect to the internet to see your team.'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        )
      else
        for (final m in _roster!)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person),
            title: Text(m.email, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: isOwner && m.role != 'owner'
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    DropdownButton<String>(
                      value: m.role,
                      items: [
                        for (final r in ['project_manager', 'site_engineer'])
                          DropdownMenuItem(value: r, child: Text(_roleLabels[r]!)),
                      ],
                      onChanged: _busy ? null : (r) => r == null ? null : _changeRole(companyId, m, r),
                    ),
                    IconButton(
                      tooltip: tr('Remove from the team'),
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: _busy ? null : () => _removeMember(companyId, m),
                    ),
                  ])
                : Text(_roleLabels[m.role] ?? m.role),
          ),
    ];
  }

  Widget _busyOr(String label) => _busy
      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
      : Text(label);
}
