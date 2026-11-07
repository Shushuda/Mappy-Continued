-- Run from the addon root with Lua 5.1: lua tests/minimap-buttons.lua
local file = assert(io.open(arg and arg[1] or "Mappy.lua", "rb"))
local source = file:read("*a")
file:close()
assert(loadstring(source))
Mappy = { IgnoreFrames = {}, MinimapButtons = {}, MinimapButtonsByFrame = {} }
local function loadSection(first, last)
    local start = assert(source:find(first, 1, true), first)
    local finish = assert(source:find(last, start + #first, true), last)
    assert(loadstring(source:sub(start, finish - 1)))()
end
loadSection("function Mappy:RegisterMinimapButton", "function Mappy:ConfigureMinimapOptions")
loadSection("function Mappy:IsAnchoredToFrame", "function Mappy:IsDruidTravelForm")
loadSection("function Mappy.Button_OnHide", "function Mappy:MinimapMouseWheel")

local restricted = setmetatable({}, { __mode = "k" })
function issecretvalue(value) return restricted[value] == true end
local function secret()
    local value = newproxy(true)
    local function denied() error("operation on secret value") end
    local mt = getmetatable(value)
    mt.__lt, mt.__le, mt.__eq, mt.__sub = denied, denied, denied, denied
    restricted[value] = true
    return value
end
local checks = 0
local function expect(actual, expected, label)
    assert(actual == expected, label)
    checks = checks + 1
end
local anchorMeta = { __eq = function(left, right)
    assert(not issecretvalue(left) and not issecretvalue(right), "comparison of secret anchor")
    return false
end }
local target = setmetatable({}, anchorMeta)
local function button(name, anchors)
    local frame = { anchors = anchors or {}, hooks = {}, shown = true }
    function frame:IsForbidden() return false end
    function frame:GetName() return name end
    function frame:GetObjectType() return "Button" end
    function frame:GetWidth() return 32 end
    function frame:GetHeight() return 32 end
    function frame:GetNumPoints() return #self.anchors end
    function frame:GetPoint(index) return unpack(self.anchors[index]) end
    function frame:SetPoint(...) self.anchors[#self.anchors + 1] = {...} end
    function frame:ClearAllPoints() self.anchors = {} end
    function frame:HookScript(event, callback) self.hooks[event] = callback end
    return frame
end

expect(Mappy:IsButtonFrame(button("TTMinimapButton12")), false, "TomTom pins excluded")
expect(Mappy:IsButtonFrame(button("TTMinimapButtonTools")), true, "only numbered TomTom pins excluded")
local aura = button(nil)
aura.GetWidth = function() return secret() end
expect(Mappy:IsButtonFrame(aura), false, "upstream secret dimension guard retained")
local secretAnchor = setmetatable({}, anchorMeta)
restricted[secretAnchor] = true
local anchored = button("Addon", {{"CENTER", secretAnchor}, {"CENTER", target}})
expect(Mappy:IsAnchoredToFrame(anchored, target), true, "readable anchor after secret anchor")
expect(Mappy:IsButtonFrame(nil), false, "missing discovery frame")
Mappy:RegisterMinimapButton(nil)
Mappy:RegisterMinimapButton({})
expect(#Mappy.MinimapButtons, 0, "incomplete registration ignored")

for _, ownership in ipairs({"neither", "set", "clear", "both"}) do
    local frame = button("Addon", {{"CENTER", target, "CENTER", 1, 2}})
    local originalSet, originalClear = frame.SetPoint, frame.ClearAllPoints
    Mappy:RegisterMinimapButton(frame)
    frame:Mappy_SetStackingEnabled(true)
    expect(frame.Mappy_StackingActive, true, "stacking enabled")
    frame:ClearAllPoints()
    frame:SetPoint("TOP", target, "BOTTOM", 13, 17)
    -- Another addon can replace either method independently after interception.
    local addonSet = function() error("restore must not call third-party SetPoint") end
    local addonClear = function() error("restore must not call third-party ClearAllPoints") end
    if ownership == "set" or ownership == "both" then frame.SetPoint = addonSet end
    if ownership == "clear" or ownership == "both" then frame.ClearAllPoints = addonClear end
    frame:Mappy_SetStackingEnabled(false)
    expect(frame.SetPoint, (ownership == "set" or ownership == "both") and addonSet or originalSet, "independent SetPoint ownership")
    expect(frame.ClearAllPoints, (ownership == "clear" or ownership == "both") and addonClear or originalClear, "independent ClearAllPoints ownership")
    expect(#frame.anchors, 1, "tracked anchor survives clearing")
    expect(frame.anchors[1][1], "TOP", "latest anchor restored")
    expect(frame.anchors[1][4], 13, "latest offset restored")
    expect(frame.Mappy_SavedAnchors, nil, "saved anchors released")
    expect(frame.Mappy_StackingActive, false, "permanent hooks disabled")
end

local invalid = button("Restricted", {{"CENTER", secretAnchor, "CENTER", 0, 0}})
Mappy:RegisterMinimapButton(invalid)
local invalidSet = invalid.SetPoint
invalid:Mappy_SetStackingEnabled(true)
expect(invalid.SetPoint, invalidSet, "secret anchors not intercepted")
local always = button("System", {{"CENTER", target, "CENTER", 0, 0}})
Mappy:RegisterMinimapButton(always, true)
always:Mappy_SetStackingEnabled(false)
expect(always.Mappy_StackingActive, true, "upstream always-stacked system button retained")

loadSection("Mappy.CornerInfo = {", "Mappy.ProfileNameMap = {")
function tableContains(set, key) return set[key] ~= nil end
loadSection("local function GetStackingBounds", "function Mappy:SetMinimapAlpha")
loadSection("function Mappy:StackMinimapButtons", "function Mappy:GetUIObjectDescription")
function Mappy:IsMinimapInFarmHud() return self.testFarmHud == true end
function Mappy.SetFrameLevel(frame, level) frame.level = level end
function Mappy:SetButtonsAlpha() self.fadeCalls = self.fadeCalls + 1 end
function GetInstanceInfo() return nil, "none", 0 end

local function geometricFrame(width, height, parent, scale, left, bottom)
    local frame = button("Geometry")
    frame.width, frame.height, frame.parent, frame.scale = width, height, parent, scale or 1
    frame.left, frame.bottom = left or 0, bottom or 0 -- Physical coordinates.
    function frame:GetScale() return self.scale end
    function frame:GetEffectiveScale()
        return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1)
    end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:GetLeft() return self.left / self:GetEffectiveScale() end
    function frame:GetRight() return self:GetLeft() + self.width end
    function frame:GetBottom() return self.bottom / self:GetEffectiveScale() end
    function frame:GetTop() return self:GetBottom() + self.height end
    function frame:GetFrameLevel() return self.level or 4 end
    function frame:SetParent(value) self.parent = value end
    function frame:SetAlpha(value) self.alpha = value end
    function frame:IsVisible() return self.shown end
    function frame:Show() self.shown = true; self.showCalls = (self.showCalls or 0) + 1 end
    function frame:Hide() self.shown = false end
    function frame:SetPoint(point, relative, relativePoint, x, y)
        assert(point == "CENTER", "stacking uses deterministic center anchors")
        self.anchors = {{point, relative, relativePoint, x, y}}
        self.stackedOn, self.stackedCorner = relative, relativePoint
        self.placements = (self.placements or 0) + 1
        local relativeScale, ownScale = relative:GetEffectiveScale(), self:GetEffectiveScale()
        local centerX = relative:GetLeft() * relativeScale
        local centerY = relative:GetBottom() * relativeScale
        if relativePoint:find("RIGHT") then centerX = centerX + relative:GetWidth() * relativeScale end
        if relativePoint:find("TOP") then centerY = centerY + relative:GetHeight() * relativeScale end
        self.left = centerX + x * ownScale - self.width * ownScale / 2
        self.bottom = centerY + y * ownScale - self.height * ownScale / 2
    end
    return frame
end

local function paddedBounds(frame)
    local ratio = frame:GetEffectiveScale() / MinimapCluster:GetEffectiveScale()
    local padding = Mappy.BlizzardMinimalistButtons[frame] and 8 * ratio or 0
    return {frame:GetLeft() * ratio - padding, frame:GetRight() * ratio + padding,
        frame:GetBottom() * ratio - padding, frame:GetTop() * ratio + padding}
end
local function overlaps(a, b)
    return a[1] < b[2] - 0.000001 and a[2] > b[1] + 0.000001
        and a[3] < b[4] - 0.000001 and a[4] > b[3] + 0.000001
end
local function near(actual, expected, label)
    assert(math.abs(actual - expected) < 0.000001, label)
    checks = checks + 1
end

local function layout(corner, ccw, mapScale, uiScale, clusterScale, clockShown, farmHud, screen)
    UIParent = geometricFrame(1920, 1080, nil, uiScale)
    MinimapCluster = geometricFrame(150, 150, UIParent, clusterScale, 300, 200)
    local container = geometricFrame(150, 150, MinimapCluster, mapScale, 300, 200)
    Minimap = geometricFrame(150, 150, container, 1, 300, 200)
    FarmHudMinimapDummy = geometricFrame(150, 150, container, 1, 300, 200)
    TimeManagerClockButton = geometricFrame(50, 16, MinimapCluster, 0.85)
    TimeManagerClockButton.left = 300 + Minimap:GetWidth() * Minimap:GetEffectiveScale() / 2
        - TimeManagerClockButton:GetWidth() * TimeManagerClockButton:GetEffectiveScale() / 2
    TimeManagerClockButton.bottom = 200 - 9 * TimeManagerClockButton:GetEffectiveScale()
    TimeManagerClockButton.shown = clockShown
    Mappy.MinimapButtons, Mappy.MinimapButtonsByFrame, Mappy.BlizzardMinimalistButtons = {}, {}, {}
    Mappy.StackingInfo, Mappy.fadeCalls, Mappy.testFarmHud = {}, 0, farmHud
    Mappy.StartingCorner = corner
    Mappy.CurrentProfile = {CCW = ccw, HideTimeOfDay = true, StackToScreen = screen}
    for index = 1, 40 do
        local mini = index % 4 == 0
        local ownScale = index % 5 == 0 and 0.75 or 1
        local frame = geometricFrame(mini and 24 or 32, mini and 24 or 32, MinimapCluster, ownScale)
        if mini then Mappy.BlizzardMinimalistButtons[frame] = true end
        if index == 3 then frame.shown = false end -- Hidden LibDBIcon-style button.
        Mappy:RegisterMinimapButton(frame)
        frame:Mappy_SetStackingEnabled(true)
    end
    Mappy:StackMinimapButtons()
    expect(Mappy.fadeCalls, 1, "upstream fade restored after placement")
    expect(Mappy.MinimapButtons[3].shown, false, "hidden button stays hidden")
    expect(Mappy.MinimapButtons[3].showCalls, nil, "hidden button never shown")
    expect(Mappy.MinimapButtons[3].placements, nil, "hidden button uses no capacity")
    local minimapCount, overflowed = 0, false
    local mapParent = farmHud and FarmHudMinimapDummy or Minimap
    for index, frame in ipairs(Mappy.MinimapButtons) do
        if frame.shown then
            expect(frame.placements, 1, "every visible button placed exactly once, including overflow boundary")
            if frame.stackedOn == UIParent then
                overflowed = true
            else
                expect(overflowed, false, "overflow is a contiguous range")
                expect(frame.stackedOn, mapParent, "FarmHud stacking parent preserved")
                minimapCount = minimapCount + 1
            end
            local bounds = paddedBounds(frame)
            for previous = 1, index - 1 do
                local other = Mappy.MinimapButtons[previous]
                if other.shown and other.stackedOn == frame.stackedOn then
                    expect(overlaps(bounds, paddedBounds(other)), false, "button borders do not overlap at corners")
                end
            end
            local cornerInfo = (ccw and Mappy.CornerInfoCCW or Mappy.CornerInfo)[frame.stackedCorner]
            if frame.stackedOn == Minimap and frame.stackedCorner:sub(1, 6) == "BOTTOM" and not cornerInfo.IsVert then
                local ratio = Minimap:GetEffectiveScale() / MinimapCluster:GetEffectiveScale()
                near((bounds[3] + bounds[4]) / 2, Minimap:GetBottom() * ratio - 5 * ratio, "clock does not lower the bottom baseline")
                if clockShown then
                    local clock = paddedBounds(TimeManagerClockButton)
                    expect(bounds[2] <= clock[1] or bounds[1] >= clock[2], true, "clock clearance uses effective-scale ratio")
                end
            end
        end
    end
    expect(overflowed, true, "screen overflow reached")
    return minimapCount
end

for _, corner in ipairs({"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}) do
    for _, ccw in ipairs({false, true}) do
        for _, mapScale in ipairs({0.5, 1, 1.75}) do
            for _, clockShown in ipairs({false, true}) do
                local normal = layout(corner, ccw, mapScale, 1, 1, clockShown)
                local scaled = layout(corner, ccw, mapScale, 0.64, 1.25, clockShown)
                expect(scaled, normal, "capacity independent of UI and cluster effective scales")
            end
        end
    end
end
local small = layout("TOPRIGHT", false, 0.5, 1, 1, false)
local large = layout("TOPRIGHT", false, 1.75, 1, 1, false)
expect(large > small, true, "larger physical minimap has more capacity")
layout("BOTTOMRIGHT", true, 1, 0.8, 1.2, true, true)
expect(layout("TOPLEFT", false, 1, 0.8, 1.2, true, false, true), 0, "explicit screen stacking stays on screen")

print("PASS: " .. checks .. " minimap-button checks (Lua 5.1; simulated secrets)")
