import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/settings_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final settings = ref.watch(settingsServiceProvider);

    if (!session.canManageSettings) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const Center(child: Text('Only a company owner can change settings.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _SarvamKeyField(settings: settings),
      ),
    );
  }
}

class _SarvamKeyField extends ConsumerStatefulWidget {
  const _SarvamKeyField({required this.settings});
  final SettingsService settings;

  @override
  ConsumerState<_SarvamKeyField> createState() => _SarvamKeyFieldState();
}

class _SarvamKeyFieldState extends ConsumerState<_SarvamKeyField> {
  final _key = TextEditingController();
  bool _saving = false;
  bool _configured = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    widget.settings.isVoiceConfigured().then((v) => mounted ? setState(() => _configured = v) : null);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.settings.setSarvamApiKey(_key.text.trim());
    _key.clear();
    final configured = await widget.settings.isVoiceConfigured();
    if (mounted) {
      setState(() {
        _saving = false;
        _configured = configured;
        _status = 'Saved. The key is stored locally and never shown again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Voice-to-DPR (Sarvam)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(_configured ? 'API key is configured.' : 'No API key configured — voice-to-DPR is disabled.'),
        const SizedBox(height: 12),
        TextField(
          controller: _key,
          decoration: const InputDecoration(
            labelText: 'Sarvam API key',
            border: OutlineInputBorder(),
            // Write-only: no value is ever echoed back here.
          ),
          obscureText: true,
          autocorrect: false,
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save key'),
        ),
        if (_status != null) ...[
          const SizedBox(height: 12),
          Text(_status!, style: const TextStyle(color: Colors.green)),
        ],
        const SizedBox(height: 24),
        const Text(
          'This is the only feature that uses the network. Everything else in '
          'FieldOS Mobile runs fully offline on this device.',
          style: TextStyle(color: Colors.grey),
        ),
      ],
    );
  }
}
