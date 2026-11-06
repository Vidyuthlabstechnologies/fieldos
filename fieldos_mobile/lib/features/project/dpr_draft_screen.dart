/// "Check the report": the DPR before it's saved, spoken or typed. As the
/// text changes, FieldOS reads it on the phone and fills in the headcount,
/// the weather and the problems worth raising, which the engineer confirms.
/// A report in Hindi, Telugu and so on can be translated to English here,
/// on the phone, for the PDF and the client.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/agents/dpr_intake.dart';
import 'package:fieldos_mobile/agents/site_report_parser.dart';
import 'package:fieldos_mobile/agents/voice_dpr_agent.dart';
import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/shared/photo_capture.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/speech_service.dart';
import 'package:fieldos_mobile/services/translation_service.dart';

class DprDraftResult {
  const DprDraftResult({
    required this.date,
    required this.summary,
    required this.manpower,
    required this.weather,
    required this.issues,
    required this.photoPaths,
  });

  final DateTime date;
  final String summary;
  final int manpower;
  final String? weather;

  /// Issue descriptions to raise, in English.
  final List<String> issues;
  final List<String> photoPaths;
}

/// Opens the draft screen; null when the person backs out.
Future<DprDraftResult?> openDprDraft(
  BuildContext context, {
  required Project project,
  String text = '',
  SpeechLanguage? spokenIn,
  bool viaSarvam = false,
}) =>
    Navigator.of(context).push<DprDraftResult>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => DprDraftScreen(project: project, initialText: text, spokenIn: spokenIn, viaSarvam: viaSarvam),
    ));

class DprDraftScreen extends ConsumerStatefulWidget {
  const DprDraftScreen({super.key, required this.project, this.initialText = '', this.spokenIn, this.viaSarvam = false});

  final Project project;
  final String initialText;

  /// Set when the report was spoken; shows where it came from.
  final SpeechLanguage? spokenIn;
  final bool viaSarvam;

  @override
  ConsumerState<DprDraftScreen> createState() => _DprDraftScreenState();
}

class _DprDraftScreenState extends ConsumerState<DprDraftScreen> {
  late final _summary = TextEditingController(text: tidySummary(widget.initialText));
  final _manpower = TextEditingController();
  final _weather = TextEditingController();
  bool _manpowerTouched = false;
  bool _weatherTouched = false;

  DateTime _date = DateTime.now();
  final _photos = <String>[];

  /// Issues found in the text, and the ones the person has unticked.
  Map<String, String> _issues = {};
  final _unticked = <String>{};

  /// Translation: the original text while the field shows English.
  String? _original;
  bool _translating = false;
  Timer? _debounce;

  SpeechLanguage? get _language => widget.spokenIn ?? _guessLanguage();

  @override
  void initState() {
    super.initState();
    _summary.addListener(_onTextChanged);
    _read(force: true);
  }

  /// A typed report in an Indian script: which language, for translation.
  SpeechLanguage? _guessLanguage() {
    final t = _summary.text;
    if (!isIndicScript(t)) return null;
    final r = t.runes.firstWhere((r) => r >= 0x0900 && r <= 0x0DFF, orElse: () => 0);
    if (r >= 0x0C00 && r < 0x0C80) return speechLanguageFor('te-IN');
    if (r >= 0x0B80 && r < 0x0C00) return speechLanguageFor('ta-IN');
    if (r >= 0x0C80 && r < 0x0D00) return speechLanguageFor('kn-IN');
    if (r >= 0x0980 && r < 0x0A00) return speechLanguageFor('bn-IN');
    if (r >= 0x0A80 && r < 0x0B00) return speechLanguageFor('gu-IN');
    if (r >= 0x0900 && r < 0x0980) return speechLanguageFor('hi-IN');
    return null;
  }

