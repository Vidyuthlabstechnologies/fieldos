/// Stores and tools: cement bought into the yard at two rates is sent to a
/// site, arrives two bags short, and the site's stock and cost pick it up
/// only once counted; leftover steel goes on to another site; a store
/// cannot send what it does not hold. A drill is handed over, goes overdue,
/// comes back damaged and goes for repair; a level is lost and its value is
/// to be recovered. Every write waits in the outbox for the server.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/procurement/site_stock.dart';
import 'package:fieldos_mobile/features/warehouse/tools_rules.dart';
import 'package:fieldos_mobile/features/warehouse/warehouse_rules.dart';
import 'package:fieldos_mobile/sync/sync_mappers.dart';

void main() {
  late AppDatabase db;
  late WarehouseDao dao;
  late Company company;
  late Store yard;
  const pm = 'pm-1';
  const engineer = 'eng-1';

  Future<Project> site(String id, String name) => db.projectDao
      .create(ProjectsCompanion.insert(id: id, companyId: company.id, name: name, status: const Value('active')));

  setUp(() async {
    db = AppDatabase.memory();
    dao = db.warehouseDao;
    company = await db.companyDao.create('Sai Constructions');
    yard = await dao.addStore(companyId: company.id, name: 'Main yard', by: pm, location: 'Kompally');
    await site('p-1', 'Narapally');
    await site('p-2', 'Vidyanagar');
  });
  tearDown(() => db.close());

  Future<List<String>> outbox(String table) async =>
      [for (final e in await db.syncOutboxDao.pending()) if (e.targetTable == table) e.operation];

  test('material bought into a store is valued at its average rate', () async {
    await dao.addMove(
        companyId: company.id, kind: 'inward', materialName: 'Cement', unit: 'bags', quantity: 100, rate: 380,
        toStoreId: yard.id, supplierName: 'Balaji Traders', by: pm);
    await dao.addMove(
        companyId: company.id, kind: 'inward', materialName: ' cement ', unit: 'bags', quantity: 100, rate: 400,
        toStoreId: yard.id, by: pm);
    final lines = storeStock(await dao.movesFor(company.id), yard.id);
    expect(lines, hasLength(1));
    expect(lines.single.balance, 200);
    expect(lines.single.avgRate, 390);
    expect(lines.single.value, 78000);
    expect(await outbox('stores'), ['insert']);
    expect(await outbox('stock_moves'), ['insert', 'insert']);
  });

  test('a transfer counts at the site only once received, and a short count is kept', () async {
    await dao.addMove(
        companyId: company.id, kind: 'inward', materialName: 'Cement', unit: 'bags', quantity: 100, rate: 390,
        toStoreId: yard.id, by: pm);
    final sent = await dao.addMove(
        companyId: company.id, kind: 'transfer', materialName: 'Cement', unit: 'bags', quantity: 50,
        fromStoreId: yard.id, toProjectId: 'p-1', vehicle: 'TS09 AB 1234', by: pm);
    expect(sent.status, 'in_transit');
    expect(sent.rate, 390, reason: 'priced at the store average when no rate is given');

    var moves = await dao.movesFor(company.id);
    expect(storeBalance(moves, yard.id, 'Cement', 'bags'), 50, reason: 'it left the store when sent');
    var stock = buildSiteStock(const [], const [], moves: await dao.movesForSite('p-1'), projectId: 'p-1');
    expect(stock, isEmpty, reason: 'nothing at the site while it is on the lorry');
    expect(onTheWayTo(moves, projectId: 'p-1').single.id, sent.id);

    final got = await dao.receive(sent.id, by: engineer, arrived: 48, note: '2 bags torn');
    expect(got.status, 'received');
    expect(got.receivedBy, engineer);
    expect(shortage(got), 2);
    expect(got.note, '2 bags torn');

    moves = await dao.movesFor(company.id);
    stock = buildSiteStock(const [], const [], moves: await dao.movesForSite('p-1'), projectId: 'p-1');
    expect(stock.single.transferredIn, 48);
    expect(stock.single.balance, 48);
    expect(siteTransferValue(moves, 'p-1'), 48 * 390);
    expect(onTheWayTo(moves, projectId: 'p-1'), isEmpty);
    await expectLater(dao.receive(sent.id, by: engineer), throwsArgumentError);
    expect(await outbox('stock_moves'), ['insert', 'insert', 'update']);
  });

  test('site stock adds transfers in and takes transfers out, next to receipts and use', () async {
    await db.materialDao.createReceipt(MaterialReceiptsCompanion.insert(
        id: 'r-1', projectId: 'p-1', materialName: 'Steel 12mm', quantity: 2000, unit: const Value('kg'), amount: 140000,
        receivedBy: pm, receivedOn: DateTime(2026, 11, 1)));
    await db.materialDao.recordUsage(MaterialUsageCompanion.insert(
        id: 'u-1', projectId: 'p-1', materialName: 'Steel 12mm', quantity: 1500, unit: const Value('kg'), recordedBy: pm,
        usedOn: DateTime(2026, 11, 5)));
    final leftover = await dao.addMove(
        companyId: company.id, kind: 'transfer', materialName: 'Steel 12mm', unit: 'kg', quantity: 400, rate: 70,
        fromProjectId: 'p-1', toProjectId: 'p-2', by: engineer);
    await dao.receive(leftover.id, by: 'eng-2');

    Future<StockLine> line(String p) async => buildSiteStock(
            await db.materialDao.forProject(p), await db.materialDao.usageForProject(p),
            moves: await dao.movesForSite(p), projectId: p)
        .single;
    final from = await line('p-1');
    expect(from.transferredOut, 400);
    expect(from.balance, 100);
    final to = await line('p-2');
    expect(to.transferredIn, 400);
    expect(to.balance, 400);
    final moves = await dao.movesFor(company.id);
    expect(siteTransferValue(moves, 'p-1'), -28000);
    expect(siteTransferValue(moves, 'p-2'), 28000);
  });

  test('a store cannot send more than it holds, and a recalled transfer goes back', () async {
    await dao.addMove(
        companyId: company.id, kind: 'inward', materialName: 'Sand', unit: 'cft', quantity: 300, rate: 60,
        toStoreId: yard.id, by: pm);
    await expectLater(
        dao.addMove(
            companyId: company.id, kind: 'transfer', materialName: 'Sand', unit: 'cft', quantity: 301,
            fromStoreId: yard.id, toProjectId: 'p-1', by: pm),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('300'))));
    final m = await dao.addMove(
        companyId: company.id, kind: 'transfer', materialName: 'Sand', unit: 'cft', quantity: 200,
        fromStoreId: yard.id, toProjectId: 'p-1', by: pm);
    expect(storeBalance(await dao.movesFor(company.id), yard.id, 'Sand', 'cft'), 100);
    await dao.cancelMove(m.id, reason: 'Wrong site');
    final moves = await dao.movesFor(company.id);
    expect(storeBalance(moves, yard.id, 'Sand', 'cft'), 300);
    expect(onTheWayTo(moves, projectId: 'p-1'), isEmpty);
    expect((await dao.moveById(m.id))!.note, 'Wrong site');
    await expectLater(dao.cancelMove(m.id), throwsArgumentError);
  });

  test('count corrections need a reason and change only the store', () async {
    await dao.addMove(
        companyId: company.id, kind: 'inward', materialName: 'Cement', unit: 'bags', quantity: 20, rate: 380,
        toStoreId: yard.id, by: pm);
    await expectLater(
        dao.addMove(
            companyId: company.id, kind: 'adjust', materialName: 'Cement', unit: 'bags', quantity: 3,
            fromStoreId: yard.id, by: pm),
        throwsArgumentError);
    await dao.addMove(
        companyId: company.id, kind: 'adjust', materialName: 'Cement', unit: 'bags', quantity: 3,
        fromStoreId: yard.id, note: 'Damaged', by: pm);
    expect(storeBalance(await dao.movesFor(company.id), yard.id, 'Cement', 'bags'), 17);
  });

  test('a move is checked before it is saved', () {
    String? check({String kind = 'transfer', String? fs, String? fp, String? ts, String? tp, double q = 1, String? note}) =>
        checkMove(
            kind: kind, fromStoreId: fs, fromProjectId: fp, toStoreId: ts, toProjectId: tp, materialName: 'Cement',
            quantity: q, note: note);
    expect(check(fs: 's', tp: 'p'), isNull);
    expect(check(fp: 'p', tp: 'p'), 'Pick two different places.');
    expect(check(fs: 's'), 'Pick where it goes from and to.');
    expect(check(fs: 's', fp: 'p', tp: 'q'), 'A move leaves one place.');
    expect(check(kind: 'inward', tp: 'p'), 'Material bought comes into a store.');
    expect(check(kind: 'inward', ts: 's'), isNull);
    expect(check(kind: 'adjust', fs: 's'), 'Say why the count changed.');
    expect(check(kind: 'adjust', fp: 'p', note: 'x'), 'Count corrections are for stores.');
    expect(check(fs: 's', tp: 'p', q: 0), 'Enter a quantity more than zero.');
  });

  test('a tool goes out, goes overdue, comes back damaged for repair, and is handed over again once repaired', () async {
    final drill = await dao.addTool(companyId: company.id, name: 'Drill machine', value: 6500, storeId: yard.id, by: pm);
    final level = await dao.addTool(companyId: company.id, name: 'Auto level', value: 18000, by: pm);
    expect(drill.code, 'T-001');
    expect(level.code, 'T-002');

    final out = await dao.issueTool(
        toolId: drill.id, issuedTo: 'Ravi (mason)', projectId: 'p-1', dueBack: DateTime(2026, 11, 8), by: engineer,
        on: DateTime(2026, 11, 1));
    final issues = await dao.issuesFor(company.id);
    final tools = await dao.toolsFor(company.id);
    expect(toolState(drill, issues, DateTime(2026, 11, 8)), ToolState.issued);
    expect(toolState(drill, issues, DateTime(2026, 11, 9)), ToolState.overdue);
    final c = toolCounts(tools, issues, DateTime(2026, 11, 9));
    expect(c.out, 1);
    expect(c.overdue, 1);
    expect(c.value, 24500);
    await expectLater(dao.issueTool(toolId: drill.id, issuedTo: 'Someone else', by: pm), throwsArgumentError);

    await dao.returnTool(out.id, condition: 'damaged', recoverAmount: 800, note: 'Chuck broken');
    final repaired = (await dao.toolById(drill.id))!;
    expect(repaired.condition, 'repair');
    expect(toolState(repaired, await dao.issuesFor(company.id), DateTime(2026, 11, 10)), ToolState.repair);
    expect(toRecover(await dao.issuesFor(company.id)).single.recoverAmount, 800);
    await expectLater(dao.returnTool(out.id, condition: 'ok'), throwsArgumentError);
    expect(await outbox('tools'), ['insert', 'insert'], reason: 'the server marks it for repair itself');

    await dao.updateTool(drill.id, name: drill.name, code: drill.code, value: drill.value, condition: 'in_use');
    await dao.issueTool(toolId: drill.id, issuedTo: 'Suresh', by: pm);
    expect(toolState((await dao.toolById(drill.id))!, await dao.issuesFor(company.id), DateTime.now()), ToolState.issued);
  });

  test('a lost tool stays lost, is not issued again, and drops out of the worth', () async {
    final level = await dao.addTool(companyId: company.id, name: 'Auto level', value: 18000, by: pm);
    final out = await dao.issueTool(toolId: level.id, issuedTo: 'Prakash', by: pm);
    await dao.returnTool(out.id, condition: 'lost', recoverAmount: 18000);
    final issues = await dao.issuesFor(company.id);
    expect(issues.single.returnedOn, isNull);
    expect(toolState(level, issues, DateTime.now()), ToolState.lost);
    expect(toolCounts([level], issues, DateTime.now()).value, 0);
    await expectLater(dao.issueTool(toolId: level.id, issuedTo: 'Prakash', by: pm), throwsArgumentError);
    expect(nextToolCode([level]), 'T-002');
  });

  test('stores, moves and tool issues round-trip through the server format', () async {
    await dao.addMove(
        companyId: company.id, kind: 'inward', materialName: 'Cement', unit: 'bags', quantity: 10, rate: 380,
        toStoreId: yard.id, by: pm);
    final m = await dao.addMove(
        companyId: company.id, kind: 'transfer', materialName: 'Cement', unit: 'bags', quantity: 10,
        fromStoreId: yard.id, toProjectId: 'p-1', by: pm);
    final json = jsonDecode(jsonEncode(stockMoveToSupabaseJson(m))) as Map<String, dynamic>;
    expect(json['status'], 'in_transit');
    expect(json['to_project_id'], 'p-1');
    final back = stockMoveFromSupabaseJson(json);
    expect(back.quantity.value, 10);
    expect(back.rate.value, 380);
    expect(back.sentOn.value.isAtSameMomentAs(m.sentOn), isTrue);

    final tool = await dao.addTool(companyId: company.id, name: 'Vibrator', by: pm);
    final i = await dao.issueTool(toolId: tool.id, issuedTo: 'Ravi', dueBack: DateTime(2026, 11, 20), by: pm);
    final ij = jsonDecode(jsonEncode(toolIssueToSupabaseJson(i))) as Map<String, dynamic>;
    expect(toolIssueFromSupabaseJson(ij).issuedTo.value, 'Ravi');
    expect(storeFromSupabaseJson(jsonDecode(jsonEncode(storeToSupabaseJson(yard))) as Map<String, dynamic>).name.value,
        'Main yard');
  });
}
