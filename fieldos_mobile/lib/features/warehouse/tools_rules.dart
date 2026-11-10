/// Tools register: where each tool is, who has it, what is overdue, and
/// what is to be recovered for damaged or lost tools.
library;

import 'package:fieldos_mobile/data/app_database.dart';

enum ToolState { available, issued, overdue, repair, lost, retired }

const toolStateLabels = {
  ToolState.available: 'In store',
  ToolState.issued: 'With someone',
  ToolState.overdue: 'Overdue',
  ToolState.repair: 'In repair',
  ToolState.lost: 'Lost',
  ToolState.retired: 'Retired',
};

const toolConditions = ['in_use', 'repair', 'retired'];
const returnConditions = ['ok', 'damaged', 'lost'];
const returnConditionLabels = {'ok': 'Fine', 'damaged': 'Damaged', 'lost': 'Lost'};

bool isOpenIssue(ToolIssue i) => i.returnedOn == null && i.returnCondition == null;

/// The issue a tool is out on, if any.
ToolIssue? openIssueOf(String toolId, Iterable<ToolIssue> issues) {
  for (final i in issues) {
    if (i.toolId == toolId && isOpenIssue(i)) return i;
  }
  return null;
}

/// The most recent issue of a tool, open or closed.
ToolIssue? lastIssueOf(String toolId, Iterable<ToolIssue> issues) {
  ToolIssue? last;
  for (final i in issues) {
    if (i.toolId != toolId) continue;
    if (last == null || i.issuedOn.isAfter(last.issuedOn) ||
        (i.issuedOn == last.issuedOn && i.createdAt.isAfter(last.createdAt))) {
      last = i;
    }
  }
  return last;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

ToolState toolState(Tool t, Iterable<ToolIssue> issues, DateTime now) {
  if (t.condition == 'retired') return ToolState.retired;
  final open = openIssueOf(t.id, issues);
  if (open != null) {
    final due = open.dueBack;
    return due != null && _day(due).isBefore(_day(now)) ? ToolState.overdue : ToolState.issued;
  }
  if (lastIssueOf(t.id, issues)?.returnCondition == 'lost') return ToolState.lost;
  if (t.condition == 'repair') return ToolState.repair;
  return ToolState.available;
}

/// Next asset tag: T-001, T-002 ... after the highest one in use.
String nextToolCode(Iterable<Tool> tools) {
  var max = 0;
  final re = RegExp(r'^T-(\d+)$');
  for (final t in tools) {
    final m = re.firstMatch(t.code ?? '');
    if (m != null) {
      final n = int.parse(m.group(1)!);
      if (n > max) max = n;
    }
  }
  return 'T-${(max + 1).toString().padLeft(3, '0')}';
}

/// Damaged or lost tools with money to recover, newest first.
List<ToolIssue> toRecover(Iterable<ToolIssue> issues) =>
    [for (final i in issues) if ((i.recoverAmount ?? 0) > 0) i]..sort((a, b) => b.issuedOn.compareTo(a.issuedOn));

typedef ToolCounts = ({int total, int out, int overdue, int lost, double value});

ToolCounts toolCounts(Iterable<Tool> tools, Iterable<ToolIssue> issues, DateTime now) {
  var out = 0, overdue = 0, lost = 0, total = 0;
  var value = 0.0;
  for (final t in tools) {
    final s = toolState(t, issues, now);
    if (s == ToolState.retired) continue;
    total++;
    if (s == ToolState.issued || s == ToolState.overdue) out++;
    if (s == ToolState.overdue) overdue++;
    if (s == ToolState.lost) {
      lost++;
    } else {
      value += t.value ?? 0;
    }
  }
  return (total: total, out: out, overdue: overdue, lost: lost, value: value);
}
