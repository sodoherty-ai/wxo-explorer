class_name WxODataModel


class AgentData:
	var id: String
	var name: String
	var display_name: String
	var description: String
	var instructions: String
	var style: String
	var guidelines: Array  # Array of Dictionaries {condition, action, tool, display_name}
	var tool_ids: Array
	var collaborator_ids: Array
	var knowledge_base_ids: Array
	var llm: String
	var raw: Dictionary  # Full API response for any extra fields

	static func from_dict(d: Dictionary) -> AgentData:
		var a = AgentData.new()
		a.raw = d
		a.id = d.get("id", "")
		a.name = d.get("name", "")
		a.display_name = d.get("display_name", a.name)
		a.description = d.get("description", "")
		a.instructions = d.get("instructions", "")
		a.style = d.get("style", "")
		a.llm = d.get("llm", "")
		a.guidelines = []
		for g in d.get("guidelines", []):
			if g is Dictionary:
				a.guidelines.append(g)
		a.tool_ids = []
		for t in d.get("tools", []):
			a.tool_ids.append(str(t))
		a.collaborator_ids = []
		for c in d.get("collaborators", []):
			a.collaborator_ids.append(str(c))
		a.knowledge_base_ids = []
		for k in d.get("knowledge_base", []):
			a.knowledge_base_ids.append(str(k))
		return a


class ToolData:
	var id: String
	var name: String
	var description: String
	var raw: Dictionary

	static func from_dict(d: Dictionary) -> ToolData:
		var t = ToolData.new()
		t.raw = d
		t.id = d.get("id", "")
		t.name = d.get("name", "")
		t.description = d.get("description", "")
		return t


class KnowledgeBaseData:
	var id: String
	var name: String
	var display_name: String
	var description: String
	var status: String
	var raw: Dictionary

	static func from_dict(d: Dictionary) -> KnowledgeBaseData:
		var kb = KnowledgeBaseData.new()
		kb.raw = d
		kb.id = d.get("id", "")
		kb.name = d.get("name", "")
		kb.display_name = d.get("display_name", kb.name)
		kb.description = d.get("description", "")
		var vi = d.get("vector_index", {})
		kb.status = vi.get("status", "unknown") if vi is Dictionary else "unknown"
		return kb


class GraphData:
	var agents: Dictionary = {}        # id -> AgentData
	var tools: Dictionary = {}          # id -> ToolData
	var knowledge_bases: Dictionary = {} # id -> KnowledgeBaseData

	func get_agent_display(id: String) -> String:
		if agents.has(id):
			return agents[id].display_name
		return id.left(8) + "..."

	func get_tool_display(id: String) -> String:
		if tools.has(id):
			return tools[id].name
		return id.left(8) + "..."

	func get_kb_display(id: String) -> String:
		if knowledge_bases.has(id):
			return knowledge_bases[id].display_name
		return id.left(8) + "..."
