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
loadSection("Mappy._MinimapButton = {}", "function Mappy:MinimapMouseWheel")

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
local target = {}
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
local secretAnchor = secret()
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

print("PASS: " .. checks .. " minimap-button checks (Lua 5.1; simulated secrets)")
