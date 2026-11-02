# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mappy-Continued is a World of Warcraft addon that transforms the minimap into a square shape with extensive customization. Written entirely in Lua, it runs directly in WoW with no build step. The TOC file (`Mappy.toc` and `Mappy_Camelot.toc`) defines the load order and metadata.

**Maintainer philosophy:** This is a maintenance fork — preserve existing features with minimal changes. Avoid adding new features or refactoring unless explicitly requested.

## Key Files

- **Mappy.toc** — Addon manifest for retail WoW (Interface version, SavedVariables, load order, optional deps)
- **Mappy_Camelot.toc** — Addon manifest for WoW Forever (Interface version, SavedVariables, load order, optional deps)
- **Mappy.lua** — Entire addon logic (~3,500 lines): initialization, minimap management, settings UI, profiles, slash commands, gathering integration
- **Libraries/** — Bundled custom libraries (MC2AddonLib, MC2DebugLib, MC2EventLib, MC2SchedulerLib, MC2UIElementsLib, LibStub, LibDropdown-1.0)
- **Textures/** — BLP textures for minimap mask and gathering node icons

## Architecture

### Library Stack (loaded before Mappy.lua via TOC order)

| Library | Purpose |
|---------|---------|
| MC2AddonLib | Prototype-based object/class system, table utilities, script hooking |
| MC2DebugLib | Debug logging with chat frame integration |
| MC2EventLib | Custom event dispatcher wrapping WoW's native event system |
| MC2SchedulerLib | One-shot and recurring task scheduling via OnUpdate; tasks scheduled while tasks run wait for the next frame |
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
- **Missing settings:** `AddonLoaded()` doesn't fill in keys missing from saved profiles. A setting added later reads `nil` in older profiles, and a changed default in `InitializeSettings()` only reaches new installs. For example, `FadeButtons` defaults to `true` since `106adfe`, but older profiles have `false` or `nil`.
- **Auto-profile switching:** Context-based selection (mounted, dungeon, battleground, default)
- **Settings UI:** Three panels registered via `Settings.RegisterCanvasLayoutCategory()` — main options, button management, profiles

### Slash Commands

`/mappy <command>` — Commands include: `help`, `ghost`/`unghost`, `lock`/`unlock`, `save <name>`, `load <name>`, `reload`, `default`, `corner <corner>`, `cw`/`ccw`, `reset`. Dispatched in `ExecuteCommand()`.

### Optional Addon Integration

Graceful integration with GatherMate/GatherMate2, MBB (MinimapButtonBag Reborn), FarmHud, and Immersion. These are declared as `OptionalDeps` in the TOC.

Immersion turns on ignore-parent-alpha on `Minimap` and `MinimapCluster` at login (see Other Addons That Touch the Minimap). `InitializeMinimap()` turns it off with `ClearIgnoreParentAlpha()` so the minimap follows whole-UI fades; Immersion's dialogs still switch it on and back themselves. Mappy also listens to Immersion's `IMMERSION_hideminimap` setting and clears the flag again when it's unticked, and prints a chat warning if the setting doesn't exist. Never clear the flag from a `SetIgnoreParentAlpha` hook, since DynamicCam's guard would loop, or from Mappy's refreshes, which can run during an Immersion dialog.

### Other Addons That Touch the Minimap

Behavior checked in each addon's source:
- **Immersion** (retail and Forever; checked 1.4.61):
  - At login (`Display/Onload.lua`), it sets ignore-parent-alpha on `Minimap` and `MinimapCluster` unless its "Hide minimap" is ticked. That option has no default, so this hits everyone who never ticked it, even with "Hide interface" off. The minimap then ignores every whole-UI fade, such as DynamicCam's "Hide entire UI". Mappy undoes it (see Optional Addon Integration).
  - "Hide minimap" is only visible while "Hide interface" is on, and changing it sets the flags right away.
  - Its dialog fade ("Hide interface" on, `Display/Fademgr.lua`) records the flag of each frame it keeps visible, fades `UIParent` to 0, turns those flags on, and restores the recorded values when the dialog closes. With "Hide minimap" ticked, it instead fades `MinimapCluster`'s own alpha to 0 and hides it, then fades it back to 1, not to its earlier value.
  - Its fades are a copy of `UIFrameFade()` (`Display/Animation.lua`) that writes the same `frame.fadeInfo` field.
  - Its settings are Blizzard proxy settings named `IMMERSION_<key>`, e.g. `IMMERSION_hideminimap` (since 2026-09-24). Blizzard runs Immersion's setter first, then notifies `Settings.SetOnValueChangedCallback()` listeners; Immersion's own `Compat.lua` listens to `hidetracker` this way. Its private table isn't global; `ImmersionFrame`, `ImmersionAPI` and its saved settings `ImmersionSetup` are.
- **DynamicCam** (checked `release/2.20.x`):
  - "Hide UI" situations fade `UIParent` (`Core.lua`, `EaseUIParentAlpha`) and guard it with a `UIParent.SetAlpha` hook that switches off when the fade ends.
  - With "Hide entire UI", it skips the minimap frames and hides `UIParent` at the end.
  - Without it, it fades `MinimapCluster` and `Minimap` with `UIFrameFade()` (`UiHideModule.lua`, `FadeOutFrame`/`FadeInFrame`). If a frame ignores parent alpha, it fades the frame's own alpha, then turns the flag off; "Keep minimap" turns the flag on instead. Both are put back when the situation ends.
  - `ParentAlphaGuard` hooks `SetIgnoreParentAlpha` on both frames. Once DynamicCam has changed the flag itself, the guard reverts every other addon's change for the rest of the session; unlike the `UIParent` guard, it never switches off. Never force the flag from another hook on that method: the two hooks would loop.
- **Immersion with DynamicCam:** both record the flag and put it back later. Immersion's always-on flag hides two problems, and turning the flag off at login (as Mappy does, or Immersion fixing it) exposes them:
  - After a DynamicCam "Keep minimap" situation, the guard keeps the flag off, so Immersion's dialogs can no longer keep the minimap visible. Also reproducible without Mappy: tick Immersion's "Hide minimap", run such a situation, then untick it.
  - A DynamicCam situation without "Keep minimap" that starts during an Immersion dialog records the dialog's temporary "on" and puts it back after the dialog has ended. The guard then keeps it on until `/reload`.

  Both need a DynamicCam "Hide UI" situation without "Hide entire UI" (off by default) and Immersion's "Hide interface". Mappy can't fix them without editing DynamicCam's private state.
- **BlizzHUDTweaks:** its frame fading can fade `MinimapCluster`'s own alpha (its own fade code, not `UIFrameFade()`), and sets it back to 1 when its fading module is turned off. It never touches the flag.
- **FarmHud** (checked `9dcb830`):
  - While its HUD is shown, it moves `Minimap` into the HUD and leaves a stand-in, `FarmHudMinimapDummy` (a child of `MinimapContainer`), at the old spot. It moves onto the stand-in `Minimap`'s children, a fixed list of named frames, and the children and regions of frames registered with `FarmHud:RegisterForeignAddOnObject()`. Mappy registers `MinimapCluster`.
  - To move a frame, it replaces the frame's `SetPoint` (and `SetParent`) fields, and assigns the originals back when the HUD hides, which leaves FarmHud-written fields behind.
  - While shown, it sets `Minimap`'s alpha itself and reverts other addons' writes through a `Minimap.SetAlpha` hook. When the HUD hides, it puts back the alpha it saved when the HUD opened.
  - When `UIParent` hides while the HUD is shown (Alt-Z, DynamicCam's "Hide entire UI"), FarmHud hides too, unless its `showWithHiddenUI` option is on (off by default). It keeps the minimap in the HUD then and skips its `OnHide` and `OnShow` code, so `FarmHud:IsVisible()` is false while the minimap is still in the HUD. `Minimap:GetParent() == FarmHud` tells the two apart, and every FarmHud check in Mappy uses it (`IsMinimapInFarmHud()`).
- **LibDBIcon** (checked minor 57): creates its buttons as children of `Minimap`, with a fixed strata and frame level. At `PLAYER_LOGIN` it places them using `Minimap:GetWidth()` at that moment, and never recalculates on resize. `SetButtonRadius(lib.radius)` recalculates every button (LibDBIcon calls it that way itself), so `ConfigureMinimap()` calls it after resizing the minimap. An addon can hide its button until the mouse is over the minimap or a LibDBIcon button with `ShowOnEnter(name, true)`. LibDBIcon does it with the button's own alpha, fading it to 0 starting 1s after the mouse leaves. It doesn't save the option: the addon calls it again every session, and there's no function to read it. Mappy turns it off on its own buttons (see Alpha).
- **HereBeDragons** (map pins for GatherMate2, HandyNotes, TomTom and others): parents minimap pins to `Minimap` (changeable with `SetMinimapObject()`) and never sets their alpha.

### Edit Mode Integration

Blizzard's `EditModeManagerFrame:UpdateLayoutInfo()` re-anchors every Edit Mode frame, `MinimapCluster` included, each time it runs, even when the layout hasn't changed. Settings such as the minimap Size are only reapplied when their value changes. It runs on:
- `EDIT_MODE_LAYOUTS_UPDATED`: at login, and on every `C_EditMode.SetActiveLayout()` call, including Mappy's own, gamepad mode and layout-switcher addons.
- `PLAYER_SPECIALIZATION_CHANGED`: spec swaps on retail, and level-ups on Forever.
- Edit Mode exit (through "revert all changes") and spectate mode.

How Mappy reacts:
- `EnterEditMode` hook: with addon positioning, moves `MinimapCluster` to its saved Edit Mode position with `ApplyEditModeAnchor()`, a copy of Blizzard's `ApplySystemAnchor` math that doesn't call into Edit Mode. Never call `C_EditMode.SetActiveLayout()` while Edit Mode is open: from this hook it caused "attempt to call a nil value" errors on Edit Mode open and exit on Forever (`EditModeManager.lua:130` and `:1672`).
- `ExitEditMode` hook and `ACTIVE_PLAYER_SPECIALIZATION_CHANGED`: a full refresh in both positioning modes, which also reapplies the size override (`OverrideEditModeSize()`).
- `UpdateLayoutInfo` post-hook (`EditModeLayoutUpdated()`), addon positioning only: restores the position and size override in the same call, so the Edit Mode position is never drawn, then schedules a full refresh. While Edit Mode is open it skips the instant restore, which would otherwise undo the position being edited. It ignores Edit Mode positioning entirely: in that mode `ConfigureMinimap()` calls `C_EditMode.SetActiveLayout()`, which would re-enter the hook every frame.
- `SetHeaderUnderneath` hook: Edit Mode calls `MinimapCluster:SetHeaderUnderneath()` whenever it applies "Header underneath" or the minimap Size, so at login and whenever either changes. On Forever and 12.1.7 it moves `ZoneTextButton` back to Blizzard's spot whichever way the setting is set, so Mappy puts it back above the map right after (`AnchorZoneText()`).
- Group Finder eye (`QueueStatusButton`, Forever only; on retail it belongs to the micro menu and doesn't touch the minimap):
  - Its default Edit Mode spot is an offset from the minimap, so the addon-button scan would take it over. It's in `IgnoreFrames`, and Mappy leaves it to Edit Mode unless the profile's `StackGroupFinder` is on.
  - With it on, `StackGroupFinder()` stacks it as a Blizzard button after the other Blizzard buttons, at 100% size (also in `OverrideEditModeSize()`). The `EnterEditMode` hook releases it to Edit Mode (`ReleaseGroupFinder()`) and restacks the ring without it; exit restacks it.
  - Releasing sets the replaced `SetPoint`/`ClearAllPoints` to `nil` instead of assigning the originals back, so Blizzard's methods are used without Mappy-written fields. It then applies the eye's Edit Mode size and saved anchor.
  - Its default spot is scaled by `MinimapCluster:GetEditModeScale()` and only recalculated on `Minimap.OnScaleUpdated`. `OverrideEditModeSize()` doesn't fire that, so `ConfigureMinimap()` fires it after the override. `SetEditModeScale(1)` isn't used because Forever's `Diel.lua` wraps it to re-anchor the day/night button.

Known gap: with Edit Mode positioning, a layout switch from anything other than Edit Mode exit or a spec swap (gamepad mode, layout-switcher addons, spectate) leaves Edit Mode's minimap size, and a stacked Group Finder eye's size, in place until the next refresh.

### Combat Handling

On retail and Forever, none of the minimap frames Mappy touches are protected: `IsProtected()` returns `false` for `Minimap`, `MinimapCluster` and the Blizzard buttons Mappy hides. Mappy configures the minimap during combat, including on a combat login. The remaining checks:
- `ConfigureMinimap()` returns early if `MinimapCluster` is protected and locked (a safety net in case Blizzard ever protects it) and while Edit Mode is active.
- `/mappy` without arguments won't open the settings panel in combat, because `C_SettingsUtil.OpenSettingsPanel` is restricted for addons.
- `SelectAutoProfile()` waits for combat to end, so the minimap doesn't resize mid-fight.
- Edit Mode hooks are described under Edit Mode Integration.

### Minimap Frames

The tree is the same on both clients: `UIParent → MinimapCluster → MinimapContainer → Minimap → MinimapBackdrop` (`Blizzard_Minimap/Mainline/Minimap.xml`).
- **`MinimapCluster`'s children:** `ZoneTextButton`, `Tracking`, `IndicatorFrame` (with `MailFrame` and `CraftingOrderFrame`), `MinimapContainer`, `InstanceDifficulty` and `BorderTop` (moves into `ZoneTextButton` in 12.1.7), plus `GameTimeFrame`, `AddonCompartmentFrame` and `TimeManagerClockButton` from their own XML files. Forever adds `GamepadHudBackground` and `GamepadButtons`, and lacks a few (see WoW Forever Client).
- **`MinimapContainer`'s children:** `Minimap` and `PlayerCoords` (Mappy hides `PlayerCoords`), plus Forever's `DielFrame`, created in Lua (`Diel.lua:19`).
- **`MinimapBackdrop`:** `InitializeSquareShape()` replaces the global with Mappy's own frame, a child of the original. Blizzard code that reads the global gets Mappy's frame, so Mappy copies the original's `StaticOverlayTexture` and `ExternalEventURLButton` onto it. FarmHud also reads the global.
- **`QueueStatusButton`** is a child of `UIParent`.
- Blizzard only sets `MinimapContainer`'s scale and position, and Mappy forces its scale to 1 (`OverrideEditModeSize()`).
- **Button parents:** every registered addon button sits under `MinimapCluster`, whatever the auto-arrange setting. `StackButton()` reparents stacked buttons, and `StackMinimapButtons()` gives unstacked addon buttons the same parent and frame level. Blizzard buttons are always stacked, but only visible buttons get stacked, so one that hasn't been shown since login keeps Blizzard's parent (for the expansion landing page button, the original `MinimapBackdrop`, inside `Minimap`).

### Alpha

- A frame's drawn alpha is its own alpha × its parent's effective alpha, all the way up to `UIParent`. An own alpha is capped at 1, so it can't cancel a parent's alpha.
- `SetIgnoreParentAlpha(true)` cuts the frame off from its whole ancestor chain, `UIParent` included. Its children still inherit from it (seen in game).
- `GetAlpha()` doesn't return the exact value set: `SetAlpha(0.2)` reads back as `0.200000000178923` (seen in game). Don't compare it with `==`; remember the value set instead.
- `IsIgnoringParentAlpha()` returns a plain boolean (API docs, seen in game). `GetAlpha()` and `GetEffectiveAlpha()` only turn secret after the alpha was set from a secret value.
- `UIFrameFade()` calls `frame:Show()` and keeps its state in `frame.fadeInfo`, so a frame has one fade at a time. A second fade on the same frame, from any addon, replaces the first, and the first one's `finishedFunc` never runs.
- Blizzard never sets ignore-parent-alpha on minimap frames, and never sets the alpha of `MinimapCluster`, `MinimapContainer` or `Minimap` (both clients).
- Blips ignore alpha, both `Minimap`'s own and its parents' (seen in game), and no API sets their alpha.
- **Mappy's minimap alpha:** `AdjustAlpha()` picks the target (combat, movement, normal, indoors, hover), and `FadeAlphaTo()` fades a helper frame, `MinimapFader`, with `UIFrameFade()`. Its `SetAlpha` hook calls `ApplyMinimapAlpha()`, which sets the alpha of `Minimap`, the zone text and the clock. Mappy never sets `MinimapCluster`'s alpha, which stays free for other addons.
  - The map's own alpha is used rather than `MinimapContainer`'s, so the map keeps Mappy's alpha even while another addon has its ignore-parent-alpha flag on.
  - **Buttons:** `SetButtonsAlpha()` sets each button's own alpha to the auto-hide fade (`ButtonFader`) × the minimap alpha, or × 1 with "Buttons ignore minimap alpha sliders" ticked. Mappy never turns ignore-parent-alpha on, so everything follows whole-UI fades.
  - **LibDBIcon's mouseover hide:** Mappy turns it off on its own buttons, at startup and whenever an addon turns it back on (`DisableLibDBIconMouseover()`), so "Show buttons ONLY on mouseover" is the only one. A button that's invisible in the stacked ring would leave a hole, and Mappy sets every button's alpha anyway.
  - `FadeTarget`, `MinimapFaderAlpha` and `ButtonFaderAlpha` hold the values Mappy set; nothing reads them back with `GetAlpha()`.
  - **FarmHud** owns the map's alpha while its HUD is shown, and Mappy re-applies its own once the minimap has left the HUD.

### Minimap Insets

`C_Minimap.SetMinimapInsetInfo` pulls the minimap's edge-pinned quest arrow toward the center within an angle slice. Blizzard doesn't document it; these facts come from Blizzard's code and ptr tests.
- **Versions:** live and Forever's current build have one unnamed slice, `(minAngle, maxAngle, scalar)`, cleared with `ClearMinimapInsetInfo()`; its only caller is the expansion landing page. 12.1.7 has named slices, `(id, minAngle, maxAngle, scalar, isCircular)`, cleared by ID. `MinimapUtil.UpdateInsetForFrame` only exists alongside named slices.
- **Angles:** radians from the map center, 0 up, counter-clockwise (left π/2, down π).
- **`scalar`:** the arrow's tip ends up at about `scalar` × its normal distance from the center.
- **`isCircular`:** `true` ramps the inset down to 0 at the slice edges, with no flat part, and the ramp grows with the slice; it suits round buttons. `false` applies the full inset across the whole slice and the arrow jumps at its edges; it suits rectangles. The path stays a circle either way.
- Overlapping slices add up. `/reload` clears all slices.
- `MinimapUtil.UpdateInsetForFrame()` turns a frame's corners into a slice using angles only, never distance, so a frame far from the map still gets a slice pointing at it.
- **On Mappy's square map:** the arrow's path is a circle inside the border. The gap grows with the map, but not in proportion: about 5.5 units at size 150 and 9.4 at size 434. The arrow doesn't scale with the map (about 17×15 units).
- **What Mappy does:** it clears Blizzard's slices for buttons it moves (`BlizzardInsetIDs`: expansion landing page, Forever's day/night button and Group Finder eye) from a post-hook on `SetMinimapInsetInfo` and once at startup (`ClearBlizzardInsets()`). Before 12.1.7 it clears the single slice. It leaves the event button's slice (`ExternalEventURLMinimapButton`) alone.

## Code Conventions

- **Naming:** CamelCase for functions/methods; `p` prefix for parameters, `v` prefix for local variables
- **Private members:** Underscore prefix (e.g., `_OptionsPanel`)
- **No localization:** All UI strings are hardcoded in English
- **No formal error handling:** Relies on WoW's built-in error catching
- **TOC versioning:** Interface version and addon Version are updated manually in `Mappy.toc`
- **Supported clients:** only the latest retail and Forever releases. Code needed only for an outgoing release gets a `TODO` to remove it once the new release is live.

## Reference Documentation

The `wow-ui-source/` directory contains the latest WoW UI source code mirrored from Blizzard. This is **documentation only** - use it as a reference for WoW's Lua API, frame templates, and UI patterns. Do not modify files in this directory or treat them as part of this addon project.

It's a git repo with one branch per WoW client. The working tree is on `live`, so searching its files covers **retail only**. Read other branches without checking them out:
- Search: `git -C wow-ui-source grep -n <pattern> origin/<branch> --`
- Read a file: `git -C wow-ui-source show origin/<branch>:<path>`

| Branch | Client | Mappy TOC |
|---|---|---|
| `live` | Retail | `Mappy.toc` |
| `forever` | WoW Forever | `Mappy_Camelot.toc` |
| `ptr`, `ptr2`, `beta` | Retail test clients | `Mappy.toc` |

Other branches are for clients Mappy doesn't support, so ignore them. Each branch's `version.txt` holds its exact build, and test branches can lag behind `live`. Remote branches are only as current as the last `git fetch`. On `forever`, Forever-only code lives in `Camelot/` subfolders, and Blizzard's TOCs tag those files `[AllowLoadGameType camelot]` (e.g. `Blizzard_Minimap/Camelot/Diel.lua`).

**Before modifying any WoW API call**, verify the replacement against:
1. `wow-ui-source/Interface/AddOns/Blizzard_Deprecated/` for transition guides
2. `wow-ui-source/` for usage examples in Blizzard's own code
3. The `forever` branch too, since `Mappy.lua` runs on both clients

## Web Resources

For WoW API lookups, prefer `wow-ui-source/` for source code reference. For wiki documentation, restrict web searches to `warcraft.wiki.gg`.

## WoW Forever Client

Forever is a Classic-style game on a client close to retail. Retail APIs and events exist there, but some mean different things:
- **Talents are vanilla-style:** three talent trees per class and no retail specializations, with the tree names standing in for spec names. The trees are built on retail's trait system (`C_Traits`).
- **Two loadout slots ("spec groups")** are swapped with `C_SpecializationInfo.SetActiveSpecGroup()`. Blizzard's Forever talent UI treats `ACTIVE_PLAYER_SPECIALIZATION_CHANGED` as that swap; this hasn't been checked in game.
- **Levelling up fires `PLAYER_SPECIALIZATION_CHANGED`**, seen in game at level 10+. Edit Mode reapplies its layout on that event (see Edit Mode Integration).
- **Spending a talent point** fires only `TRAIT_CONFIG_UPDATED` and `PLAYER_TALENT_UPDATE`, seen in game.
- **Client detection:** `Mappy.IsForeverClient` (`WOW_PROJECT_ID == WOW_PROJECT_CAMELOT`) is only for client-specific behavior. Missing frames use existence checks.
- **Missing frames:** Forever 70425 omits `MinimapCluster.InstanceDifficulty`, `IndicatorFrame.CraftingOrderFrame` and `BorderTop`; its header background is `ZoneTextButton.StateTexture`.
- **Rotation:** Mappy keeps the `rotateMinimap` CVar off with `StopMinimapRotation()`: at startup, on every `CVAR_UPDATE`, and when the minimap leaves FarmHud's HUD (it's left alone while the minimap is in the HUD). Edit Mode stores Rotate Minimap in the layout and writes the CVar at every login and whenever it changes, so the layout keeps the player's choice and removing Mappy restores it. `C_Minimap.SetIgnoreRotateMinimap()` isn't enough, both seen in game: addons that draw their own minimap icons read the CVar and kept rotating them, and the game resets the ignore switch on loading screens. With the CVar off, loading screens don't bring the compass texture back, but turning rotation off doesn't clear a compass already shown (seen in game). Forever re-skins the minimap (round mask, frame art, underlay ring) in `MinimapCluster:UpdateMinimapConfig()` on every `rotateMinimap` change, and once in `OnLoad()` before addons load, so Mappy hooks it and also undoes it once at startup.

## WoW Midnight (aka Retail; 12.0+) and Forever (aka Camelot; 1.60.1+) Secret Values System

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
