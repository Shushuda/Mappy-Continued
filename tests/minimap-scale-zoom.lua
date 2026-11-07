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
loadMethod("Mappy:SetZoomButtonsCorner")
loadMethod("Mappy:ConfigureZoomButtons")
loadMethod("Mappy:EditModeExit")
local function frame()
    return {
        ClearAllPoints = function(self) self.point = nil end,
        SetPoint = function(self, ...) self.point = {...} end,
    }
end
Minimap = { ZoomIn = frame(), ZoomOut = frame() }
function Mappy:LoadProfile(profile)
    self.CurrentProfile = profile
    self:ConfigureZoomButtons()
end
function Mappy:ErrorMessage(message) error(message) end
for _, corner in ipairs({"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}) do
    Mappy:SetZoomButtonsCorner(corner:lower())
    assert(Mappy.CurrentProfile.ZoomButtonsCorner == corner)
    for _, button in ipairs({"ZoomIn", "ZoomOut"}) do
        for index, value in ipairs(Mappy.ZoomButtonPositions[corner][button]) do
            assert(Minimap[button].point[index] == value)
        end
    end
    -- Blizzard changes anchors during Edit Mode; exit must restore the saved corner.
    Minimap.ZoomIn:SetPoint("CENTER")
    Minimap.ZoomOut:SetPoint("CENTER")
    Mappy:EditModeExit()
    assert(Minimap.ZoomIn.point[1] == corner)
    assert(Minimap.ZoomOut.point[1] == corner)
end
Mappy:LoadProfile({ ZoomButtonsCorner = "BOTTOMLEFT" })
assert(Minimap.ZoomIn.point[1] == "BOTTOMLEFT")
Mappy:LoadProfile({})
assert(Minimap.ZoomIn.point[1] == "TOPLEFT")
print("minimap scale/zoom regressions passed")
