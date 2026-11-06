/// Riverpod providers wiring the offline-first stack together.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/agents/agent.dart';
import 'package:fieldos_mobile/agents/cost_control_agent.dart';
import 'package:fieldos_mobile/agents/dpr_intake.dart';
import 'package:fieldos_mobile/agents/voice_dpr_agent.dart';
import 'package:fieldos_mobile/auth/auth_provider.dart';
import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/dashboard/project_cost_summary.dart';
import 'package:fieldos_mobile/services/billing_service.dart';
import 'package:fieldos_mobile/services/location_service.dart';
import 'package:fieldos_mobile/services/sarvam_service.dart';
import 'package:fieldos_mobile/services/settings_service.dart';
import 'package:fieldos_mobile/services/translation_service.dart';
import 'package:fieldos_mobile/services/voice_service.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final authServiceProvider = Provider<AuthService>((ref) => AuthService(ref.watch(appDatabaseProvider)));

final settingsServiceProvider =
    Provider<SettingsService>((ref) => SettingsService(ref.watch(appDatabaseProvider)));

final sarvamServiceProvider = Provider<SarvamService>((ref) => SarvamService());

/// A recorder for the Sarvam fallback; each voice sheet makes its own and
/// disposes it.
final voiceServiceFactoryProvider = Provider<VoiceService Function()>((ref) => VoiceService.new);

final translationServiceProvider = Provider<TranslationService>((ref) => TranslationService());

final voiceDprAgentProvider = Provider<VoiceDprAgent>(
  (ref) => VoiceDprAgent(
    sarvam: ref.watch(sarvamServiceProvider),
    settings: ref.watch(settingsServiceProvider),
  ),
);

final dprIntakeAgentProvider = Provider<DprIntakeAgent>((ref) => const DprIntakeAgent());

final costControlAgentProvider = Provider<CostControlAgent>((ref) => const CostControlAgent());

final agentRegistryProvider = Provider<AgentRegistry>(
  (ref) => AgentRegistry([
    ref.watch(voiceDprAgentProvider),
    ref.watch(dprIntakeAgentProvider),
    ref.watch(costControlAgentProvider),
  ]),
);

final locationServiceProvider = Provider<LocationService>((ref) => LocationService());

final billingServiceProvider = Provider<BillingService>((ref) => BillingService(ref.watch(appDatabaseProvider)));

final sessionProvider = StateNotifierProvider<SessionNotifier, SessionState>(
  (ref) => SessionNotifier(ref.watch(authServiceProvider), ref.watch(appDatabaseProvider)),
);

/// List providers, keyed by parent id, for the detail screens.
final projectsProvider =
    FutureProvider.autoDispose.family<List<Project>, String>((ref, companyId) {
  return ref.watch(appDatabaseProvider).projectDao.forCompany(companyId);
});

final tasksProvider = FutureProvider.autoDispose.family<List<Task>, String>((ref, projectId) {
  return ref.watch(appDatabaseProvider).taskDao.forProject(projectId);
});

final dprProvider = FutureProvider.autoDispose.family<List<DprEntry>, String>((ref, projectId) {
  return ref.watch(appDatabaseProvider).dprDao.forProject(projectId);
});

final issuesProvider =
    FutureProvider.autoDispose.family<List<Issue>, String>((ref, projectId) {
  return ref.watch(appDatabaseProvider).issueDao.forProject(projectId);
});

/// Cost-health summary for a single project (budget vs actuals via the agent).
final costSummaryProvider =
    FutureProvider.autoDispose.family<ProjectCostSummary, String>((ref, projectId) async {
  final db = ref.watch(appDatabaseProvider);
  final project = await db.projectDao.byId(projectId);
  if (project == null) {
    throw StateError('Project $projectId not found');
  }
  return ProjectCostSummary.forProject(db, project);
});

/// Pending approvals for one company's projects, oldest first (the Home
/// badge and the Approvals screen). Another company's approvals on the
/// same phone stay out of it.
final pendingApprovalsProvider =
    FutureProvider.autoDispose.family<List<Approval>, String>((ref, companyId) async {
  final db = ref.watch(appDatabaseProvider);
  final ids = {for (final p in await db.projectDao.forCompany(companyId)) p.id};
  final pending = await db.approvalDao.pendingFor(null);
  return [for (final a in pending) if (ids.contains(a.projectId)) a]
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
});

/// Procurement lists (the RFQ -> PO -> GRN chain).
final suppliersProvider = FutureProvider.autoDispose.family<List<Supplier>, String>(
    (ref, companyId) => ref.watch(appDatabaseProvider).supplierDao.forCompany(companyId));
final requestsProvider = FutureProvider.autoDispose.family<List<PurchaseRequest>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).purchaseDao.requestsFor(projectId));
final ordersProvider = FutureProvider.autoDispose.family<List<PurchaseOrder>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).purchaseDao.ordersFor(projectId));
final receiptsProvider = FutureProvider.autoDispose.family<List<MaterialReceipt>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).materialDao.forProject(projectId));

/// Labour attendance + GPS geofence for a project.
final attendanceProvider = FutureProvider.autoDispose.family<List<LabourAttendanceData>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).attendanceDao.forProject(projectId));
final geofenceProvider = FutureProvider.autoDispose.family<ProjectGeofence?, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).geofenceDao.effectiveFor(projectId));

/// Company subcontractor directory.
final subcontractorsProvider = FutureProvider.autoDispose.family<List<Subcontractor>, String>(
    (ref, companyId) => ref.watch(appDatabaseProvider).subcontractorDao.forCompany(companyId));

/// Equipment per project.
final equipmentProvider = FutureProvider.autoDispose.family<List<EquipmentData>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).equipmentDao.forProject(projectId));
final equipmentLogsProvider = FutureProvider.autoDispose.family<List<EquipmentLog>, String>(
    (ref, equipmentId) => ref.watch(appDatabaseProvider).equipmentDao.logsFor(equipmentId));

/// Inspections per project.
final inspectionsProvider = FutureProvider.autoDispose.family<List<Inspection>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).inspectionDao.forProject(projectId));
final inspectionItemsProvider = FutureProvider.autoDispose.family<List<InspectionItem>, String>(
    (ref, inspectionId) => ref.watch(appDatabaseProvider).inspectionDao.itemsFor(inspectionId));

/// Documents per project.
final documentsProvider = FutureProvider.autoDispose.family<List<Document>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).documentDao.forProject(projectId));

/// Workers per project.
final workersProvider = FutureProvider.autoDispose.family<List<Worker>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).workerDao.forProject(projectId));

/// Estimation / BOQ providers (existing EstimationDao, new providers).
final estimationsProvider = FutureProvider.autoDispose.family<List<Estimation>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).estimationDao.forProject(projectId));
final costHeadsProvider = FutureProvider.autoDispose.family<List<CostHead>, String>(
    (ref, estimationId) => ref.watch(appDatabaseProvider).estimationDao.costHeadsFor(estimationId));
final measurementEntriesProvider = FutureProvider.autoDispose.family<List<MeasurementEntry>, String>(
    (ref, costHeadId) => ref.watch(appDatabaseProvider).estimationDao.measurements(costHeadId));
final steelEntriesProvider = FutureProvider.autoDispose.family<List<SteelEntry>, String>(
    (ref, costHeadId) => ref.watch(appDatabaseProvider).estimationDao.steel(costHeadId));
