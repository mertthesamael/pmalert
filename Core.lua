local ADDON_NAME = ...

TestAddonNS = TestAddonNS or {}
local ns = TestAddonNS

PMAlertDB = PMAlertDB or {}

-- Legacy installs only had colorR/G/B; convert once so the settings color swatch can use colorHex.
if PMAlertDB.colorHex == nil and PMAlertDB.colorR ~= nil then
    PMAlertDB.colorHex = CreateColor(
        PMAlertDB.colorR or 1,
        PMAlertDB.colorG or 0.2,
        PMAlertDB.colorB or 0.7,
        1
    ):GenerateHexColor()
end

ns.defaults = {
    colorHex = CreateColor(1, 0.2, 0.7, 1):GenerateHexColor(),
    edgeSize = 26,
    alphaMax = 0.5,
    flashDuration = 1,
}

ns.sliderBounds = {
    flashDuration = { min = 0.15, max = 3, step = 0.05 },
    alphaMax = { min = 0.1, max = 1, step = 0.05 },
    edgeSize = { min = 24, max = 160, step = 2 },
}

for k, v in pairs(ns.defaults) do
    if PMAlertDB[k] == nil then
        PMAlertDB[k] = v
    end
end

local config = {}

--- Blizzard color swatch / chat codes may differ slightly from strict AARRGGBB.
local function NormalizeColorHexString(raw)
    if type(raw) ~= "string" or raw == "" then
        return nil
    end
    local s = raw:match("^|c([0-9a-fA-F]+)") or raw:match("^#([0-9a-fA-F]+)") or raw
    s = s:gsub("%s", ""):upper()
    if not s:match("^[0-9A-F]+$") then
        return nil
    end
    if #s == 6 then
        return "FF" .. s
    end
    if #s == 8 then
        return s
    end
    return nil
end

local function HexStringToRGB(hexRaw)
    local norm = NormalizeColorHexString(hexRaw)
    if not norm then
        return nil
    end
    local c = CreateColorFromHexString(norm)
    if not c then
        return nil
    end
    return c:GetRGB()
end

local function SettingsGetNumber(variable, fallback)
    if Settings and Settings.GetValue then
        local ok, v = pcall(Settings.GetValue, variable)
        if ok and type(v) == "number" then
            return v
        end
    end
    return fallback
end

local function SnapNumber(value, minV, maxV, step)
    if type(value) ~= "number" then
        return minV
    end
    value = math.max(minV, math.min(maxV, value))
    if not step or step <= 0 then
        return value
    end
    local n = math.floor((value - minV) / step + 0.5)
    return minV + n * step
end

function ns.CommitSliderToDB(key, rawValue)
    local b = ns.sliderBounds[key]
    if not b or type(rawValue) ~= "number" then
        return
    end
    local snapped = SnapNumber(rawValue, b.min, b.max, b.step)
    if key == "edgeSize" then
        PMAlertDB[key] = math.floor(snapped + 0.5)
    else
        PMAlertDB[key] = snapped
    end
end

local function SyncConfigFromDB()
    local db = PMAlertDB
    local b = ns.sliderBounds

    local durRaw = SettingsGetNumber("PMAlert_FlashDuration", db.flashDuration)
    local alphaRaw = SettingsGetNumber("PMAlert_AlphaMax", db.alphaMax)
    local edgeRaw = SettingsGetNumber("PMAlert_EdgeSize", db.edgeSize)

    config.flashDuration = SnapNumber(durRaw, b.flashDuration.min, b.flashDuration.max, b.flashDuration.step)
    config.alphaMax = SnapNumber(alphaRaw, b.alphaMax.min, b.alphaMax.max, b.alphaMax.step)
    config.edgeSize = math.floor(SnapNumber(edgeRaw, b.edgeSize.min, b.edgeSize.max, b.edgeSize.step) + 0.5)

    local hex = db.colorHex
    if Settings and Settings.GetValue then
        local ok, fromSettings = pcall(Settings.GetValue, "PMAlert_FlashColor")
        if ok and fromSettings ~= nil and fromSettings ~= "" then
            hex = fromSettings
        end
    end

    local r, g, b = HexStringToRGB(hex)
    if not r then
        r, g, b = HexStringToRGB(db.colorHex)
    end
    if r then
        config.color = { r, g, b }
    else
        config.color = { 1, 0.2, 0.7 }
    end
end

SyncConfigFromDB()

local frame = CreateFrame("Frame")

local overlay = CreateFrame("Frame", "PMAlertOverlay", UIParent)
overlay:SetAllPoints(UIParent)
overlay:Hide()
overlay:SetFrameStrata("FULLSCREEN_DIALOG")
overlay:SetFrameLevel(100)

