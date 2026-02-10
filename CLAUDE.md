# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mappy-Continued is a World of Warcraft addon that transforms the minimap into a square shape with extensive customization. Written entirely in Lua, it runs directly in WoW with no build step. The TOC file (`Mappy.toc`) defines the load order and metadata.

**Maintainer philosophy:** This is a maintenance fork — preserve existing features with minimal changes. Avoid adding new features or refactoring unless explicitly requested.

## Key Files

- **Mappy.toc** — Addon manifest (Interface version, SavedVariables, load order, optional deps)
- **Mappy.lua** — Entire addon logic (~2,900 lines): initialization, minimap management, settings UI, profiles, slash commands, gathering integration
- **Libraries/** — Bundled custom libraries (MC2AddonLib, MC2DebugLib, MC2EventLib, MC2SchedulerLib, MC2UIElementsLib, LibStub, LibDropdown-1.0)
- **Textures/** — BLP textures for minimap mask and gathering node icons

## Architecture

### Library Stack (loaded before Mappy.lua via TOC order)

| Library | Purpose |
|---------|---------|
| MC2AddonLib | Prototype-based object/class system, table utilities, script hooking |
| MC2DebugLib | Debug logging with chat frame integration |
| MC2EventLib | Custom event dispatcher wrapping WoW's native event system |
| MC2SchedulerLib | One-shot and recurring task scheduling via OnUpdate |
| MC2UIElementsLib | UI element constructors (dialogs, checkboxes, sliders, textures) |
| LibStub | Standard WoW library loader |
| LibDropdown-1.0 | Dropdown menu creation |

### Initialization Flow

```
ADDON_LOADED event → AddonLoaded()
  ├─ InitializeSettings() (first run)
  ├─ Load CurrentProfile from gMappy_Settings
  └─ Schedule InitializeMinimap (0.5s delay)
      ├─ FindMinimapButtons(), InitializeDragging(), InitializeSquareShape()
      ├─ Register event handlers (combat, movement, zone changes)
      ├─ Setup coordinate display
      ├─ Schedule ConfigureMinimap (0.5s)
      └─ Schedule UpdateMountedState (recurring 0.5s)
```

### Update Loop

- `Update()` runs every 0.2s — handles profile auto-switching, coordinate display, alpha state
- `UpdateMountedState()` runs every 0.5s — detects mount/dismount for profile switching

### Settings & Profiles

- **SavedVariables:** `gMappy_Settings` (persisted by WoW between sessions)
- **Profiles:** Named presets (DEFAULT, gather, etc.) with per-profile minimap size, alpha, visibility, position, gathering options
- **Auto-profile switching:** Context-based selection (mounted, dungeon, battleground, default)
- **Settings UI:** Three panels registered via `Settings.RegisterCanvasLayoutCategory()` — main options, button management, profiles

### Slash Commands

`/mappy <command>` — Commands include: `help`, `ghost`/`unghost`, `lock`/`unlock`, `save <name>`, `load <name>`, `reload`, `default`, `corner <corner>`, `cw`/`ccw`, `reset`, `gcompact`. Dispatched in `ExecuteCommand()`.

### Optional Addon Integration

Graceful integration with Gatherer, GatherMate/GatherMate2, MBB (MinimapButtonBag Reborn), and FarmHud. These are declared as `OptionalDeps` in the TOC.

### Protected Frame Handling

Minimap frames are protected by Blizzard. The addon checks `CanChangeProtectedState()` before modifying protected frames and hooks Edit Mode enter/exit for compatibility.

## Code Conventions

- **Naming:** CamelCase for functions/methods; `p` prefix for parameters, `v` prefix for local variables
- **Private members:** Underscore prefix (e.g., `_OptionsPanel`)
- **No localization:** All UI strings are hardcoded in English
- **No formal error handling:** Relies on WoW's built-in error catching
- **TOC versioning:** Interface version and addon Version are updated manually in `Mappy.toc`

## Reference Documentation

The `wow-ui-source/` directory contains the latest WoW UI source code mirrored from Blizzard. This is **documentation only** - use it as a reference for WoW's Lua API, frame templates, and UI patterns. Do not modify files in this directory or treat them as part of this addon project.

## Web Resources

For WoW API lookups, prefer `wow-ui-source/` for source code reference. For wiki documentation, restrict web searches to `warcraft.wiki.gg`.

## WoW Midnight (12.0) Secret Values System

### When Aura Data Becomes Secret
| Context | Aura Data |
|---------|-----------|
| Overworld + no combat | Accessible |
| Overworld + combat | **Secret** |
| Instanced content (delves, dungeons, raids, arenas, BGs) | **Secret** (regardless of combat) |

### Detection APIs
- `issecretvalue(val)` - Returns true if value is a secret handle
- `canaccessvalue(val)` - Returns true if current execution can read the value
- `scrubsecretvalues(...)` - Returns args with secret values replaced by nil

### Safety Pattern
Always check before comparing:
```lua
if not issecretvalue(aura.spellId) and aura.spellId == TARGET_SPELL_ID then
    -- safe to use
end
```

Performing math, comparison, or string conversion on a secret value triggers an unrecoverable Lua error.

### Private Auras vs Secret Values
- **Private auras**: Boss mechanics marked as opaque. Always private, older system (pre-Midnight). Designed to block DBM/WeakAuras from tracking certain encounters.
- **Secret values**: Dynamic system added in Midnight. Aura data becomes secret based on context (combat/instance state). Same aura is accessible in overworld, secret in dungeon.

### Whitelist
Blizzard whitelists specific spells via bluepost announcements. No API to query the whitelist. Whitelisted spells return normal values in all contexts. Can change per patch.
