-- Run from the addon root with Lua 5.1: lua tests/minimap-smoothing.lua
local secret = newproxy(true)
function issecretvalue(value) return rawequal(value, secret) end
function canaccessvalue(value) return not issecretvalue(value) end
WOW_PROJECT_ID, WOW_PROJECT_CAMELOT = 1, 2
GameTimeFrame, AddonCompartmentFrame = {}, {}
MinimapCluster = { IndicatorFrame = { MailFrame = {} }, Tracking = {} }
local addon = { EventLib = { RegisterEvent = function() end } }
assert(loadfile(arg and arg[1] or "Mappy.lua"))("Mappy", addon)

local function frame(regions, children)
    return {
        IsForbidden = function() return false end,
        IsProtected = function() return false end,
        HasSecretValues = function() return false end,
        GetRegions = function() return unpack(regions or {}) end,
        GetChildren = function() return unpack(children or {}) end,
    }
end
local function texture(snap, bias)
    local t = frame()
    t.snap, t.bias, t.writes = snap, bias, 0
    function t:IsObjectType(kind) return kind == "Texture" end
    function t:IsSnappingToPixelGrid() return self.snap end
    function t:GetTexelSnappingBias() return self.bias end
    function t:SetSnapToPixelGrid(value) self.snap = value; self.writes = self.writes + 1 end
    function t:SetTexelSnappingBias(value) self.bias = value; self.writes = self.writes + 1 end
    return t
end
local ordinary = texture(true, 0.5)
local unchanged = texture(false, 0)
local forbidden = texture(true, 0.75)
forbidden.IsForbidden = function() return true end
local hiddenSecret = texture(secret, 0.5)
local unsupported = frame()
local parent = frame({ordinary, unchanged, forbidden, hiddenSecret, unsupported})
Minimap = frame({}, {parent})

local checks = 0
local function expect(value, expected, label)
    assert(value == expected, label)
    checks = checks + 1
end
addon:InitializeSettings()
addon.CurrentProfile = gMappy_Settings.Profiles.DEFAULT
addon:ApplyMinimapSmoothing()
expect(ordinary.writes, 0, "default runtime leaves textures unchanged")
expect(addon.CurrentProfile.IconSmoothing, false, "new profile defaults to disabled")
addon:SetIconSmoothing(true)
expect(ordinary.snap, false, "enable disables pixel snapping")
expect(ordinary.bias, 0, "enable removes snapping bias")
expect(unchanged.writes, 0, "already smooth texture is not owned")
expect(forbidden.writes, 0, "forbidden texture is untouched")
expect(hiddenSecret.writes, 0, "secret properties are untouched")
addon:ApplyMinimapSmoothing()
expect(ordinary.writes, 2, "reapply preserves the original snapshot")
addon:SetIconSmoothing(false)
expect(ordinary.snap, true, "disable restores original snap")
expect(ordinary.bias, 0.5, "disable restores original bias")

-- An intervening addon owns its new bias; restore only our remaining snap.
addon:SetIconSmoothing(true)
ordinary.bias = 0.25
addon:SetIconSmoothing(false)
expect(ordinary.snap, true, "independent snap restoration")
expect(ordinary.bias, 0.25, "another addon's bias is preserved")

-- Exercise actual profile switching, without running unrelated configuration.
addon.UpdateButtonAutoHide = function() end
addon.SchedulerLib = { ScheduleUniqueTask = function() end }
local panel = { IsVisible = function() return false end }
addon.OptionsPanel, addon.AppearancePanel = panel, panel
addon.ButtonOptionsPanel, addon.ProfilesPanel = panel, panel
addon:LoadProfile({IconSmoothing = true})
expect(ordinary.bias, 0, "saved true profile enables smoothing")
addon:LoadProfile({})
expect(ordinary.snap, true, "nil profile setting restores snap")
expect(ordinary.bias, 0.25, "nil profile setting restores latest original bias")
addon:LoadProfile({IconSmoothing = true})
addon:LoadProfile({IconSmoothing = false})
expect(ordinary.bias, 0.25, "explicit false profile restores bias")

-- A temporarily protected texture must be restored after it becomes writable.
addon:SetIconSmoothing(true)
ordinary.IsProtected = function() return true end
ordinary.CanChangeProtectedState = function() return false end
addon:SetIconSmoothing(false)
expect(ordinary.snap, false, "protected texture is not written")
ordinary.CanChangeProtectedState = function() return true end
addon:ApplyMinimapSmoothing()
expect(ordinary.snap, true, "pending restoration survives protected state")
expect(ordinary.bias, 0.25, "pending bias restoration survives protected state")

-- Events queue one deferred scan, rather than installing a recurring timer.
local queued
addon.SchedulerLib.ScheduleUniqueTask = function(_, delay, method, context)
    queued = {delay, method, context}
end
addon:MinimapSmoothingChanged()
expect(queued, nil, "disabled smoothing does not queue needless scans")
addon:SetIconSmoothing(true)
local fresh = texture(true, 0.75)
parent.GetRegions = function() return ordinary, fresh end
addon:MinimapSmoothingChanged()
queued[2](queued[3])
expect(fresh.bias, 0, "event scan smooths newly created regions")
addon:SetIconSmoothing(false)
expect(fresh.bias, 0.75, "event-created region restores its own original bias")

print("PASS: " .. checks .. " minimap-smoothing checks (Lua 5.1; simulated secrets)")
