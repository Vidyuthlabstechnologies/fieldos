/// The audit trail lists every decision and change of money in time order,
/// with who did it, and leaves money-in out for those who don't see it.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/approvals/approval_chain.dart';
import 'package:fieldos_mobile/features/export/audit_trail.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  test('records, cancellations, signatures and payments, oldest first', () async {
    final company = await db.companyDao.create('Sai Constructions');
    final site = await db.projectDao.create(
        ProjectsCompanion.insert(id: 'site-1', companyId: company.id, name: 'Kompally, "A" block', status: const Value('active')));
    await db.approvalChainDao.setRule(company.id, kind: ApprovalKind.expense, role: ApprovalLevel.owner, above: 1000, by: 'owner');
    final t = DateTime.now();
    await db.expenseDao.create(SiteExpensesCompanion.insert(
        id: 'e1', projectId: site.id, category: 'Material', amount: 5000, incurredOn: '2026-11-03', recordedBy: 'sup',
        paidTo: const Value('Balaji, Hardware')));
    await db.approvalChainDao.sign(
        projectId: site.id, kind: ApprovalKind.expense, itemId: 'e1', level: ApprovalLevel.owner, approve: false, amount: 5000, by: 'owner', note: 'not ours');
    await db.expenseDao.setVoided('e1', voided: true, reason: 'rejected by owner', by: 'owner', now: t.add(const Duration(hours: 1)));
    await db.paymentDao.create(PaymentsReceivedCompanion.insert(
        id: 'p1', projectId: site.id, amount: 50000, receivedOn: t, fromParty: 'Client', mode: 'bank', recordedBy: 'owner',
        createdAt: Value(t.add(const Duration(hours: 2)))));

    final all = await buildAuditTrail(db, company.id);
    expect(all.map((e) => e.action), contains('Approval rule set'));
    expect([for (final e in all) if (e.action != 'Approval rule set') e.action], [
      'Expense recorded',
      'Rejected as owner (expense)',
      'Expense cancelled',
      'Payment received',
    ]);
    expect(all.firstWhere((e) => e.action == 'Expense cancelled').note, 'rejected by owner');
    expect((await buildAuditTrail(db, company.id, moneyIn: false)).map((e) => e.action), isNot(contains('Payment received')));

    final csv = auditCsv(all, nameOf: (id) => id == 'owner' ? 'Ravi (owner)' : id, siteName: {site.id: site.name});
    final lines = csv.trim().split('\n');
    expect(lines.first, 'When,Site,Who,What,Item,Amount (₹),Note,Record');
    expect(csv, contains(',"Kompally, ""A"" block",sup,Expense recorded,"Material to Balaji, Hardware",5000.00,,e1'));
    expect(csv, contains('Ravi (owner),Rejected as owner (expense),,5000.00,not ours,e1'),
        reason: 'the step carries the amount');
  });
}
