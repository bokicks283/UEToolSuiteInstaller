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

For a Steam-configured project, explicitly select local LAN networking:

```powershell
ue mp play -Map /Game/Map/YourGameplayMap -Network LAN
```

`ue-tools` accepts the same commands. `-Map` is optional; without it Unreal uses the project's configured default game map. If the repository has several `.uproject` files, pass `-UProjectPath .\YourGame.uproject`. `-WorkspacePath` selects a workspace when engine resolution needs it. Use `ue mp help` for syntax.

`play` starts two separate `UnrealEditor.exe -game` processes and requests windowed mode. The host uses `?listen` and port 7777; the client opens `127.0.0.1:7777`. The launcher requests `MP_HOST` and `MP_CLIENT` as game window titles through process-local `Game` configuration overrides and requests a framed window so the titles are visible. With multiple screens, it requests a window position and resolution on the primary screen for the host and another screen for the client. With one screen, both processes request windowed mode. The launcher also passes `-UEToolSuiteMP` to both processes; projects that opt into this marker can honor the window and resolution arguments when applying saved video settings. Other projects may still override these startup requests.

The CLI prints each PID and log path. Logs are separate under `.ue-tools/local/mp-logs/`; `logs` prints the current paths. `stop` checks the recorded PID, executable, and start time before terminating a process. Close an old session with `ue mp stop` before starting another.

`-Network LAN` is case-insensitive and can appear before or after `-Map`. It adds `-ini:Engine:[OnlineSubsystem]:DefaultPlatformService=Null`, `-ini:Engine:[OnlineSubsystemSteam]:bEnabled=false`, and `-NetDriverOverrides=/Script/OnlineSubsystemUtils.IpNetDriver` to **both** launched processes. These command-line overrides temporarily select LAN networking without changing `DefaultEngine.ini` or other project configuration. Without `-Network`, the original behavior remains, including rejection of a detected Steam configuration. Other network mode values are unsupported.

This is a manual development launcher. Build the game project beforehand and inspect the host and client windows and logs yourself. LAN mode is for local multiplayer debugging and does not validate Steam sessions. The launcher does not create sessions or automate gameplay. Local firewall prompts, map availability, project login flows, and game-specific session code remain project responsibilities.
