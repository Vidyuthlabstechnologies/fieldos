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
import 'package:fieldos_mobile/features/project/site_day.dart';
import 'package:fieldos_mobile/features/shared/photo_capture.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/speech_service.dart';
import 'package:fieldos_mobile/services/translation_service.dart';
import 'package:fieldos_mobile/l10n/language.dart';

class DprDraftResult {
  const DprDraftResult({
    required this.date,
    required this.summary,
    required this.manpower,
    required this.weather,
    required this.issues,
    required this.photoPaths,
    this.taskProgress = const {},
  });

  final DateTime date;
  final String summary;
  final int manpower;
  final String? weather;

  /// Issue descriptions to raise, in English.
  final List<String> issues;
  final List<String> photoPaths;

  /// Task id to its new progress %, for the tasks moved forward today.
  final Map<String, int> taskProgress;
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

  /// Progress set on this report, by task id. Only moved tasks are kept.
  final _progress = <String, int>{};

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
            title: Text(trf('Download {language} translation?', {'language': _langName(lang!)})),
            content: Text(
              trf(
                  'This is a one-time download of about 30 MB. After that, {language} reports translate to '
                  'English on this phone, with no internet and no cost.',
                  {'language': _langName(lang)}),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Not now'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Download'))),
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
      helpText: tr('Which day is this report for?'),
    );
    if (picked != null) setState(() => _date = DateTime(picked.year, picked.month, picked.day, now.hour, now.minute));
  }

  Future<void> _addPhoto() async {
    final picked = await captureCameraFirstMany(context, prefix: 'dpr', place: widget.project.name);
    if (picked.isNotEmpty && mounted) setState(() => _photos.addAll(picked.map((f) => f.path)));
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
        taskProgress: Map.of(_progress),
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
        title: Text(heard != null ? tr('Check your report') : tr('New daily report')),
        actions: [TextButton(onPressed: _save, child: Text(tr('Save'), style: TextStyle(color: Colors.white)))],
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
                          ? trf('Heard in {language} by Sarvam. Check the words before saving.', {'language': _langName(heard)})
                          : trf('Heard in {language} on this phone. Check the words before saving.',
                              {'language': _langName(heard)}),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ]),
              ),
            _FromSiteRecords(
              projectId: widget.project.id,
              day: _date,
              summaryEmpty: _summary.text.trim().isEmpty,
              onUseLast: (text) {
                _summary.text = text;
                _read();
              },
              onUseWorkers: (n) => setState(() {
                _manpower.text = '$n';
                _manpowerTouched = true;
              }),
              onAddLine: (line) {
                final cur = _summary.text.trimRight();
                _summary.text = cur.isEmpty ? line : '$cur\n$line';
                _read();
              },
              summaryText: _summary.text,
            ),
            TextField(
              controller: _summary,
              minLines: 4,
              maxLines: 12,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: tr('Work done'),
                alignLabelWithHint: true,
                hintText: tr('What was done, how many people worked, the weather, any problems'),
              ),
            ),
            if (canTranslate || _original != null || _translating)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  if (_translating) ...[
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 10),
                    Text(tr('Translating on this phone…')),
                  ] else if (_original != null) ...[
                    const Icon(Icons.check_circle, size: 18, color: Brand.ok),
                    const SizedBox(width: 6),
                    Expanded(child: Text(trf('Translated from {language} on this phone', {'language': lang == null ? tr('the original') : _langName(lang)}))),
                    TextButton(onPressed: _undoTranslation, child: Text(tr('Show original'))),
                  ] else
                    OutlinedButton.icon(
                      onPressed: _translate,
                      icon: const Icon(Icons.translate),
                      label: Text(tr('Translate to English')),
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
                    decoration: InputDecoration(labelText: tr('People on site'), prefixIcon: Icon(Icons.groups_outlined)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _weather,
                    maxLength: 50,
                    onChanged: (_) => _weatherTouched = true,
                    decoration: InputDecoration(
                      labelText: tr('Weather'),
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
                title: Text(tr('Report for')),
                subtitle: Text('${fmtDay(_date)} · ${fmtDate(_date)}'),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: _pickDate,
              ),
            ),
            _TaskProgressSection(
              projectId: widget.project.id,
              values: _progress,
              onChanged: (id, v) => setState(() => _progress[id] = v),
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
                            tooltip: tr('Remove photo'),
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
                        Text(tr('Add photos'), style: theme.textTheme.labelSmall),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
            const SectionHeader('Problems to raise'),
            if (_issues.isEmpty)
              Text(tr('None found. FieldOS looks for delays, shortages, leaks, cracks, breakdowns, safety and payment '
                'problems as you write or speak, in English, Hindi and Telugu.'),
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
            FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: Text(tr('Save report'))),
          ],
        ),
      ),
    );
  }
}


