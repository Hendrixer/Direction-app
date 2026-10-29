# Direction plugins

`plugins/direction/` is a single local package with both `.codex-plugin/plugin.json` and `.claude-plugin/plugin.json`. Both hosts use the same `.mcp.json` and four skills:

- **start-project** — create/open a project, import supplied media, prepare and review an assembly.
- **edit-video** — programmatic edits, transcript cuts, per-track audio, color, verification, export.
- **take-turnover** — work as the director's editor: read the brief, read back a turnover, cut, ask, and deliver the next cut with an answer per note.
- **review-feedback** — read original frames/audio/transcript and source projections, revise, reply as addressed.

Requires Apple Silicon and macOS 26+. It uses Direction's native executable; it does not embed an LLM, access a cloud service, generate footage, or install model dependencies. Apple's local speech model may download on first transcription.

## Prepare the executable

```sh
./scripts/build-app.sh release
./scripts/install-local.sh
```

The installer creates `~/.local/bin/direction` as a link to the built app's helper. It refuses to overwrite any unrelated executable/link. Keep this checkout and app in place; rerunning the build updates the linked helper. Alternatively install Direction.app under `~/Applications` or `/Applications`, or set `DIRECTION_CLI` to its helper's absolute path in the MCP environment.

The plugin launcher checks DIRECTION_CLI, the local link, installed app paths, then PATH. It quotes paths with spaces and reserves stdout for MCP messages. The app need not be open to edit or export.

## Codex

The repository contains `.agents/plugins/marketplace.json`, named `direction-local`.

```sh
codex plugin marketplace add /absolute/path/to/direction
codex plugin add direction@direction-local
```

Restart/reload the plugin host or begin a new chat to load its tools and skills. The desktop Plugins directory can also install from the Direction local marketplace. Do not publish this local development plugin as a public plugin without deciding distribution licensing and completing release packaging.

## Claude Code

For a session without installing:

```sh
claude --plugin-dir /absolute/path/to/direction/plugins/direction
```

For this repository:

```sh
claude plugin marketplace add /absolute/path/to/direction --scope project
claude plugin install direction@direction-local --scope project
```

Start a new Claude session. Invoke `/direction:start-project`, `/direction:edit-video`, or `/direction:review-feedback`, or describe the task naturally.

## Project lifecycle

The MCP process starts with no project selected. Create with `direction_create_project {path,name}`, list known packages with `direction_projects`, or open with `direction_open_project {path,showInApp}`. Pass `projectPath` on every editing/review/job call. Opening a project never redirects other calls. Original CLI integrations can still pin a default with `direction mcp --project PATH`.

Projects persist in `.direction` packages. The app and tools share a local recent-project index. Sources remain linked originals. Jobs live in the process that starts them: keep that process running until export/transcription/preview is complete.

## Verification

`./scripts/test.sh` includes actual stdio launch from the plugin's MCP configuration, project creation, restart persistence, explicit routing, inline PNG/WAV context, and CLI/API bootstrap. Run `claude plugin validate plugins/direction` for host manifest validation. Skill validation uses the Skill Creator validator. Local host loading is distinct from directory submission; this package has not been published or assigned an open-source license.

Formats were checked against [OpenAI plugin packaging](https://developers.openai.com/plugins/build/plugins) and [Claude's plugin reference](https://code.claude.com/docs/en/plugins-reference).
