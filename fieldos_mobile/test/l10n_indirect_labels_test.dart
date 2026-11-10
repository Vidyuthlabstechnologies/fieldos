/// Labels that reach tr() through a variable (a const list or map, a
/// trade, a weather word) are invisible to l10n_coverage_test's scan of
/// tr('...') calls. Each such list is checked here, so a new entry can't
/// quietly show in English to someone using the app in Telugu.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/agents/assistant_tools.dart';
import 'package:fieldos_mobile/features/attendance/staff_attendance.dart' show staffAttendanceStatusLabels;
import 'package:fieldos_mobile/features/chat/project_chat_view.dart';
import 'package:fieldos_mobile/features/crm/crm_rules.dart';
import 'package:fieldos_mobile/features/dashboard/my_dashboard.dart' show kpiLibrary;
import 'package:fieldos_mobile/features/inspections/inspections_screen.dart';
import 'package:fieldos_mobile/features/labour/day_register.dart';
import 'package:fieldos_mobile/features/money/money_book.dart';
import 'package:fieldos_mobile/features/money/money_view.dart';
import 'package:fieldos_mobile/features/payroll/payroll_rules.dart';
import 'package:fieldos_mobile/features/procurement/purchase_tools.dart';
import 'package:fieldos_mobile/features/project/dpr_draft_screen.dart';
import 'package:fieldos_mobile/features/reports/period_report.dart';
import 'package:fieldos_mobile/features/reports/report_library.dart';
import 'package:fieldos_mobile/features/reports/reports_library_screen.dart' show reportPeriodLabels;
import 'package:fieldos_mobile/features/subscription/paywall_screen.dart';
import 'package:fieldos_mobile/features/tasks/my_tasks_screen.dart';
import 'package:fieldos_mobile/features/warehouse/tools_rules.dart';
import 'package:fieldos_mobile/features/warehouse/warehouse_rules.dart';
import 'package:fieldos_mobile/data/app_database.dart' show staffSalaryCategory;
import 'package:fieldos_mobile/l10n/strings_hi.dart';
import 'package:fieldos_mobile/l10n/strings_kn.dart';
import 'package:fieldos_mobile/l10n/strings_mr.dart';
import 'package:fieldos_mobile/l10n/strings_ta.dart';
import 'package:fieldos_mobile/l10n/strings_te.dart';

String _cap(String s) => '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}';

void main() {
  final labels = <String, Iterable<String>>{
    'paywall benefits': [for (final (_, t) in paywallBenefits) t],
    'weather': weatherChoices,
    'staff attendance statuses': staffAttendanceStatusLabels.values,
    'lead stages': leadStageLabels.values,
    'lead sources': leadSourceLabels.values,
    'lead activities': activityKindLabels.values,
    'quote statuses': quoteStatusLabels.values,
    'lost reasons': lostReasonChoices,
    'follow-up choices': [for (final (_, l) in followUpChoices) l],
    'stock move statuses': moveStatusLabels.values,
    'count correction reasons': adjustReasonChoices,
    'tool states': toolStateLabels.values,
    'report groups': reportGroupLabels.values,
    'report library periods': reportPeriodLabels.values,
    'dashboard figures': [for (final k in kpiLibrary) k.title],
    'report titles': [for (final r in reportLibrary) r.title],
    'report descriptions': [for (final r in reportLibrary) r.about],
    'report columns': {
      for (final r in reportLibrary) ...r.build(ReportInput(sites: const [], from: DateTime(2026), to: DateTime(2027), now: DateTime(2026, 6))).headers,
    },
    'tool return conditions': returnConditionLabels.values,
    'professional tax states': ptStateLabels.values,
    'salary pay modes': [...payModes.values, staffSalaryCategory],
    'trades': commonTrades,
    'payment modes': paymentModes.values,
    'expense categories': {...defaultExpenseCategories, ...expenseCategories},
    'inspection item statuses': inspectionItemStatuses.values,
    'inspection types': [for (final t in inspectionTypes) if (t != 'mep') _cap(t)],
    'task groups': taskGroupTitles.values,
    'report periods': periodLabels.values,
    'chat report reasons': reportReasonLabels.values,
    'unit groups': [for (final g in unitGroups) g.label],
    'units': [for (final g in unitGroups) for (final u in g.units) u.label],
  };
  const tables = {
    'Hindi': stringsHi,
    'Telugu': stringsTe,
    'Tamil': stringsTa,
    'Kannada': stringsKn,
    'Marathi': stringsMr,
  };

  labels.forEach((what, keys) {
    test('$what are translated in every Indian language', () {
      tables.forEach((language, table) {
        final missing = [for (final k in keys) if ((table[k] ?? '').trim().isEmpty) k];
        expect(missing, isEmpty, reason: '$language is missing $what');
      });
    });
  });
}