/// "Progress today": each open task with a slider, so the report moves the
/// plan forward instead of the plan being updated separately.
class _TaskProgressSection extends ConsumerWidget {
  const _TaskProgressSection({required this.projectId, required this.values, required this.onChanged});

  final String projectId;
  final Map<String, int> values;
  final void Function(String taskId, int value) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(tasksProvider(projectId)).maybeWhen(
          data: (tasks) => tasks.where((t) => t.status != 'done').toList()
            ..sort((a, b) => (a.dueDate ?? DateTime(9999)).compareTo(b.dueDate ?? DateTime(9999))),
          orElse: () => const <Task>[],
        );
    if (open.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader('Progress today'),
      Text(tr('Move the tasks worked on today. 100% marks a task done.'),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      for (final t in open)
        Builder(builder: (context) {
          final v = values[t.id] ?? t.progress;
          final moved = values.containsKey(t.id) && values[t.id] != t.progress;
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis)),
                Text(moved ? '${t.progress}% → $v%' : '$v%',
                    style: theme.textTheme.labelLarge?.copyWith(color: moved ? theme.colorScheme.primary : null)),
              ]),
              Slider(
                value: v.toDouble(),
                max: 100,
                divisions: 20,
                label: '$v%',
                onChanged: (x) => onChanged(t.id, x.round()),
              ),
            ]),
          );
        }),
    ]);
  }
}


/// Suggestions from the site's own records for the report's day: start
/// from the last report, the headcount from attendance, and the material
/// that arrived. Each is one tap, and nothing is filled in without it.
class _FromSiteRecords extends ConsumerWidget {
  const _FromSiteRecords({
    required this.projectId,
    required this.day,
    required this.summaryEmpty,
    required this.summaryText,
    required this.onUseLast,
    required this.onUseWorkers,
    required this.onAddLine,
  });

  final String projectId;
  final DateTime day;
  final bool summaryEmpty;
  final String summaryText;
  final void Function(String text) onUseLast;
  final void Function(int workers) onUseWorkers;
  final void Function(String line) onAddLine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = summaryEmpty
        ? ref.watch(dprProvider(projectId)).maybeWhen(data: (l) => lastReportBefore(l, day), orElse: () => null)
        : null;
    final workers =
        ref.watch(attendanceProvider(projectId)).maybeWhen(data: (l) => workersOnDay(l, day), orElse: () => 0);
    final materials = materialsLine(
        ref.watch(receiptsProvider(projectId)).maybeWhen(data: (l) => materialsOnDay(l, day), orElse: () => const []));
    final showMaterials = materials.isNotEmpty && !summaryText.contains(materials);
    if (last == null && workers == 0 && !showMaterials) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(spacing: 8, runSpacing: 4, children: [
        if (last != null)
          ActionChip(
            avatar: const Icon(Icons.content_copy_outlined, size: 18),
            label: Text(trf('Copy last report ({day})', {'day': fmtDay(last.entryDate)})),
            onPressed: () => onUseLast(last.workSummary),
          ),
        if (workers > 0)
          ActionChip(
            avatar: const Icon(Icons.groups_outlined, size: 18),
            label: Text(workers == 1 ? '1 worker punched in' : '$workers workers punched in'),
            onPressed: () => onUseWorkers(workers),
          ),
        if (showMaterials)
          ActionChip(
            avatar: const Icon(Icons.local_shipping_outlined, size: 18),
            label: Text(tr('Add material received')),
            onPressed: () => onAddLine(materials),
          ),
      ]),
    );
  }
}

/// A language's name as the reader knows it: in English for the English
/// app, in its own script otherwise.
String _langName(SpeechLanguage l) => currentLanguage == AppLanguage.en ? l.englishName : l.name;
