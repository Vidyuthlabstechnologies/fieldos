import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/core/branded_page.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/features/team/team_sync_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

/// Shown right after the first registration, when the user has no company
/// yet: create one (and own it), or join an employer's with its code.
class CompanySetupScreen extends ConsumerStatefulWidget {
  const CompanySetupScreen({super.key});

  @override
  ConsumerState<CompanySetupScreen> createState() => _CompanySetupScreenState();
}

class _CompanySetupScreenState extends ConsumerState<CompanySetupScreen> {
  final _name = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).createCompany(_name.text);
      // The app moves on to the home screen by itself once a company is set.
    } catch (e, st) {
      if (mounted) setState(() => _error = friendlyError(e, st));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(sessionProvider).user;
    final cloud = ref.watch(cloudSyncAvailableProvider);
    final firstName = (user?.name ?? '').trim().split(RegExp(r'\s+')).first;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return BrandedSheetPage(
      header: [
        SizedBox(height: BrandedSheetPage.isCompact(context) ? 16 : 32),
        const BrandMark(size: 64, onDark: true),
        const SizedBox(height: 10),
        Text(
          firstName.isEmpty ? 'Welcome to FieldOS' : 'Welcome, $firstName',
          style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 6),
        Text(
          'One more step before your first project.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.8)),
        ),
      ],
      sheet: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Set up your company', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('Your projects, team, labour and reports are kept under your company, and you are its owner.',
              style: muted),
          const SizedBox(height: 20),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.organizationName],
            maxLength: AuthService.maxCompanyNameLength,
            onSubmitted: (_) => _busy ? null : _create(),
            decoration: const InputDecoration(
              labelText: 'Company name',
              prefixIcon: Icon(Icons.apartment_outlined),
              helperText: 'For example Sri Sai Constructions',
              helperMaxLines: 2,
              counterText: '',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            FormMessage(_error!),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _create,
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Create company'),
          ),
          if (cloud) ...[
            const SizedBox(height: 28),
            Row(children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('or', style: muted),
              ),
              const Expanded(child: Divider()),
            ]),
            const SizedBox(height: 20),
            Text("Working for someone else's company?", style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('Ask the owner for the join code. You will see their projects once you join.', style: muted),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Join with a code'),
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamSyncScreen())),
            ),
          ],
          const SizedBox(height: 24),
          TextButton(
            onPressed: _busy ? null : () => ref.read(sessionProvider.notifier).logout(),
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.onSurfaceVariant),
            child: Text(user == null ? 'Log out' : 'Not ${user.name}? Log out'),
          ),
          const SizedBox(height: 8),
          Text(
            'Need help? ${Brand.supportEmail}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
