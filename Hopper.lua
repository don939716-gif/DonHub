--[[
    DonHub - Smart Hopper v1.2
    Type: Standalone Utility
    Author: Don
    
    INSTRUCTIONS FOR AUTO-EXECUTE:
    1. Save this entire script as a file named "DonHub_Hopper.lua" 
       inside your Executor's "workspace" or "scripts" folder.
    2. Run it once. 
    3. Configure your mobs. It will AUTO-SAVE.
    4. When it hops, it will reload your settings automatically.
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
    HopDelay = 3, -- Seconds to wait after clearing before hopping
    FileName = "DonHub_Hopper.lua" -- The name of the file you saved
}

--// STATE \\--
local IsHopping = false
local IsLoading = false -- Prevent saving while loading

--// UI SETUP \\--
local Window = Fluent:CreateWindow({
    Title = "DonHub | Smart Hopper",
    SubTitle = "v1.2",
    TabWidth = 160,
    Size = UDim2.fromOffset(480, 360),
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

function TriggerAutoSave()
    if not IsLoading then
        SaveManager:Save("AutoSave")
    end
end

--// AUTO EXECUTE LOGIC \\--
function QueueAutoExecute()
    local queue_on_teleport = queue_on_teleport or (syn and syn.queue_on_teleport)
    
    if queue_on_teleport then
        -- This script string runs immediately after teleporting
        local Payload = [[
            task.wait(5) -- Wait for game to load
            local FileName = "]] .. Config.FileName .. [["
            if isfile(FileName) then
                loadstring(readfile(FileName))()
            else
                warn("DonHub AutoExec: Could not find file " .. FileName)
            end
        ]]
        queue_on_teleport(Payload)
    end
end

function TeleportToIsland(IslandName)
    if IsHopping then return end
    IsHopping = true
    
    Fluent:Notify({Title = "Hopper", Content = "Teleporting to " .. IslandName, Duration = 5})
    QueueAutoExecute() -- Queue the script to run next server
    
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
    QueueAutoExecute() -- Queue the script to run next server
    
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

        if MobsRemaining == 0 then
            task.wait(Config.HopDelay)
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
            end
        end
    end
end)

--// UI ELEMENTS \\--

local Toggle = Tabs.Main:AddToggle("EnableHopper", {Title = "Enable Smart Hopper", Default = false })
Toggle:OnChanged(function(Value)
    Config.Enabled = Value
    IsHopping = false
    TriggerAutoSave()
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
    TriggerAutoSave()
end)

Tabs.Main:AddInput("FileNameInput", {
    Title = "Script File Name",
    Description = "Must match the file you saved in workspace.",
    Default = "DonHub_Hopper.lua",
    Placeholder = "DonHub_Hopper.lua",
    Numeric = false,
    Finished = true,
    Callback = function(Value)
        Config.FileName = Value
        TriggerAutoSave()
    end
})

Tabs.Main:AddParagraph({
    Title = "Auto-Execute Info",
    Content = "For Auto-Execute to work, save this script as 'DonHub_Hopper.lua' in your executor's workspace folder."
})

--// SAVE MANAGER \\--
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
SaveManager:SetFolder("DonHub_Hopper")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

--// AUTO LOAD \\--
IsLoading = true
if isfile("DonHub_Hopper/AutoSave.json") then
    SaveManager:Load("AutoSave")
end
IsLoading = false

Window:SelectTab(1)
Fluent:Notify({
    Title = "DonHub Hopper",
    Content = "Loaded & Config Restored",
    Duration = 5
})
