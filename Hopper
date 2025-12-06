--[[
    DonHub - Smart Hopper
    Type: Standalone Utility
    Author: Don
]]

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlaceId = game.PlaceId

--// CONSTANTS \\--
local WORLD_1_ID = 76558904092080
local WORLD_2_ID = 129009554587176

local ARG_TO_W1 = "Stonewake's Cross"
local ARG_TO_W2 = "Forgotten Kingdom"

local W1_MOBS = {
    "Zombie", "Delver Zombie", "EliteZombie", "Brute Zombie"
}

local W2_MOBS = {
    "Bomber", "Skeleton Rogue", "Axe Skeleton", "Deathaxe Skeleton", 
    "Slime", "Blazing Slime", "Elite Deathaxe Skeleton", 
    "Elite Rogue Skeleton", "Reaper"
}

--// CONFIGURATION \\--
local Config = {
    Enabled = false,
    SelectedMobs = {},
    HopDelay = 3 -- Seconds to wait after clearing before hopping
}

--// STATE \\--
local IsHopping = false

--// UI SETUP \\--
local Window = Fluent:CreateWindow({
    Title = "DonHub | Smart Hopper",
    SubTitle = "Utility",
    TabWidth = 160,
    Size = UDim2.fromOffset(480, 360), -- Smaller window for utility
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Hopper", Icon = "map" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

--// HELPER FUNCTIONS \\--

function CleanMobName(Name)
    return string.gsub(Name, "%d+$", "")
end

function GetMobCount()
    local Count = 0
    local Living = Workspace:FindFirstChild("Living")
    if not Living then return 0 end

    for _, Model in pairs(Living:GetChildren()) do
        if not Players:GetPlayerFromCharacter(Model) and Model:FindFirstChild("Humanoid") and Model.Humanoid.Health > 0 then
            local CleanName = CleanMobName(Model.Name)
            if table.find(Config.SelectedMobs, CleanName) then
                Count = Count + 1
            end
        end
    end
    return Count
end

function TeleportToIsland(IslandName)
    if IsHopping then return end
    IsHopping = true
    
    Fluent:Notify({Title = "Hopper", Content = "Teleporting to " .. IslandName, Duration = 5})
    
    task.spawn(function()
        local Remote = ReplicatedStorage.Shared.Packages.Knit.Services.PortalService.RF.TeleportToIsland
        local Success, Err = pcall(function()
            Remote:InvokeServer(IslandName)
        end)
        
        if not Success then
            warn("Teleport Failed: " .. tostring(Err))
            IsHopping = false
        end
    end)
end

function ServerHop()
    if IsHopping then return end
    IsHopping = true
    
    Fluent:Notify({Title = "Hopper", Content = "Finding smallest server...", Duration = 10})
    
    task.spawn(function()
        while task.wait(1) do
            pcall(function()
                local Servers = HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")).data
                for _, Server in ipairs(Servers) do
                    if Server.playing < Server.maxPlayers and Server.id ~= game.JobId then
                        TeleportService:TeleportToPlaceInstance(game.PlaceId, Server.id, LocalPlayer)
                        return
                    end
                end
            end)
        end
    end)
end

--// LOGIC ENGINE \\--

function AnalyzeIntent()
    local WantsW1 = false
    local WantsW2 = false

    for _, Mob in pairs(Config.SelectedMobs) do
        if table.find(W1_MOBS, Mob) then WantsW1 = true end
        if table.find(W2_MOBS, Mob) then WantsW2 = true end
    end

    return WantsW1, WantsW2
end

task.spawn(function()
    while true do
        task.wait(1)
        if not Config.Enabled or IsHopping then continue end

        local MobsRemaining = GetMobCount()
        local WantsW1, WantsW2 = AnalyzeIntent()
        local CurrentWorld = (game.PlaceId == WORLD_2_ID) and 2 or 1

        -- Update Status UI (Optional, printed to console for now)
        -- print("Mobs Left: " .. MobsRemaining .. " | W1: " .. tostring(WantsW1) .. " | W2: " .. tostring(WantsW2))

        if MobsRemaining == 0 then
            task.wait(Config.HopDelay)
            -- Double check after delay
            if GetMobCount() > 0 then continue end

            -- LOGIC TREE
            if WantsW1 and not WantsW2 then
                -- CASE: Only W1 Mobs
                if CurrentWorld == 1 then
                    ServerHop() -- Smallest Server Hop
                else
                    TeleportToIsland(ARG_TO_W1) -- Go back to W1
                end

            elseif not WantsW1 and WantsW2 then
                -- CASE: Only W2 Mobs
                if CurrentWorld == 2 then
                    TeleportToIsland(ARG_TO_W1) -- Go to W1 to reset (Loop)
                else
                    TeleportToIsland(ARG_TO_W2) -- Go to W2
                end

            elseif WantsW1 and WantsW2 then
                -- CASE: Mixed Mobs
                if CurrentWorld == 1 then
                    TeleportToIsland(ARG_TO_W2) -- Finished W1, go W2
                else
                    TeleportToIsland(ARG_TO_W1) -- Finished W2, go W1
                end
            else
                -- No mobs selected? Do nothing.
            end
        end
    end
end)

--// UI ELEMENTS \\--

local Toggle = Tabs.Main:AddToggle("EnableHopper", {Title = "Enable Smart Hopper", Default = false })
Toggle:OnChanged(function(Value)
    Config.Enabled = Value
    IsHopping = false
end)

local MobDropdown = Tabs.Main:AddDropdown("MobSelect", {
    Title = "Select Mobs to Monitor",
    Description = "Hopper will trigger when NONE of these are alive.",
    Values = (function() 
        local T = {}
        for _, v in pairs(W1_MOBS) do table.insert(T, v) end
        for _, v in pairs(W2_MOBS) do table.insert(T, v) end
        table.sort(T)
        return T
    end)(),
    Multi = true,
    Default = {},
})

MobDropdown:OnChanged(function(Value)
    Config.SelectedMobs = {}
    for Name, Selected in pairs(Value) do
        if Selected then table.insert(Config.SelectedMobs, Name) end
    end
end)

Tabs.Main:AddParagraph({
    Title = "Logic Explanation",
    Content = "1. Only W1 Mobs: Hops to small W1 server.\n2. Only W2 Mobs: Loops W1 <-> W2.\n3. Mixed Mobs: Clears current world, then switches."
})

--// SAVE MANAGER \\--
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
SaveManager:SetFolder("DonHub_Hopper")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)
Fluent:Notify({
    Title = "DonHub Hopper",
    Content = "Loaded Successfully",
    Duration = 5
})
