/// The stage-by-stage breakdown of a building's structure, so a site
/// tracks "Columns: Shuttering" and "Slab: Casting" instead of one line
/// called "RCC work". Each step becomes a task that needs an on-site check
/// before it can be marked 100%. Dressing is its own activity and always
/// takes at least a day.
library;

import 'package:fieldos_mobile/l10n/language.dart';

class ActivityStage {
  const ActivityStage(this.id, this.title, this.steps, {this.minDays = 0});
  final String id;
  final String title;
  final List<String> steps;

  /// Days from the start to the due date of each step; 0 leaves no due date.
  final int minDays;
}

const _slabSteps = [
  'Shuttering and centering',
  'Beam and slab steel',
  'Electrical and plumbing conduits',
  'Level check',
  'Casting',
  'De-shuttering',
  'Curing',
];

const activityStages = [
  ActivityStage('footings', 'Footings', [
    'Excavation',
    'PCC (lean concrete)',
    'Footing steel binding',
    'Footing shuttering',
    'Level check',
    'Casting',
    'Curing',
  ]),
  ActivityStage('plinth', 'Plinth beam', ['Shuttering', 'Steel binding', 'Level check', 'Casting', 'De-shuttering', 'Curing']),
  ActivityStage('columns', 'Columns', [
    'Steel overlapping and binding',
    'Shuttering',
    'Level check',
    'Shear key procedure',
    'Casting',
    'De-shuttering',
    'Curing',
    'Shuttering oil application',
  ]),
  ActivityStage('slab1', 'First slab', [..._slabSteps, 'Columns of the next floor', 'Beams of the next floor']),
  ActivityStage('slab2', 'Second slab', [..._slabSteps, 'Columns of the next floor', 'Beams of the next floor']),
  ActivityStage('dressing', 'Dressing', ['Dressing'], minDays: 1),
];

/// The task title for one step: "Columns: Shuttering". The stage and step
/// are translated into the language the person uses.
String activityTaskTitle(ActivityStage stage, String step) {
  // Dressing is one step with the stage's own name.
  if (stage.steps.length == 1 && stage.steps.first == stage.title) return tr(stage.title);
  return '${tr(stage.title)}: ${tr(step)}';
}

ActivityStage? stageById(String id) {
  for (final s in activityStages) {
    if (s.id == id) return s;
  }
  return null;
}

/// Metres from the site's centre within which a person counts as on site
/// when the site has no radius of its own.
const defaultSiteRadiusM = 150.0;
