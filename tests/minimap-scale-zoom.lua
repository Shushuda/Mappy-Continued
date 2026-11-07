-- Run from the addon root with Lua 5.1: lua tests/minimap-scale-zoom.lua
-- Exercise the production methods without loading the addon or Blizzard UI.
local file = assert(io.open("Mappy.lua", "r"))
local source = file:read("*a")
file:close()
Mappy = { CurrentProfile = {}, _AppearancePanel = {} }
local function loadMethod(name)
    local first = assert(source:find("function " .. name .. "(", 1, true), name)
    local last = source:find("\nfunction ", first + 1, true) or (#source + 1)
    assert(loadstring(source:sub(first, last - 1), "@Mappy.lua:" .. name))()
end
local tableStart = assert(source:find("Mappy.ZoomButtonPositions =", 1, true))
local tableEnd = assert(source:find("Mappy.StartingCorner =", tableStart, true))
assert(loadstring(source:sub(tableStart, tableEnd - 1)))()
loadMethod("Mappy:ConfigureZoomButtons")

function CopyTable(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = CopyTable(item) end
    return copy
end
local function equal(left, right)
    if type(left) ~= "table" then return left == right end
    if type(right) ~= "table" then return false end
    for key, value in pairs(left) do
        if not equal(value, right[key]) then return false end
    end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end
-- Deliberately different enum numbers catch accidental hardcoded system/setting IDs.
Enum = {
    EditModeSystem = { Minimap = 22 },
    EditModeMinimapSetting = { Size = 42 },
    EditModeLayoutType = { Preset = 10, Account = 11, Character = 12, Override = 13 },
}
local combat, locked, editing, protected, changeProtected = false, false, false, false, true
function InCombatLockdown() return combat end
local function layout(kind, value)
    return { layoutType = kind, systems = {
        { system = 99, settings = {{setting = 42, value = 123}} },
        { system = 22, settings = {{setting = 41, value = 321}, {setting = 42, value = value}} },
    } }
end
local presets = { layout(10, 5), layout(10, 6) }
local raw = { activeLayout = 4, layouts = {layout(11, 3), layout(12, 11)} }
EditModeManagerFrame = {
    IsEditModeLocked = function() return locked end,
    IsEditModeActive = function() return editing end,
    -- Blizzard_EditMode/Shared/EditModeManager.lua:1433-1438.
    GetActiveLayoutInfo = function(self)
        return self.overrideLayoutInfo or self.layoutInfo.layouts[self.layoutInfo.activeLayout]
    end,
}
local function updateLayouts()
    -- UpdateLayoutInfo (938-948) prepends presets; raw C_EditMode layouts omit them.
    local expanded = CopyTable(presets)
    for _, item in ipairs(raw.layouts) do expanded[#expanded + 1] = CopyTable(item) end
    EditModeManagerFrame.layoutInfo = { activeLayout = raw.activeLayout, layouts = expanded }
end
updateLayouts()
local saves, schedules = 0, 0
C_EditMode = {
    GetLayouts = function() return CopyTable(raw) end,
    SaveLayouts = function(info)
        saves = saves + 1
        assert(info ~= EditModeManagerFrame.layoutInfo, "must not taint live manager tables")
        assert(info.activeLayout == raw.activeLayout)
        assert(#info.layouts == #presets + #raw.layouts, "same expanded payload as Blizzard SaveLayouts")
        local selected = info.activeLayout
        for index, item in ipairs(EditModeManagerFrame.layoutInfo.layouts) do
            if index ~= selected then
                assert(equal(item, info.layouts[index]), "unrelated layout changed")
            else
                local expected = CopyTable(item)
                expected.systems[2].settings[2].value = info.layouts[index].systems[2].settings[2].value
                assert(equal(expected, info.layouts[index]), "unrelated system or setting changed")
            end
        end
        for index = 1, #raw.layouts do raw.layouts[index] = CopyTable(info.layouts[index + #presets]) end
        updateLayouts()
    end,
}
local methods = {}
function methods:SetWidth(value) self.width = value end
function methods:SetHeight(value) self.height = value end
function methods:SetScale(value) self.scale = value end
function methods:GetEffectiveScale()
    return (self.scale or 1) * (self.parent and self.parent:GetEffectiveScale() or 1)
end
function methods:GetParent() return self.parent end
function methods:IsProtected() return protected end
function methods:CanChangeProtectedState() return changeProtected end
function methods:SetPoint(...) self.point = {...} end
function methods:ClearAllPoints() self.point = nil end
methods.Mappy_SetPoint = methods.SetPoint
methods.Mappy_ClearAllPoints = methods.ClearAllPoints
function methods:SetText(value) self.text = value end
function methods:SetChecked(value) self.checked = value end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:SetValue(value)
    self.value = value
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value, false) end
end
function methods:IsVisible() return false end
for _, name in ipairs({"Hide", "SetMinMaxValues", "SetValueStep", "SetObeyStepOnDrag",
    "SetStepsPerPage", "SetStartPoint", "SetEndPoint", "SetColorTexture", "SetThickness"}) do
    methods[name] = function() end
end
local function widget(parent)
    return setmetatable({ parent = parent, scripts = {} }, {__index = methods})
end
function methods:CreateFontString() return widget(self) end
function methods:CreateLine() return widget(self) end
function CreateFrame(kind, name, parent)
    local result = widget(parent)
    if name then
        _G[name] = result
        for _, suffix in ipairs({"Text", "Low", "High"}) do _G[name .. suffix] = widget(result) end
    end
    return result
end
UIParent = widget()
UIParent:SetScale(0.8)
MinimapCluster = widget(UIParent)
MinimapCluster.MinimapContainer = widget(MinimapCluster)
Minimap = widget(MinimapCluster.MinimapContainer)
Minimap.ZoomIn, Minimap.ZoomOut = widget(Minimap), widget(Minimap)
local marker, button = widget(Minimap), widget(MinimapCluster)
Mappy.MinimapButtonsByFrame = {}
Mappy.CurrentProfile = { MinimapSize = 140, MinimapScale = 1.6 }
Mappy.SchedulerLib = {ScheduleUniqueTask = function() schedules = schedules + 1 end}
Mappy.AppearancePanel = widget()
Mappy.AppearancePanel.SizeSlider = widget()
MappySizeSliderText = widget()
for _, name in ipairs({"GetEditModeMinimapScale", "SetEditModeMinimapScale", "OverrideEditModeSize",
    "UpdateSizeSliderText", "IsMinimapInFarmHud", "ConfigureMinimap", "EditModeEnter",
    "EditModeLayoutUpdated", "SetMinimapSize", "SetMinimapAlpha", "SetMinimapCombatAlpha",
    "SetMinimapMovingAlpha"}) do
    loadMethod("Mappy:" .. name)
end
local function close(actual, expected)
    assert(math.abs(actual - expected) < 0.000001, tostring(actual) .. " ~= " .. tostring(expected))
end
close(Mappy:GetEditModeMinimapScale(), 1.6) -- Selected second custom layout, not the first.
raw.activeLayout = 3
updateLayouts()
close(Mappy:GetEditModeMinimapScale(), 0.8) -- Retained profile fallback must not shadow customs.
Mappy:SetEditModeMinimapScale(1.3)
assert(raw.layouts[1].systems[2].settings[2].value == 8)
assert(raw.layouts[2].systems[2].settings[2].value == 11)
assert(Mappy.CurrentProfile.MinimapScale == 1.6)
raw.activeLayout = 4
updateLayouts()
for value = 0, 15 do
    Mappy:SetEditModeMinimapScale((50 + value * 10) / 100)
    assert(raw.layouts[1].systems[2].settings[2].value == 8)
    assert(raw.layouts[2].systems[2].settings[2].value == value)
    close(Mappy:GetEditModeMinimapScale(), (50 + value * 10) / 100)
end
local beforeSaves = saves
Mappy:SetEditModeMinimapScale(2) -- Unchanged scale doesn't save.
assert(saves == beforeSaves)
for _, state in ipairs({"combat", "locked", "editing", "protected", "sync", "applying"}) do
    local before = CopyTable(EditModeManagerFrame.layoutInfo)
    local profile = CopyTable(Mappy.CurrentProfile)
    local scheduled = schedules
    combat, locked, editing = state == "combat", state == "locked", state == "editing"
    protected, changeProtected = state == "protected", false
    Mappy.DisableUpdates = state == "sync"
    EditModeManagerFrame.layoutApplyInProgress = state == "applying"
    Mappy:SetEditModeMinimapScale(0.5)
    assert(saves == beforeSaves and schedules == scheduled)
    assert(equal(before, EditModeManagerFrame.layoutInfo) and equal(profile, Mappy.CurrentProfile))
end
combat, locked, editing, protected, changeProtected = false, false, false, false, true
Mappy.DisableUpdates, EditModeManagerFrame.layoutApplyInProgress = false, false
raw.activeLayout = 1
updateLayouts()
local customBefore = CopyTable(raw.layouts)
close(Mappy:GetEditModeMinimapScale(), 1.6)
Mappy:SetEditModeMinimapScale(0.9)
close(Mappy:GetEditModeMinimapScale(), 0.9)
assert(Mappy.CurrentProfile.MinimapScale == 0.9 and saves == beforeSaves)
assert(equal(raw.layouts, customBefore) and presets[1].systems[2].settings[2].value == 5)
Mappy.CurrentProfile.MinimapScale = nil
close(Mappy:GetEditModeMinimapScale(), 1) -- Reading preset defaults never writes profile.
assert(Mappy.CurrentProfile.MinimapScale == nil and saves == beforeSaves)
raw.layouts = {} -- Preset-only accounts need no custom layout to scale.
updateLayouts()
Mappy:SetEditModeMinimapScale(1.5)
close(Mappy:GetEditModeMinimapScale(), 1.5)
assert(saves == beforeSaves and #raw.layouts == 0)

MinimapCluster.MinimapContainer:SetScale(1.5) -- Blizzard applies this to the container.
Mappy:OverrideEditModeSize()
assert(MinimapCluster.MinimapContainer.scale == 1 and Minimap.scale == 1.5)
assert(Minimap.width == 140 and MinimapCluster.width == 210 and MinimapCluster.height == 210)
assert(Minimap.point[1] == "TOPLEFT" and Minimap.point[2] == MinimapCluster)
close(marker:GetEffectiveScale(), 1.2)
close(button:GetEffectiveScale(), 0.8) -- Stacked sibling buttons are not scaled.
Mappy:UpdateSizeSliderText()
FarmHud = widget()
Mappy.FarmHudEnabled = true
Minimap.parent = FarmHud
Minimap:SetScale(0.75)
Mappy:OverrideEditModeSize()
assert(Minimap.scale == 0.75, "hidden FarmHud still owns the minimap by parent")
Minimap.parent, Mappy.FarmHudEnabled = MinimapCluster.MinimapContainer, false
Mappy:OverrideEditModeSize()
editing = true
Mappy:EditModeEnter()
assert(Minimap.scale == 1, "Edit Mode must not compound map and container scales")
editing = false
Mappy:EditModeLayoutUpdated()
assert(Minimap.scale == 1.5 and MinimapCluster.MinimapContainer.scale == 1)

-- Exercise the production ConfigureMinimap path, including its layout-update re-entry.
local activeWrites, radiusUpdates = 0, 0
function Mappy:ConfigureMinimapOptions() end
function Mappy:StackMinimapButtons() end
function Mappy:AdjustAlpha() end
function Mappy:SetFramePosition() end
EventRegistry = {TriggerEvent = function() end}
LibStub = function(name, silent)
    assert(name == "LibDBIcon-1.0" and silent)
    return { radius = 5, SetButtonRadius = function(_, radius)
        assert(radius == 5)
        radiusUpdates = radiusUpdates + 1
    end }
end
C_EditMode.SetActiveLayout = function(index)
    activeWrites = activeWrites + 1
    assert(index == raw.activeLayout)
    MinimapCluster.MinimapContainer:SetScale(Mappy:GetEditModeMinimapScale())
    Mappy:EditModeLayoutUpdated()
end
Mappy:ConfigureMinimap()
assert(activeWrites == 1 and radiusUpdates == 1)
assert(MinimapCluster.MinimapContainer.scale == 1 and Minimap.scale == 1.5)
assert(MinimapCluster.width == 210 and Minimap.width == 140)
combat = true
Mappy:ConfigureMinimap()
assert(activeWrites == 1 and radiusUpdates == 1, "combat must not reapply a layout")
combat, locked = false, true
Mappy:ConfigureMinimap()
assert(activeWrites == 1 and radiusUpdates == 1, "locked contexts must not reapply a layout")
locked = false

print("minimap scale/zoom regressions passed")