  void _onTextChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _read();
    });
  }

  /// Reads the report again: headcount and weather fill in unless the
  /// person typed their own, issues update.
  void _read({bool force = false}) {
    final readings = _original == null
        ? draftFromTranscript(_summary.text)
        : draftFromTranscript(_original!, english: _summary.text);
    setState(() {
      if (force || !_manpowerTouched) {
        final m = readings.manpower;
        _manpower.text = m == null ? '' : '$m';
      }
      if (force || !_weatherTouched) _weather.text = readings.weather ?? '';
      _issues = readings.issues;
    });
  }

  Future<void> _translate() async {
    final lang = _language;
    final code = lang?.translateCode;
    if (code == null) return;
    final translator = ref.read(translationServiceProvider);
    setState(() => _translating = true);
    try {
      if (!await translator.isReady(code)) {
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Download ${lang!.englishName} translation?'),
            content: Text(
              'This is a one-time download of about 30 MB. After that, ${lang.englishName} reports translate to '
              'English on this phone, with no internet and no cost.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Download')),
            ],
          ),
        );
        if (ok != true) return;
        await translator.download(code);
      }
      final source = _summary.text;
      final english = await translator.toEnglish(source, code);
      if (!mounted) return;
      _original = source;
      _summary.text = tidySummary(english);
      _read();
    } on TranslationException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (e, st) {
      if (mounted) showSnack(context, friendlyError(e, st), error: true);
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  void _undoTranslation() {
    final original = _original;
    if (original == null) return;
    _original = null;
    _summary.text = original;
    _read();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: now.subtract(const Duration(days: 60)),
      lastDate: now,
      helpText: 'Which day is this report for?',
    );
    if (picked != null) setState(() => _date = DateTime(picked.year, picked.month, picked.day, now.hour, now.minute));
  }

  Future<void> _addPhoto() async {
    final path = await captureCameraFirst(context, prefix: 'dpr', place: widget.project.name);
    if (path != null && mounted) setState(() => _photos.add(path));
  }

  void _save() {
    final summary = _summary.text.trim();
    if (summary.isEmpty) {
      showSnack(context, 'Write or speak what was done before saving.', error: true);
      return;
    }
    final manpower = int.tryParse(_manpower.text.trim()) ?? 0;
    final weather = _weather.text.trim();
    final issues = [
      for (final e in _issues.entries)
        if (!_unticked.contains(e.key)) _issueDescription(e.key, e.value),
    ];
    Navigator.pop(
      context,
      DprDraftResult(
        date: _date,
        summary: summary,
        manpower: manpower.clamp(0, 9999),
        weather: weather.isEmpty ? null : (weather.length > 50 ? weather.substring(0, 50) : weather),
        issues: issues,
        photoPaths: List.of(_photos),
      ),
    );
  }

  /// "Water ingress: “leak near the north wall”". The quote is left out
  /// when it's in an Indian script, which the PDF report can't print.
  String _issueDescription(String key, String evidence) {
    final label = issueLabel(key);
    if (evidence.isEmpty || isIndicScript(evidence) || evidence.runes.any((r) => r > 0xFF)) return label;
    return '$label: “$evidence”';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _summary.dispose();
    _manpower.dispose();
    _weather.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = _language;
    final canTranslate = _original == null && lang?.translateCode != null && isIndicScript(_summary.text);
    final heard = widget.spokenIn;
    return Scaffold(
      appBar: AppBar(
        title: Text(heard != null ? 'Check your report' : 'New daily report'),
        actions: [TextButton(onPressed: _save, child: const Text('Save', style: TextStyle(color: Colors.white)))],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (heard != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Icon(Icons.mic_none, size: 18, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.viaSarvam
                          ? 'Heard in ${heard.englishName} by Sarvam. Check the words before saving.'
                          : 'Heard in ${heard.englishName} on this phone. Check the words before saving.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ]),
              ),
            TextField(
              controller: _summary,
              minLines: 4,
              maxLines: 12,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Work done',
                alignLabelWithHint: true,
                hintText: 'What was done, how many people worked, the weather, any problems',
              ),
            ),
            if (canTranslate || _original != null || _translating)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  if (_translating) ...[
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 10),
                    const Text('Translating on this phone…'),
                  ] else if (_original != null) ...[
                    const Icon(Icons.check_circle, size: 18, color: Brand.ok),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Translated from ${lang?.englishName ?? 'the original'} on this phone')),
                    TextButton(onPressed: _undoTranslation, child: const Text('Show original')),
                  ] else
                    OutlinedButton.icon(
                      onPressed: _translate,
                      icon: const Icon(Icons.translate),
                      label: const Text('Translate to English'),
                    ),
                ]),
              ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _manpower,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                    onChanged: (_) => _manpowerTouched = true,
                    decoration: const InputDecoration(labelText: 'People on site', prefixIcon: Icon(Icons.groups_outlined)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _weather,
                    maxLength: 50,
                    onChanged: (_) => _weatherTouched = true,
                    decoration: const InputDecoration(
                      labelText: 'Weather',
                      prefixIcon: Icon(Icons.wb_cloudy_outlined),
                      counterText: '',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final w in const ['Sunny', 'Cloudy', 'Rain', 'Hot', 'Windy', 'Cold'])
                  ChoiceChip(
                    label: Text(w),
                    selected: _weather.text == w,
                    onSelected: (_) => setState(() {
                      _weather.text = w;
                      _weatherTouched = true;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.event_outlined),
                title: const Text('Report for'),
                subtitle: Text('${fmtDay(_date)} · ${fmtDate(_date)}'),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: _pickDate,
              ),
            ),
            const SectionHeader('Photos'),
            SizedBox(
              height: 92,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final p in _photos)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(File(p), width: 92, height: 92, fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(width: 92, height: 92, color: theme.colorScheme.surfaceContainer)),
                        ),
                        Positioned(
                          right: 2,
                          top: 2,
                          child: IconButton.filledTonal(
                            visualDensity: VisualDensity.compact,
                            iconSize: 16,
                            tooltip: 'Remove photo',
                            onPressed: () => setState(() => _photos.remove(p)),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ]),
                    ),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _addPhoto,
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.colorScheme.outline),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_a_photo_outlined, color: theme.colorScheme.primary),
                        const SizedBox(height: 4),
                        Text('Add photo', style: theme.textTheme.labelSmall),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
            const SectionHeader('Problems to raise'),
            if (_issues.isEmpty)
              Text(
                'None found. FieldOS looks for delays, shortages, leaks, cracks, breakdowns, safety and payment '
                'problems as you write or speak, in English, Hindi and Telugu.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              for (final e in _issues.entries)
                CheckboxListTile(
                  value: !_unticked.contains(e.key),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(issueLabel(e.key)),
                  subtitle: e.value.isEmpty ? null : Text('“${e.value}”', maxLines: 2, overflow: TextOverflow.ellipsis),
                  onChanged: (v) => setState(() => v == true ? _unticked.remove(e.key) : _unticked.add(e.key)),
                ),
            const SizedBox(height: 24),
            FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: const Text('Save report')),
          ],
        ),
      ),
    );
  }
}
