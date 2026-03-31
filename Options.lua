local _ADDON_NAME = ...
local ns = TestAddonNS

if not ns or not Settings or not Settings.RegisterVerticalLayoutCategory then
    return
end

local db = PMAlertDB
local d = ns.defaults
local category = Settings.RegisterVerticalLayoutCategory("PM Alert")

local function addColorSwatch(variable, key, name, tooltip)
    local def = d[key]
    local setting = Settings.RegisterAddOnSetting(category, variable, key, db, type(def), name, def)
    setting:SetValueChangedCallback(function()
        local v = setting:GetValue()
        if type(v) == "string" and v ~= "" then
            db[key] = v
        elseif type(v) == "table" then
            if v.GetRGBA then
                db[key] = v:GenerateHexColor()
            elseif v.r and v.g and v.b then
                db[key] = CreateColor(v.r, v.g, v.b, v.a or 1):GenerateHexColor()
            end
        end
        ns.ApplySavedVariables()
    end)
    Settings.CreateColorSwatch(category, setting, tooltip)
end

local function addSlider(variable, key, name, tooltip, minV, maxV, step)
    local def = d[key]
    local setting = Settings.RegisterAddOnSetting(category, variable, key, db, type(def), name, def)
    setting:SetValueChangedCallback(function()
        ns.CommitSliderToDB(key, setting:GetValue())
        ns.ApplySavedVariables()
    end)

    local options = Settings.CreateSliderOptions(minV, maxV, step)
    if options.SetLabelFormatter and MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
    end

    Settings.CreateSlider(category, setting, options, tooltip)
end

addColorSwatch(
    "PMAlert_FlashColor",
    "colorHex",
    "Flash color",
    "Uses the game color picker (including hex). This is the color of the whisper edge flash."
)

addSlider(
    "PMAlert_FlashDuration",
    "flashDuration",
    "Fade-out duration",
    "How long the flash takes to fade out after the peak (seconds).",
    0.15,
    3,
    0.05
)

addSlider(
    "PMAlert_AlphaMax",
    "alphaMax",
    "Flash intensity",
    "How strong the flash is at its brightest (0.1–1).",
    0.1,
    1,
    0.05
)

addSlider(
    "PMAlert_EdgeSize",
    "edgeSize",
    "Edge thickness",
    "Height or width of the gradient band in pixels (larger = softer, wider glow).",
    24,
    160,
    2
)

Settings.RegisterAddOnCategory(category)
ns.settingsCategory = category