local edges = {}
local persistentWhisperFlash = false
local whisperWatchdog = nil
local chatReadHooksRegistered = false

--- Intensity is baked into gradient alphas. Retail WoW often ignores Texture:SetAlpha on gradient fills,
--- so pulsing must vary CreateColor(..., a) instead of SetAlpha.
local function ApplyEdgeGradient(tex, edgeKind, outerAlpha)
    outerAlpha = math.min(1, math.max(0, outerAlpha or 0))
    local r, g, b = config.color[1], config.color[2], config.color[3]
    local clear = CreateColor(r, g, b, 0)
    local solid = CreateColor(r, g, b, outerAlpha)
    tex:SetTexture("Interface/Buttons/WHITE8x8")
    if edgeKind == "top" then
        tex:SetGradient("VERTICAL", clear, solid)
    elseif edgeKind == "bottom" then
        tex:SetGradient("VERTICAL", solid, clear)
    elseif edgeKind == "left" then
        tex:SetGradient("HORIZONTAL", solid, clear)
    elseif edgeKind == "right" then
        tex:SetGradient("HORIZONTAL", clear, solid)
    end
    tex:SetAlpha(1)
end

local function SetEdgesGradientIntensity(outerAlpha)
    outerAlpha = math.min(1, math.max(0, outerAlpha))
    overlay.pulseOuterAlpha = outerAlpha
    if not edges.top then
        return
    end
    ApplyEdgeGradient(edges.top, "top", outerAlpha)
    ApplyEdgeGradient(edges.bottom, "bottom", outerAlpha)
    ApplyEdgeGradient(edges.left, "left", outerAlpha)
    ApplyEdgeGradient(edges.right, "right", outerAlpha)
end

local function CreateGradientEdge(parent, point, width, height, edgeKind)
    local tex = parent:CreateTexture(nil, "OVERLAY")
    tex:SetPoint(point, parent, point, 0, 0)
    tex:SetSize(width, height)
    ApplyEdgeGradient(tex, edgeKind, 0)
    return tex
end

local function BuildOverlay()
    edges.top = CreateGradientEdge(overlay, "TOP", UIParent:GetWidth(), config.edgeSize, "top")
    edges.bottom = CreateGradientEdge(overlay, "BOTTOM", UIParent:GetWidth(), config.edgeSize, "bottom")
    edges.left = CreateGradientEdge(overlay, "LEFT", config.edgeSize, UIParent:GetHeight(), "left")
    edges.right = CreateGradientEdge(overlay, "RIGHT", config.edgeSize, UIParent:GetHeight(), "right")
end

local function RefreshColors()
    local a = overlay.pulseOuterAlpha or 0
    SetEdgesGradientIntensity(a)
end

local function UpdateEdgeSizes()
    if not edges.top then return end

    edges.top:SetSize(UIParent:GetWidth(), config.edgeSize)
    edges.bottom:SetSize(UIParent:GetWidth(), config.edgeSize)
    edges.left:SetSize(config.edgeSize, UIParent:GetHeight())
    edges.right:SetSize(config.edgeSize, UIParent:GetHeight())
end

function ns.ApplySavedVariables()
    SyncConfigFromDB()
    RefreshColors()
    UpdateEdgeSizes()
end

local SETTINGS_NOTIFY_KEYS = {
    "PMAlert_FlashColor",
    "PMAlert_FlashDuration",
    "PMAlert_AlphaMax",
    "PMAlert_EdgeSize",
}

function ns.NotifySettingsUI()
    if not Settings or not Settings.NotifyUpdate then
        return
    end
    for _, key in ipairs(SETTINGS_NOTIFY_KEYS) do
        Settings.NotifyUpdate(key)
    end
end

local function CancelWhisperWatchdog()
    if whisperWatchdog then
        whisperWatchdog:Cancel()
        whisperWatchdog = nil
    end
end

local function StopPersistentWhisperFlash()
    persistentWhisperFlash = false
    CancelWhisperWatchdog()
    overlay:SetScript("OnUpdate", nil)
    overlay.pulseOuterAlpha = 0
    if edges.top then
        SetEdgesGradientIntensity(0)
    end
    overlay:Hide()
end

local function Overlay_PulseOnUpdate(_, elapsed)
    SyncConfigFromDB()
    local period = math.max(0.6, 0.24 + 2 * config.flashDuration)
    overlay.pulsePhase = (overlay.pulsePhase or 0) + elapsed
    local t = overlay.pulsePhase % period
    local w = (math.sin(t / period * math.pi * 2) + 1) / 2
    local outer = w * config.alphaMax
    SetEdgesGradientIntensity(outer)
