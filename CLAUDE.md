# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mappy-Continued is a World of Warcraft addon that transforms the minimap into a square shape with extensive customization. Written entirely in Lua, it runs directly in WoW with no build step. The TOC file (`Mappy.toc`, shared by retail and Forever) defines the load order and metadata.

**Maintainer philosophy:** This is a maintenance fork — preserve existing features with minimal changes. Avoid adding new features or refactoring unless explicitly requested.

## Key Files

- **Mappy.toc** — Addon manifest for retail and WoW Forever (Interface versions for both, SavedVariables, load order, optional deps)
- **Mappy.lua** — Entire addon logic (~3,500 lines): initialization, minimap management, settings UI, profiles, slash commands, gathering integration
- **Libraries/** — Bundled custom libraries (MC2AddonLib, MC2DebugLib, MC2EventLib, MC2SchedulerLib, MC2UIElementsLib, LibStub, LibDropdown-1.0)
- **Textures/** — BLP textures for gathering node icons and overlays; 8-bit opacity masks in `MinimapMasks/`

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
- **Settings UI:** Four panels: main options, registered via `Settings.RegisterCanvasLayoutCategory()`, with appearance, button management and profiles as subcategories (`RegisterCanvasLayoutSubcategory()`). Options that depend on other options, or are off for another reason (the gathering node options, since Blizzard removed `SetBlipTexture()`), are greyed out in each panel's `UpdateDependentOptions()`, called from its `OnShow()` and from the setters of the options they depend on, with `setCheckbuttonEnabled()` (checkbox and label). Options for something a client doesn't have aren't created on that client at all, since they could never apply there (Forever has no world quests): with a frame check when the client lacks a frame (`MinimapCluster.DielFrame`), and with `Mappy.IsForeverClient` when it lacks an API or the feature is only made for one client.

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
- `ConfigureMinimap()` returns early if `MinimapCluster` is protected and locked (a safety net in case Blizzard ever protects it) and while Edit Mode is active. `UpdateMinimapShown()` has the same safety net for `MinimapContainer`.
- `/mappy` without arguments won't open the settings panel in combat, because `C_SettingsUtil.OpenSettingsPanel` is restricted for addons.
- `SelectAutoProfile()` waits for combat to end, so the minimap doesn't resize mid-fight.
- Edit Mode hooks are described under Edit Mode Integration.

### Minimap Frames

The tree is the same on both clients: `UIParent → MinimapCluster → MinimapContainer → Minimap → MinimapBackdrop` (`Blizzard_Minimap/Mainline/Minimap.xml`).
- **`MinimapCluster`'s children:** `ZoneTextButton`, `Tracking`, `IndicatorFrame` (with `MailFrame` and `CraftingOrderFrame`), `MinimapContainer`, `InstanceDifficulty` and `BorderTop` (moves into `ZoneTextButton` in 12.1.7), plus `GameTimeFrame`, `AddonCompartmentFrame` and `TimeManagerClockButton` from their own XML files. Forever adds `GamepadHudBackground` and `GamepadButtons`, and lacks a few (see WoW Forever Client).
- **`MinimapContainer`'s children:** `Minimap` and `PlayerCoords` (Mappy hides `PlayerCoords`), plus Forever's `DielFrame`, created in Lua (`Diel.lua:19`).
- **`MinimapBackdrop`:** `InitializeSquareShape()` replaces the global with Mappy's own frame, a child of the original. Blizzard code that reads the global gets Mappy's frame, so Mappy copies the original's `StaticOverlayTexture` and `ExternalEventURLButton` onto it. FarmHud also reads the global. It also holds the border (see Border).
- **`QueueStatusButton`** is a child of `UIParent`.
- Blizzard only sets `MinimapContainer`'s scale and position, and Mappy forces its scale to 1 (`OverrideEditModeSize()`) and hides it at 0% alpha (see Alpha).
- **Zoom buttons:** Blizzard shows `Minimap.ZoomIn`/`ZoomOut` only from `MinimapMixin:OnEnter` and hides them on `OnLeave`; with `HideZoomButtons` on, `MinimapOnEnter()` hides them right after.
- **Button parents:** every registered addon button sits under `MinimapCluster`, whatever the auto-arrange setting. `StackButton()` reparents stacked buttons, and `StackMinimapButtons()` gives unstacked addon buttons the same parent and frame level. Blizzard buttons are always stacked, but only visible buttons get stacked, so one that hasn't been shown since login keeps Blizzard's parent (for the expansion landing page button, the original `MinimapBackdrop`, inside `Minimap`).

### Alpha

- A frame's drawn alpha is its own alpha × its parent's effective alpha, all the way up to `UIParent`. An own alpha is capped at 1, so it can't cancel a parent's alpha.
- `SetIgnoreParentAlpha(true)` cuts the frame off from its whole ancestor chain, `UIParent` included. Its children still inherit from it (seen in game).
- `GetAlpha()` doesn't return the exact value set: `SetAlpha(0.2)` reads back as `0.200000000178923` (seen in game). Don't compare it with `==`; remember the value set instead.
- `IsIgnoringParentAlpha()` returns a plain boolean (API docs, seen in game). `GetAlpha()` and `GetEffectiveAlpha()` only turn secret after the alpha was set from a secret value.
- `UIFrameFade()` calls `frame:Show()` and keeps its state in `frame.fadeInfo`, so a frame has one fade at a time. A second fade on the same frame, from any addon, replaces the first, and the first one's `finishedFunc` never runs.
- Blizzard never sets ignore-parent-alpha on minimap frames, and never sets the alpha of `MinimapCluster`, `MinimapContainer` or `Minimap` (both clients).
- Blips ignore alpha, both `Minimap`'s own and its parents' (seen in game), and no API sets their alpha.
- Quest, world quest and dig site areas (blobs in the API) ignore alpha like blips. Each has three parts with 0–255 alpha setters on `Minimap`, for `Quest`, `Task` (world quests, bonus objectives) and `Arch` (dig sites): `Set*BlobRingAlpha` (the hatched pattern along the map's edge, "edge pattern" in the options), `Set*BlobOutsideAlpha` (the glowing outline) and `Set*BlobInsideAlpha` (the fill). They take effect right away. They have no getters and Blizzard never sets them. The defaults, matched by eye on retail: ring 128, outline 128 (world quests 255; 245 and up look identical), and fill 128 on dig sites only (quests and world quests show none). The world map's blobs (`SetFillAlpha` 128, `SetBorderAlpha` 192) are separate frames.
- The selected quest's (AKA supertracked) ring and outline ignore those setters; only `SetQuestBlobRingScalar()` reaches its ring, and it resizes the ring. The selected world quest reacts. The outline for both draws brighter while selected.
- **Mappy's minimap alpha:** `AdjustAlpha()` picks the target (combat, movement, normal, hover), and `FadeAlphaTo()` fades a helper frame, `MinimapFader`, with `UIFrameFade()`. Its `SetAlpha` hook calls `ApplyMinimapAlpha()`, which keeps `Minimap` at alpha 1, selects the map opacity mask, and fades the border, static overlay, coordinates, zoom buttons, zone text and clock separately (see Indoor map art). Mappy never sets `MinimapCluster`'s alpha, which stays free for other addons.
  - The opacity mask affects map artwork; child frames still inherit the map frame's alpha of 1. `ApplyMinimapAlpha()` sets the original backdrop's alpha (`MinimapBackdrop:GetParent()`, containing Mappy's replacement backdrop and static overlay), the coordinate font string and the zoom buttons explicitly. Mappy doesn't change ignore-parent-alpha to implement its opacity settings.
  - **Buttons:** `SetButtonsAlpha()` sets each button's own alpha to the auto-hide fade (`ButtonFader`) × the minimap alpha, or × 1 with "Buttons ignore minimap alpha sliders" ticked. Mappy never turns ignore-parent-alpha on, so everything follows whole-UI fades.
    - While "Show buttons ONLY on mouseover" is on (and "Buttons ignore…" is off), buttons count a 0% minimap alpha as 100%, so hovering still reveals them on a hidden map, while a dimmed map keeps them dimmed (OLED burn-in). `GetMouseoverButtonsAlpha()` blends fades into or out of 0% with the same progress as the map's fade (`FadeStart` to `FadeTarget`), with 0% swapped for 100% at either end, so buttons don't dip and jump back when the map fades out at 0%, and buttons lingering after the mouse leaves match the mail icon.
    - The mail icon and Group Finder eye exceptions ("Except the …") get the same value but skip the auto-hide fade. They're greyed out while mouseover-only is off, since the auto-hide fade is 1 then.
  - **Mouseover:** while the profile's `MinimapHoverOpaque` is on ("Change alpha on mouseover"; the key keeps its old name), hovering replaces the state's alpha with `MinimapHoverAlpha` ("Mouseover Alpha", `nil` = 100%), raising or lowering it. The same mask selection applies indoors and outdoors.
  - **Quest areas:** `ApplyBlobAlpha()` sets each part to its default × Mappy's requested alpha (`MinimapFaderAlpha`) while the profile's `FadeBlobs` is on, and to its default otherwise, so the areas fade with the map, except the selected quest's ring and outline. They only follow Mappy's alpha, not whole-UI fades. While the minimap is in FarmHud's HUD, they get their defaults. If Blizzard changes a default, Mappy keeps drawing the old value and can't tell, since nothing reads it back.
  - **Hiding at 0%:** blips and the player arrow ignore alpha, and quest areas only partly follow it (see Quest areas), so with the profile's `HideMinimapAtZeroAlpha` on, `UpdateMinimapShown()` hides `MinimapContainer` while Mappy's alpha is 0. Its checkbox, "Show map icons at 0% alpha", shows the inverse. New installs hide in `DEFAULT` and show in `gather` (its sonar view); older profiles have no key and show, as before. It hides the container, not `Minimap`: Blizzard (Toggle Minimap keybinding, new-player tutorial, `MinimapDisabled` game rule), FarmHud (when its HUD hides) and `UIFrameFade()` (DynamicCam) show and hide `Minimap` itself, and nothing else touches the container. It stays shown while the minimap is in FarmHud's HUD, since FarmHud's stand-in is in it. Hover still works through `Update()`'s `MinimapCluster:IsMouseOver()` check, up to 0.2s later. `StackMinimapButtons()` counts the hidden container as shown (`IsButtonVisible()`), so buttons still inside the minimap get stacked. Hiding the container fires `OnHide` on the frames inside it; Blizzard's handlers there (the expansion landing page button's alert callbacks, Forever's event button glow) are undone on `OnShow`.
  - **Click-through at 0%:** while Mappy's alpha is 0, whatever the profile, `UpdateClickThrough()` turns off the mouse on `MinimapCluster`, the zone text, the clock, and the buttons when they fade with the map ("Buttons ignore…" and mouseover-only both off; mouseover-only buttons count 0% as 100%), and turns it back on for exactly those frames (`ClickThroughFrames`) above 0. For the zone text, clock and buttons it includes every frame inside them (`addFrameTree()`), since each takes the mouse on its own: `MinimapCluster.Tracking` is a container, and its clickable part is the dropdown button inside it. `MinimapCluster` takes the mouse (Blizzard's XML, with no mouse scripts) and is the map's size, so it catches clicks at the map's spot once the map is hidden or ghosted; while the map is shown, the map takes them itself. It turns the mouse off rather than hiding the frames: Mappy's `OnHide` hook on buttons restacks the ring, and addons, Blizzard and Mappy's own hide options show these frames. Frames whose mouse is already off (the cluster in ghost mode) and protected frames are skipped. Hover still works, since `IsMouseOver()` only checks the cursor's position. Buttons hidden by "Show buttons ONLY on mouseover" keep their mouse.
  - **LibDBIcon's mouseover hide:** Mappy turns it off on its own buttons, at startup and whenever an addon turns it back on (`DisableLibDBIconMouseover()`), so "Show buttons ONLY on mouseover" is the only one. A button that's invisible in the stacked ring would leave a hole, and Mappy sets every button's alpha anyway.
  - `FadeTarget`, `MinimapFaderAlpha` and `ButtonFaderAlpha` hold the values Mappy set; nothing reads them back with `GetAlpha()`.
  - **FarmHud** owns the map while it is in the HUD. Mappy skips its map alpha, mask, border, coordinate and zoom-button alpha writes then, and reapplies its settings after the minimap leaves the HUD. FarmHud entry still restores quest-area defaults and shows its stand-in. Check mask restoration and inherited frame alpha when testing FarmHud.
- **Indoor map art:** setting the native minimap frame below alpha 1 can leave its artwork black or missing after a redraw. Mappy keeps the frame at alpha 1 and applies transparency through `Minimap:SetMaskTexture()` instead.
  - `SetMinimapMaskAlpha()` clamps and rounds the requested opacity to a byte from 0 to 255, remembers `MinimapMaskAlphaByte`, and changes the texture only when that byte changes. Normal, movement, combat and mouseover settings keep using the existing helper-frame fade.
  - `MinimapMaskPathFormat` uses `Mappy.AddonPath` and `Textures\\MinimapMasks\\%03d.tga`. The 256 masks are 8x8 uncompressed 32-bit TGA images, with white RGB and a uniform alpha byte matching their filename. They total 70,144 bytes on disk; fade opacity has 8-bit precision.
  - `MinimapMaskPath` holds the selected texture. `InitializeSquareShape()` and Forever's `RestoreSquareSkin()` use it, so a rotation-setting refresh restores the current mask.
  - Indoor detection, view-radius tables, idle timers, redraw event handlers and automatic zoom nudges are no longer needed for Mappy's opacity settings. Manual wheel zoom is unchanged.
  - The 5.5.0 indoor dimming and idle-fade controls are removed. Existing `DimIndoorMap`, `FadeIndoorMap` and `IndoorFadeDelay` values are ignored without deleting or migrating profiles. The map follows the existing alpha sliders indoors and outdoors; the removed dark overlay no longer dims native blips or the player arrow.
  - Test city and indoor transitions, zero-opacity hiding and gathering icons, Retail housing's static overlay, FarmHud entry/exit, third-party pins and external whole-UI fades. Keeping the native frame opaque changes inherited alpha for child frames that aren't explicitly faded; client tests are required for those integrations.

### Engine observations from upstream 5.5.0

These are maintainer-reported in-game observations recorded at upstream commit `7d22abd`, before the opacity-mask implementation. They remain useful compatibility and regression-test context. They do not mean every case below has been retested with masks, and the removed frame-alpha workaround is not part of the current implementation.

- **Cached artwork:** the map art was not redrawn every frame. An indoor drawing made with the native frame below 100% alpha could remain black until another redraw; one made at 100% could remain visible after the frame alpha dropped. This explains the old idle-fade workaround and its limitations.
- **Redraw conditions:** zooming, indoor/outdoor map swaps, loading screens and entering another indoor map piece (corridor segments or Undercity layers) were observed to redraw the art. `NEW_WMO_CHUNK` often accompanied the last case, but not always or in step with the redraw. Standing still, turning, jumping, elevators and moving blips generally did not redraw it, except in a small spot in Undercity proper. In that spot, the old idle fade could leave the map black until movement or zooming; that observation describes the old frame-alpha approach, not a confirmed mask failure.
- **Map mode versus player location:** `IsIndoors()` did not identify every indoor minimap. Buildings changed both states, but Forever's Orgrimmar (from the entrance corridor onward) and underground Undercity changed only the minimap mode. Thunder Bluff and Undercity's above-ground ruins changed neither. Retail had fewer such locations. Map IDs were also insufficient: Undercity's map 1458 covered both the ruins and underground areas.
- **Measured view radii:** at a fixed zoom step, indoor map art usually showed fewer yards. Mappy's size setting did not change the radius. The measured sets below are historical reference data, not tables used by the current opacity code. Zoom 0 was fully zoomed out; Retail's main sets had an extra zoomed-out step relative to Forever.

| Context | View radii in yards, zoom steps 0 through 5 |
|---|---|
| Forever outdoors | 233.3, 200, 166.7, 133.3, 100, 66.7 |
| Forever indoors | 150, 120, 90, 60, 40, 25 |
| Retail outdoors | 333.3, 233.3, 200, 166.7, 133.3, 100 |
| Retail indoors | 220, 150, 120, 90, 60, 40 |
| Retail housing neighborhoods and house interiors | Same radii as Forever outdoors; neighborhood art remained visible below 100% frame alpha |

- **Zoom settings and events:** `minimapZoom` and `minimapInsideZoom` could not distinguish modes when their saved values matched. `MINIMAP_UPDATE_ZOOM` fired on a map-mode swap after the radius updated, and on `Minimap:SetZoom()`. Two `SetZoom()` calls in one execution produced one event after both. These observations explain the previous detection and redraw handlers; no automatic zoom nudge is needed by the mask implementation.
- **Dark overlay behavior:** the removed 5.5.0 overlay darkened native blips, the player arrow and quest areas along with the map, without making the opaque map see-through. HereBeDragons pins drew above it. That icon-darkening effect is separate from map transparency and is not reproduced by opacity masks; any future darkening option needs its own scope and compatibility testing.

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

### Border

- Mappy draws the border with Blizzard's NineSlice layouts, on two frames inside its `MinimapBackdrop`: `TooltipBorder` (`TooltipDefaultLayout`, its dark fill hidden), and on Forever `WindowBorder` (the profile's `WindowBorder`, "Forever-style border"). `AdjustBackgroundStyle()` shows one; "Hide border" hides both. `MinimapBackdrop` sits 4 outside the map.
- Forever keeps retail's atlas names and repaints the art. `Blizzard_SharedXML/Camelot/NineSliceLayoutOverrides.lua` only nudges the window frame's corners for the new art's size, so the same layout draws each client's art. Blizzard's tooltips set only their fill color in code (`SharedTooltip_SetBackdropStyle()`), so the border's color is in the art, including a dark inset shadow: grey on retail, brown on Forever. Mappy tints retail's to 85% (`BorderTint`).
- **Forever style:** the window frame's art (`UI-Frame-Metal-*`, layout `ButtonFrameTemplateNoPortrait`) in Mappy's own `WindowBorderLayout`. The window's top has a title bar, so the top uses the bottom pieces upside down through the layout's `setupPieceVisualsFunction`; NineSlice itself only flips pieces in fixed directions. On Forever the corners are 95×100 and the edges 95, 95 and 100 thick (left, right, bottom), but only 7–17 units of each is metal and the rest is transparent. So Mappy ignores Blizzard's offsets: the sides sit 17, 12, 7 and 12 outside the map (left, top, right, bottom), and the zone name moves from 4 to 8 above the map.
- Below map size 176 the Forever style's corners would overlap. `CropWindowBorderCorners()` crops their inner ends on every size change, like Forever's `NineSliceUtil.UpdateCornerCropping()` does for short windows, but both ways. `CheckWindowBorderArt()` prints an error once a session if the art's sizes differ from `WindowBorderArtSizes`.
- Frame levels: `Minimap` L, Blizzard's backdrop L+1, Mappy's L+2, border frames L+3, zoom buttons L+4, stacked buttons L+5.

## Code Conventions

- **Naming:** CamelCase for functions/methods; `p` prefix for parameters, `v` prefix for local variables
- **Private members:** Underscore prefix (e.g., `_OptionsPanel`)
- **No localization:** All UI strings are hardcoded in English
- **No formal error handling:** Relies on WoW's built-in error catching
- **TOC versioning:** Interface versions (retail and Forever, comma-separated on one line) and addon Version are updated manually in `Mappy.toc`. There are no client-specific TOCs, so both clients load this one.
- **Supported clients:** only the latest retail and Forever releases. Code needed only for an outgoing release gets a `TODO` to remove it once the new release is live.

## Reference Documentation

The `wow-ui-source/` directory (one tier above working dir) contains the latest WoW UI source code mirrored from Blizzard. This is **documentation only** - use it as a reference for WoW's Lua API, frame templates, and UI patterns. Do not modify files in this directory or treat them as part of this addon project.

It's a git repo with one branch per WoW client. Read branches without checking them out:
- Search: `git -C wow-ui-source grep -n <pattern> origin/<branch> --`
- Read a file: `git -C wow-ui-source show origin/<branch>:<path>`

| Branch | Client |
|---|---|
| `live` | Retail |
| `forever` | WoW Forever |
| `ptr`, `ptr2`, `beta` | Retail test clients |

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
