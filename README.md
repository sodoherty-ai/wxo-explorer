# wxo-explorer

A 3D network graph visualizer for [IBM watsonx Orchestrate](https://www.ibm.com/products/watsonx-orchestrate) environments, built with Godot 4.6 and GDScript.

wxo-explorer connects to a watsonx Orchestrate instance via its REST API and renders agents, tools, and knowledge bases as an interactive 3D graph. Click on any node to inspect its details, and chat directly with agents from within the app.

## Features

- **3D Network Graph** — Agents (blue spheres), tools (green cubes), and knowledge bases (orange cylinders) laid out using a force-directed algorithm, with edges showing relationships between them.
- **Interactive Camera** — Orbit and free-fly camera modes with mouse, keyboard, and gamepad support.
- **Node Detail Panel** — Click any node to view its properties, connections, and which agents use it.
- **Agent Chat** — Chat directly with agents through the wxO API. Each agent maintains its own conversation session, so you can switch between agents and pick up where you left off.
- **Markdown Rendering** — Agent responses are rendered with formatting support for bold, italic, headings, code blocks, tables, lists, and links.
- **Resizable Chat Panel** — Drag the handle to resize the chat window to your preference.
- **Dual Auth Modes** — Supports local Bearer Token (with auto-fill from local credentials) and API Key authentication.

## Requirements

- [Godot 4.6](https://godotengine.org/) stable
- A running watsonx Orchestrate instance (Developer Edition locally, or a SaaS instance)

## Getting Started

1. Open the project in Godot 4.6.
2. Run the project (F5).
3. On the intro screen, enter your server URL (default: `http://localhost:4321`).
4. Select your auth mode and provide credentials.
   - **Local (Bearer Token)**: Use "Auto-fill from local credentials" to load your token from `~/.cache/orchestrate/credentials.yaml`, or enter it manually.
   - **API Key**: Enter your API key for cloud instances.
5. Click "Test Connection" to verify, then "Enter" to load the graph.

## Controls

| Input | Orbit Mode | Free-fly Mode |
|-------|-----------|---------------|
| WASD / Arrows | Pan | Move |
| Left-drag | Orbit | — |
| Right-drag | Pan | Mouse look |
| Scroll wheel | Zoom | Adjust speed |
| Tab | Switch to Free-fly | Switch to Orbit |
| Space / Shift | — | Up / Down |
| Click | Select node | Select node |
| Escape | Back to intro | Release mouse / Back |

Gamepad supported: left stick for movement/pan, right stick for look/orbit, triggers for zoom/vertical, Triangle to toggle mode.

## Project Structure

```
wxo-explorer/
├── scenes/           # Godot scene files (.tscn)
│   ├── main.tscn     # Root scene, manages screen transitions
│   └── screens/      # Intro, loading, and graph screens
├── scripts/          # GDScript source files
│   ├── api/          # wxO REST API and chat clients
│   ├── camera/       # Dual-mode camera controller
│   ├── graph/        # Graph manager, node rendering, force layout, starfield
│   ├── screens/      # Screen logic (intro, loading, graph)
│   └── util/         # Utilities (markdown-to-BBCode converter)
└── resources/        # Fonts, images, saved config
```

## License

All rights reserved.
