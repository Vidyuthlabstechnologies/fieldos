/// Agentic layer. FieldOS Mobile is built around small, composable *agents*
/// that each own a task and can be orchestrated. The first concrete agent is
/// [VoiceDprAgent] (voice -> structured DPR). The abstraction is intentionally
/// tiny: an agent exposes metadata and a single [run] that returns an
/// [AgentResult].
library;

/// Outcome of running an agent. `ok` signals success; `data` carries whatever
/// structured result the agent produced.
class AgentResult {
  const AgentResult({required this.ok, required this.message, this.data = const {}});
  final bool ok;
  final String message;
  final Map<String, dynamic> data;
}

/// A unit of capability an agent can invoke (e.g. transcribe, structure).
/// Kept as metadata today; agents call their dependencies directly, but this
/// is the seam future agents (planner, BOQ-import) will register tools into.
class AgentTool {
  const AgentTool({required this.name, required this.description});
  final String name;
  final String description;
}

abstract class Agent {
  String get name;
  String get description;
  List<AgentTool> get tools;
  Future<AgentResult> run(Map<String, dynamic> input);
}

/// Registry of agents the app currently ships. UI discovers agents here.
class AgentRegistry {
  AgentRegistry(this.agents);
  final List<Agent> agents;

  Agent? byName(String name) => agents.where((a) => a.name == name).firstOrNull;
}
