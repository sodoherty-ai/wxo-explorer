# wxo-explorer

A Godot 4.6 application that visualizes a watsonx Orchestrate environment as a 3D network graph showing agents, knowledge bases, and tools with their relationships.

## Project Conventions

- **Engine**: Godot 4.6 stable
- **Language**: GDScript only (no C#, no plugins requiring compilation)
- **Style**: Follow GDScript style guide (snake_case for variables/functions, PascalCase for classes/nodes)
- **Approach**: Incremental - stop at each major step for user review before proceeding

## wxO Documentation

- MCP doc server configured in `.mcp.json` - use `SearchIbmWatsonxOrchestrateAdk` tool to look up API details
- wxO Developer Edition OpenAPI docs: `http://localhost:4321/docs`

## Architecture Overview

```
wxo-explorer/
├── project.godot
├── CLAUDE.md
├── .mcp.json
├── scenes/
│   ├── main.tscn                  # Root scene - manages screen transitions
│   ├── screens/
│   │   ├── intro_screen.tscn      # 2D intro/settings screen (entry point)
│   │   ├── loading_screen.tscn    # 2D loading/debug screen (data fetch)
│   │   └── graph_screen.tscn      # 3D graph exploration screen
│   ├── ui/
│   │   └── node_detail_panel.tscn # Info panel when clicking a node (overlay on 3D)
│   └── graph/
│       ├── agent_node.tscn        # 3D representation of an agent
│       ├── tool_node.tscn         # 3D representation of a tool
│       └── knowledge_node.tscn    # 3D representation of a knowledge base
├── scripts/
│   ├── main.gd                    # Scene manager - handles screen transitions
│   ├── config_data.gd             # ConfigData resource (server URL, auth, save/load)
│   ├── screens/
│   │   ├── intro_screen.gd        # Intro screen: server config, auth, connect, enter
│   │   ├── loading_screen.gd      # Loading screen: fetches data, shows debug log
│   │   └── graph_screen.gd        # Graph screen: orchestrates 3D view + HUD
│   ├── api/
│   │   ├── wxo_client.gd          # HTTP client for wxO REST API
│   │   └── wxo_data_model.gd      # Data classes for agents, tools, knowledge
│   ├── graph/
│   │   ├── graph_manager.gd       # Builds and manages the 3D graph
│   │   ├── graph_node_base.gd     # Base class for all graph nodes
│   │   ├── graph_edge.gd          # Edge/connection line between nodes
│   │   └── graph_layout.gd        # Force-directed layout algorithm
│   ├── camera/
│   │   └── camera_controller.gd   # Dual-mode camera (orbit + free-fly)
│   └── ui/
│       └── node_detail_panel.gd   # Detail panel UI logic
└── resources/
	└── config.tres                # Saved settings (server URL, etc.)
```

## Authentication

Two auth modes supported:
- **Local (Bearer Token)**: For wxO Developer Edition running locally. Token can be auto-filled from `~/.cache/orchestrate/credentials.yaml` (reads `wxo_mcsp_token` field).
- **SaaS (API Key)**: For cloud wxO instances. User provides their API key manually.

Both are sent as `Authorization: Bearer <token/key>` header.

## wxO REST API Reference

All endpoints use Bearer token auth: `Authorization: Bearer <token>`

**Base URL (local dev):** `http://localhost:4321/api`

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/v1/orchestrate/agents` | GET | List all agents (returns full objects with tool/collab/kb ID arrays) |
| `/v1/orchestrate/agents/{id}` | GET | Get a specific agent by ID |
| `/v1/tools` | GET | List all tools (name, description, input/output schema) |
| `/v1/tools/{id}` | GET | Get a specific tool by ID |
| `/v1/orchestrate/knowledge-bases` | GET | List all knowledge bases (name, description, vector_index status) |
| `/v1/orchestrate/knowledge-bases/{kb_id}/status` | GET | Get knowledge base status |

**Agent object** has `tools[]`, `collaborators[]`, `knowledge_base[]` as arrays of UUID strings referencing other entities.

## Visual Design

| Entity | 3D Shape | Color |
|--------|----------|-------|
| Agent | Sphere | Blue (#4A90D9) |
| Tool | Cube | Green (#50C878) |
| Knowledge Base | Cylinder | Orange (#E8943A) |
| Edge (relationship) | Line/tube | White with slight glow |

## App Flow

```
[App Launch]
	 │
	 ▼
[Intro Screen (2D)]
 - Server URL, auth mode, credentials
 - "Test Connection" / "Enter" buttons
	 │
	 ▼ (on "Enter")
[Loading Screen (2D)]
 - Fires parallel API requests (agents + tools + KBs)
 - Shows debug log with request URLs, HTTP status, parse results
 - Lists all fetched entities
 - Auto-transitions to graph after 2 seconds
 - "Back" button shown on error
	 │
	 ▼ (on success)
[Graph Screen (3D)]
 - Receives GraphData from loading screen
 - Renders 3D network graph
 - Camera controls (orbit / free-fly, Tab to toggle)
 - HUD: Back button, mode label, controls help text
 - Click nodes for detail panel overlay
 - "Back" button / Escape → returns to Intro Screen
```

## Camera Controls

**Orbit mode (default):**
- Left-drag or middle-drag: rotate around focal point
- Right-drag: pan focal point
- WASD / Arrow keys: pan focal point (keyboard)
- Scroll wheel: zoom in/out
- Tab: switch to free-fly
- Gamepad: Left stick pan, Right stick orbit, Triggers zoom, Triangle toggle mode

**Free-fly mode:**
- WASD / Arrow keys: move (always active)
- Hold right-click: capture mouse for mouse look
- Space/Shift: move up/down
- Scroll wheel: adjust speed
- Tab: switch to orbit
- Escape: release mouse (second Escape returns to intro)
- Gamepad: Left stick move, Right stick look, Triggers up/down, Triangle toggle mode

## Implementation Phases

### Phase 1: Project Skeleton + Intro Screen ✅
- Godot project initialized (1280x720 viewport, 2x window override, forward+ renderer)
- `main.tscn` root scene manages screen transitions (instantiate/free)
- `intro_screen.tscn` 2D centered panel with:
  - Server URL input (default: `http://localhost:4321`)
  - Auth mode dropdown: Local (Bearer Token) / SaaS (API Key)
  - Bearer token field + auto-fill from `~/.cache/orchestrate/credentials.yaml`
  - API key field (hidden when Local mode selected)
  - Test Connection + Enter buttons, status label
- `graph_screen.tscn` 3D scene (camera + directional light + ground plane + HUD)
- Screen transitions: Enter → Graph, Back/Escape → Intro
- `ConfigData` resource class saves/loads all settings to `user://config.tres`

### Phase 2: Camera Controller ✅
- `camera_controller.gd` on Camera3D in graph screen
- Orbit mode: left/mid-drag orbit, right-drag pan, WASD/arrows pan, scroll zoom
- Free-fly mode: WASD/arrows move always, right-click for mouse look, Space/Shift up/down
- PS5/gamepad: left stick move/pan, right stick look/orbit, triggers zoom/up-down, Triangle toggle
- Tab toggles between modes
- HUD displays current mode name + control hints
- Escape releases captured mouse before propagating to back handler

### Phase 3: API Client ✅
- `wxo_data_model.gd`: AgentData, ToolData, KnowledgeBaseData, GraphData classes
  - Parse from JSON dicts, agent has tool_ids/collaborator_ids/knowledge_base_ids
- `wxo_client.gd`: HTTPRequest-based async client
  - `configure(config)` sets base URL + auth header from ConfigData
  - `test_connection()` hits `/v1/orchestrate/agents`, emits `connection_tested(success, message)`
  - `fetch_all()` fetches agents + tools + KBs, emits `data_fetched(GraphData)` or `fetch_error`
- Intro screen "Test Connection" button now live - shows agent count on success
- Uses await + one-shot HTTPRequest nodes for sequential async fetching (local dev server doesn't handle concurrent requests)

### Phase 4: Data Fetching ✅
- `fetch_all()` fetches agents, tools, KBs sequentially (local wxO dev server is single-threaded)
- Graph screen creates WxOClient on _ready, configures from saved config, calls fetch_all()
- HUD StatusLabel shows "Fetching data from wxO..." then summary "X agents, Y tools, Z KBs"
- GraphData stored on graph_screen for Phase 5 to render
- Errors displayed on HUD if any endpoint fails

### Phase 5: 3D Graph Rendering ✅
- `graph_node_base.gd`: Base class creates MeshInstance3D + Label3D (billboard) programmatically via `setup()`
- `graph_layout.gd`: Force-directed layout (Coulomb repulsion + Hooke attraction + center gravity + damping)
  - Positions initialized randomly in a flattened sphere (Y range reduced to 30%)
  - Velocity capped at 20.0 to prevent explosion, settles after 60 frames below threshold
- `graph_manager.gd`: Orchestrates graph building
  - Creates shared meshes/materials: blue spheres (agents), green cubes (tools), orange cylinders (KBs)
  - Builds edge list from agent relationships (tool_ids, collaborator_ids, knowledge_base_ids)
  - Renders edges as ImmediateMesh PRIMITIVE_LINES (rebuilt each frame during layout)
  - Emits `graph_built(node_count, edge_count)` signal
- `graph_screen.gd`: Creates GraphManager on _ready, passes GraphData, shows node/edge count in HUD

### Phase 6: Interaction
- Click/ray-cast to select a node
- Detail panel shows node info (name, type, description, connections)
- Hover highlight effect

### Phase 7: Polish
- Visual refinements (materials, glow, anti-aliasing)
- Auto-refresh / manual refresh button
- Error handling and loading states
