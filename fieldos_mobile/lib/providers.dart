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
import 'package:fieldos_mobile/services/sarvam_service.dart';
import 'package:fieldos_mobile/services/settings_service.dart';
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

final voiceServiceProvider = Provider<VoiceService>((ref) => VoiceService());

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

/// Company-wide pending approvals (the multi-level approvals queue).
final pendingApprovalsProvider =
    FutureProvider.autoDispose<List<Approval>>((ref) {
  return ref.watch(appDatabaseProvider).approvalDao.pendingFor(null);
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
    (ref, projectId) => ref.watch(appDatabaseProvider).geofenceDao.forProject(projectId));

/// Company subcontractor directory.
final subcontractorsProvider = FutureProvider.autoDispose.family<List<Subcontractor>, String>(
    (ref, companyId) => ref.watch(appDatabaseProvider).subcontractorDao.forCompany(companyId));
