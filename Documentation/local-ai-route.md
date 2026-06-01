# PerX Local Agent Route

## Scope

The macOS app uses `PerXLocalAgentClient` as its only boundary for local
external dependencies. App-facing services do not launch commands, inspect tool
install paths or call Ollama HTTP endpoints directly.

The Local Agent owns:

- dependency discovery and structured status for Homebrew, Python, Node.js,
  Ollama, ZIP and Unzip;
- periodic dependency monitoring;
- Homebrew-based installation and updates where supported;
- Python script execution for Excel compatibility, MLX legacy bridging and RAG
  builds;
- ZIP archive creation;
- Ollama lifecycle management;
- Ollama health checks, model listing, GGUF imports, text generation, streaming
  and vision requests.

System-native Swift functionality and remote application APIs remain in the app.
For example, Cloud, Hub and OAuth calls are not local dependency operations and
are intentionally not proxied by the Local Agent.

## Ollama route

Only the Local Agent communicates with Ollama:

- `GET http://localhost:11434/api/tags` checks health and lists models.
- `POST http://localhost:11434/api/generate` handles local text generation.
- The same endpoint receives an `images` array for local vision analysis.

`LocalAIService` is the internal app-facing facade. It validates model
configuration and delegates every Ollama operation to `PerXLocalAgentClient`.

## Distribution model

The main macOS target is configured for direct Developer ID distribution with
hardened runtime and without Mac App Store sandbox assumptions. Optional local
dependencies report readable errors when they are unavailable.

## Embedded XPC architecture

`PerX Local Agent` is an embedded XPC service with bundle identifier
`it.pernozzoli.PerX.LocalAgent`. Xcode packages it under
`PerX.app/Contents/XPCServices` and signs it together with the app.

The app compiles `XPCPerXLocalAgentClient` only. It serializes requests over
`NSXPCConnection`, receives structured errors and uses a callback XPC endpoint
for streamed Ollama tokens. The helper target compiles
`InProcessPerXLocalAgent`; this is the only component that launches processes,
inspects local executable paths or contacts localhost Ollama endpoints.

The XPC service starts dependency monitoring when it is activated. It refreshes
installed versions every heartbeat and checks Homebrew updates at a slower
cadence. A future LaunchAgent can adopt the same `PerXLocalAgentClient`
contract if monitoring must continue while PerX is not running.

For release distribution, archive and notarize the macOS app bundle as a whole.
The nested XPC service must keep hardened runtime enabled and must be signed by
the same Developer ID release workflow.