end

local function StartPersistentWhisperFlash()
    StopPersistentWhisperFlash()
    persistentWhisperFlash = true
    SyncConfigFromDB()
    UpdateEdgeSizes()
    RefreshColors()
    overlay.pulsePhase = 0
    overlay:SetScript("OnUpdate", Overlay_PulseOnUpdate)
    overlay:Show()

    CancelWhisperWatchdog()
    if C_Timer and C_Timer.NewTimer then
        whisperWatchdog = C_Timer.NewTimer(600, function()
            whisperWatchdog = nil
            StopPersistentWhisperFlash()
        end)
    end
end

local function OnChatInteracted()
    if persistentWhisperFlash then
        StopPersistentWhisperFlash()
    end
end

local function RegisterChatReadHooks()
    if chatReadHooksRegistered then
        return
    end
    chatReadHooksRegistered = true

    local function hookMouseDown(frame)
        if frame and frame.HookScript then
            frame:HookScript("OnMouseDown", OnChatInteracted)
        end
    end

    for i = 1, NUM_CHAT_WINDOWS do
        hookMouseDown(_G["ChatFrame" .. i])
        hookMouseDown(_G["FloatingChatFrame" .. i])
        hookMouseDown(_G["ChatFrame" .. i .. "Tab"])
    end

    if FCF_Tab_OnClick then
        hooksecurefunc("FCF_Tab_OnClick", function()
            OnChatInteracted()
        end)
    end
end

local function PlayPMAlertSound()
    PlaySound(SOUNDKIT.TELL_MESSAGE)
end

local function PrintMsg(msg)
    print("|cffFF4DB8PM Alert:|r " .. msg)
end

local function ShowHelp()
    PrintMsg("Commands:")
    PrintMsg("/pmalert options — open settings")
    PrintMsg("/pmalert test — same pulse as a whisper (stop by clicking chat or /pmalert dismiss)")
    PrintMsg("/pmalert dismiss — stop pulse")
    PrintMsg("/pmalert pink — default pink color")
    PrintMsg("Pulse stops when you click the chat window or a chat tab.")
    PrintMsg("/pmalert help")
end

local function OpenOptions()
    local category = ns.settingsCategory
    if not category or not Settings or not Settings.OpenToCategory then
        PrintMsg("Open Escape → Options → AddOns → PM Alert (settings not available on this client).")
        return
    end
    local id = category.GetID and category:GetID() or nil
    local function openPanel()
        if id == nil then
            PrintMsg("Could not open PM Alert automatically. Use Escape → Options → AddOns → PM Alert.")
            return
        end
        Settings.OpenToCategory(id)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, openPanel)
    else
        openPanel()
    end
end

local function HandleSlashCommand(input)
    input = (input or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if input == "" or input == "help" then
        ShowHelp()
        return
    end

    if input == "options" or input == "config" then
        OpenOptions()
        return
    end

    if input == "test" then
        PlayPMAlertSound()
        StartPersistentWhisperFlash()
        PrintMsg("Test pulse running. Click the chat window or use /pmalert dismiss to stop.")
        return
    end

    if input == "dismiss" or input == "stop" then
        StopPersistentWhisperFlash()
        PrintMsg("Pulse stopped.")
        return
    end

    if input == "pink" then
        PMAlertDB.colorHex = ns.defaults.colorHex
        ns.ApplySavedVariables()
        ns.NotifySettingsUI()
        PrintMsg("Pink color restored.")
        return
    end

    PrintMsg("Unknown command: " .. input)
    ShowHelp()
end

local function OnEvent(_, event, message, sender)
    if event == "PLAYER_LOGIN" then
        BuildOverlay()
        RegisterChatReadHooks()

        SLASH_PMALERT1 = "/pmalert"
        SlashCmdList["PMALERT"] = function(msg)
            HandleSlashCommand(msg)
        end

        PrintMsg("Loaded. /pmalert options or /pmalert help")
        return
    end

    if event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER" then
        PlayPMAlertSound()
        StartPersistentWhisperFlash()
        PrintMsg(string.format("Whisper from %s", sender or "Unknown"))
    end
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:RegisterEvent("CHAT_MSG_BN_WHISPER")
frame:RegisterEvent("UI_SCALE_CHANGED")
frame:RegisterEvent("DISPLAY_SIZE_CHANGED")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        UpdateEdgeSizes()
        RefreshColors()
        return
    end

    OnEvent(self, event, ...)
end)
