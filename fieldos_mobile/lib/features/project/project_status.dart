/// A project's stage in words, with the colour of its label. The values
/// are the ones the cloud accepts.
library;

import 'package:fieldos_mobile/core/ui.dart';

const projectStatuses = ['active', 'planning', 'on_hold', 'completed'];

String projectStatusLabel(String status) => switch (status) {
      'active' => 'Active',
      'planning' => 'Planning',
      'on_hold' => 'On hold',
      'completed' => 'Completed',
      _ => status,
    };

String projectStatusHint(String status) => switch (status) {
      'active' => 'Work is going on at the site',
      'planning' => 'Not started yet',
      'on_hold' => 'Work has stopped for now',
      'completed' => 'Handed over',
      _ => '',
    };

PillTone projectStatusTone(String status) => switch (status) {
      'active' => PillTone.ok,
      'on_hold' => PillTone.warn,
      _ => PillTone.neutral,
    };

/// Running sites first, finished ones last.
int projectStatusOrder(String status) {
  final i = projectStatuses.indexOf(status);
  return i < 0 ? projectStatuses.length : i;
}
