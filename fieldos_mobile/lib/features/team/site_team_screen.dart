/// A site's team: who is on it, in which role, with what approval limit,
/// and whether only the team (plus the company's owners and managers) can
/// see the site. Rules in auth/site_roles.dart; the server holds the same
/// ones (20261110210000_site_roles.sql).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/site_roles.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/tasks/team_roster.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_service.dart';

final siteTeamProvider = FutureProvider.autoDispose.family<List<ProjectMember>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).siteTeamDao.membersFor(projectId));

final membersOnlyProvider = FutureProvider.autoDispose.family<bool, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).siteTeamDao.isMembersOnly(projectId));

/// The signed-in person's access on a site, checking both this phone's
/// user id and their cloud account.
final mySiteAccessProvider = FutureProvider.autoDispose.family<SiteAccessFor, String>((ref, projectId) async {
  final s = ref.watch(sessionProvider);
  final roster = await ref.watch(teamRosterProvider(s.activeCompany?.id ?? '').future);
  return siteAccessFor(ref.watch(appDatabaseProvider), projectId,
      userId: s.user?.id, companyRole: s.role, cloudUserId: roster.myUserId);
});

class SiteTeamScreen extends ConsumerStatefulWidget {
  const SiteTeamScreen({super.key, required this.project});
  final Project project;

  @override
  ConsumerState<SiteTeamScreen> createState() => _SiteTeamScreenState();
}

class _SiteTeamScreenState extends ConsumerState<SiteTeamScreen> {
  bool _busy = false;

  String get _pid => widget.project.id;

