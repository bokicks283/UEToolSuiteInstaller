---
title: Multiplayer launcher
slug: /cli/multiplayer
---

# Manual multiplayer launcher

From a project repository with one discoverable `.uproject`, run:

```powershell
ue mp play -Map /Game/Maps/Arena
ue mp logs
ue mp stop
```

`ue-tools` accepts the same commands. `-Map` is optional; without it Unreal uses the project's configured default game map. If the repository has several `.uproject` files, pass `-UProjectPath .\YourGame.uproject`. `-WorkspacePath` selects a workspace when engine resolution needs it. Use `ue mp help` for syntax.

`play` starts two separate windowed `UnrealEditor.exe -game` processes. The host uses `?listen` and port 7777; the client opens `127.0.0.1:7777`. The CLI prints each PID and log path. Logs are separate under `.ue-tools/local/mp-logs/`; `logs` prints the current paths. `stop` terminates only the recorded processes whose executable path and start time still match, then removes the session record. Close an old session with `ue mp stop` before starting another.

This is a manual development launcher. Build the game project beforehand and inspect the host and client windows and logs yourself. It does not create sessions, configure Steam, change network drivers, or automate gameplay. Projects that enable Steam networking in `Config/DefaultEngine.ini` must use a project-supported local mode or separate Steam accounts; the launcher reports the configuration instead of changing it. Local firewall prompts, map availability, project login flows, and game-specific session code remain project responsibilities.