  Future<void> _run(Future<void> Function() job, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
      ref.invalidate(siteTeamProvider(_pid));
      ref.invalidate(membersOnlyProvider(_pid));
      ref.invalidate(mySiteAccessProvider(_pid));
      if (mounted && done != null) showSnack(context, done);
    } catch (e, st) {
      if (mounted) showSnack(context, friendlyError(e, st), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _isSelf(String userId, TeamRoster roster) {
    final me = ref.read(sessionProvider).user?.id;
    return userId == me || (roster.myUserId != null && userId == roster.myUserId);
  }

  String _name(String userId, TeamRoster roster) {
    if (_isSelf(userId, roster)) return tr('You');
    final m = roster.byId(userId);
    return m == null ? tr('Someone on the team') : m.email;
  }

  Future<void> _add(TeamRules rules, TeamRoster roster, List<ProjectMember> team) async {
    final onTeam = {for (final m in team) m.userId};
    final choices = [for (final m in roster.members) if (!onTeam.contains(m.userId)) m];
    if (choices.isEmpty) {
      showSnack(context, tr('Everyone in the company is already on this site.'));
      return;
    }
    final picked = await showModalBottomSheet<CloudMember>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text(tr('Add to this site'), style: Theme.of(ctx).textTheme.titleMedium)),
          for (final m in choices)
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_outlined),
              title: Text(m.userId == roster.myUserId ? tr('You') : m.email),
              subtitle: Text(SiteRole.label(m.role)),
              onTap: () => Navigator.pop(ctx, m),
            ),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    final result = await _editSheet(rules, name: picked.email, role: SiteRole.siteEngineer, limit: null);
    if (result == null) return;
    await _run(
      () => ref.read(appDatabaseProvider).siteTeamDao.setMember(
          projectId: _pid, userId: picked.userId, role: result.role, approvalLimit: result.limit),
      done: tr('Added to the site team.'),
    );
  }

  Future<({String role, double? limit})?> _editSheet(TeamRules rules,
      {required String name, required String role, required double? limit}) {
    return showModalBottomSheet<({String role, double? limit})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _MemberSheet(name: name, role: role, limit: limit, roles: rules.rolesTheyCanGive),
    );
  }

  Future<void> _edit(TeamRules rules, ProjectMember m, TeamRoster roster) async {
    final result = await _editSheet(rules, name: _name(m.userId, roster), role: m.role, limit: m.approvalLimit);
    if (result == null) return;
    await _run(
      () => ref.read(appDatabaseProvider).siteTeamDao.setMember(
          projectId: _pid, userId: m.userId, role: result.role, approvalLimit: result.limit),
      done: tr('Saved.'),
    );
  }

  Future<void> _remove(ProjectMember m, TeamRoster roster) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Remove from this site?')),
        content: Text(trf('{name} will no longer be on this site\'s team.', {'name': _name(m.userId, roster)})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Remove'))),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => ref.read(appDatabaseProvider).siteTeamDao.removeMember(m.id), done: tr('Removed from the site team.'));
  }

  @override
  Widget build(BuildContext context) {
    final companyId = ref.watch(sessionProvider).activeCompany?.id ?? widget.project.companyId;
    final team = ref.watch(siteTeamProvider(_pid));
    final membersOnly = ref.watch(membersOnlyProvider(_pid)).value ?? false;
    final access = ref.watch(mySiteAccessProvider(_pid)).value;
    final roster = ref.watch(teamRosterProvider(companyId)).value ?? const TeamRoster(members: [], myUserId: null);
    final rules = access == null ? null : TeamRules(access);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('${tr('Site team')} · ${widget.project.name}')),
      floatingActionButton: rules?.canManageTeam == true && roster.members.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : () => _add(rules!, roster, team.value ?? const []),
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(tr('Add person')),
            )
          : null,
      body: team.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st, onRetry: () => ref.invalidate(siteTeamProvider(_pid))),
        data: (rows) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          children: [
            Card(
              child: SwitchListTile(
                value: membersOnly,
                onChanged: rules?.canSetMembersOnly == true && !_busy
                    ? (v) => _run(() => ref.read(appDatabaseProvider).siteTeamDao.setMembersOnly(_pid, v))
                    : null,
                title: Text(tr('Only this team sees the site')),
                subtitle: Text(membersOnly
                    ? tr('Hidden from the rest of the company. The company\'s owners and managers still see it.')
                    : tr('Everyone in the company sees this site.')),
              ),
            ),
            if (roster.members.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: FormMessage(tr('Turn on Team & sync to add people. The team list comes from the company\'s accounts.')),
              ),
            const SectionHeader('On this site'),
            if (rows.isEmpty)
              EmptyState(
                compact: true,
                icon: Icons.groups_outlined,
                title: tr('No one is listed yet'),
                message: tr('Everyone in the company works here with their company role. Add people to give them a site role or an approval limit.'),
              ),
            for (final m in rows)
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Icon(_roleIcon(m.role))),
                  title: Text(_name(m.userId, roster)),
                  subtitle: Text([
                    SiteRole.label(m.role),
                    if (m.role == SiteRole.projectManager)
                      m.approvalLimit == null
                          ? tr('No approval limit')
                          : trf('Approves up to {amount}', {'amount': rupees(m.approvalLimit!)}),
                    SiteRole.explain(m.role),
                  ].join(' · ')),
                  isThreeLine: true,
                  onTap: rules != null && rules.canChange(isSelf: _isSelf(m.userId, roster), role: m.role) && !_busy
                      ? () => _edit(rules, m, roster)
                      : null,
                  trailing: rules != null && rules.canRemove(isSelf: _isSelf(m.userId, roster), role: m.role)
                      ? IconButton(
                          tooltip: tr('Remove'),
                          icon: const Icon(Icons.person_remove_outlined),
                          onPressed: _busy ? null : () => _remove(m, roster),
                        )
                      : null,
                ),
              ),
            if (access != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
                child: Text(
                  trf('Your role here: {role}.', {'role': SiteRole.label(access.siteRole)}) +
                      (access.managesSite
                          ? ' ${access.approvalLimit == null ? tr('No approval limit') : trf('Approves up to {amount}', {'amount': rupees(access.approvalLimit!)})}.'
                          : ''),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static IconData _roleIcon(String role) => switch (role) {
        SiteRole.owner => Icons.workspace_premium_outlined,
        SiteRole.projectManager => Icons.manage_accounts_outlined,
        SiteRole.siteEngineer => Icons.engineering_outlined,
        SiteRole.accounts => Icons.account_balance_wallet_outlined,
        SiteRole.storekeeper => Icons.inventory_2_outlined,
        _ => Icons.visibility_outlined,
      };
}

class _MemberSheet extends StatefulWidget {
  const _MemberSheet({required this.name, required this.role, required this.limit, required this.roles});
  final String name;
  final String role;
  final double? limit;
  final List<String> roles;

  @override
  State<_MemberSheet> createState() => _MemberSheetState();
}

class _MemberSheetState extends State<_MemberSheet> {
  late String _role = widget.roles.contains(widget.role) ? widget.role : widget.roles.first;
  late final _limit = TextEditingController(text: widget.limit == null ? '' : widget.limit!.toStringAsFixed(0));
  String? _error;

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  void _save() {
    double? limit;
    if (_role == SiteRole.projectManager && _limit.text.trim().isNotEmpty) {
      limit = double.tryParse(_limit.text.trim().replaceAll(',', ''));
      if (limit == null || limit < 0) {
        setState(() => _error = tr('Enter the limit in rupees, or leave it empty for no limit.'));
        return;
      }
    }
    Navigator.pop(context, (role: _role, limit: limit));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _role,
              onChanged: (v) => setState(() => _role = v ?? _role),
              child: Column(children: [
                for (final r in widget.roles)
                  RadioListTile<String>(
                    value: r,
                    title: Text(SiteRole.label(r)),
                    subtitle: Text(SiteRole.explain(r)),
                    dense: true,
                  ),
              ]),
            ),
            if (_role == SiteRole.projectManager) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _limit,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: tr('Approval limit (₹)'),
                  helperText: tr('In the weekly close they approve items up to this. Leave empty for no limit.'),
                  errorText: _error,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: Text(tr('Save'))),
          ],
        ),
      ),
    );
  }
}
