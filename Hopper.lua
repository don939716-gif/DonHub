--[[
    DonHub - Headless Smart Hopper v1.2
    Type: Standalone Utility (No UI)
    Author: Don
    
    Updates:
    - Fixed World 2 Detection (Now checks for W2 mobs if ID fails).
    - Added Debug Prints to F9 Console.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

--// USER CONFIGURATION \\--
local UserConfig = {
    Enabled = true,       
    HopDelay = 1,         
    AutoReconnect = true, 
    Debug = true, -- Prints status to F9 Console
    
    Mobs = {
        -- World 1
        ["Zombie"] = false,
        ["Delver Zombie"] = false,
        ["EliteZombie"] = false,
        ["Brute Zombie"] = false,

        -- World 2
        ["Bomber"] = true, -- Enabled for testing
        ["Skeleton Rogue"] = false,
        ["Axe Skeleton"] = false,
        ["Deathaxe Skeleton"] = false,
        ["Slime"] = false,
        ["Blazing Slime"] = false,
        ["Elite Deathaxe Skeleton"] = false,
        ["Elite Rogue Skeleton"] = false,
        ["Reaper"] = false
    }
}

--// CONSTANTS \\--
local WORLD_1_ID = 76558904092080
local WORLD_2_ID = 129009554587176

local ARG_TO_W1 = "Stonewake's Cross"
local ARG_TO_W2 = "Forgotten Kingdom"

local W1_LIST = {"Zombie", "Delver Zombie", "EliteZombie", "Brute Zombie"}
local W2_LIST = {"Bomber", "Skeleton Rogue", "Axe Skeleton", "Deathaxe Skeleton", "Slime", "Blazing Slime", "Elite Deathaxe Skeleton", "Elite Rogue Skeleton", "Reaper"}

--// STATE \\--
local IsHopping = false

--// NOTIFICATION HELPER \\--
local function Notify(Title, Text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = Title,
            Text = Text,
            Duration = 5
        })
    end)
    if UserConfig.Debug then
        print("[DonHub Hopper]: " .. Text)
    end
end

--// AUTO RECONNECT FAILSAFE \\--
if UserConfig.AutoReconnect then
    task.spawn(function()
        local PromptGui = CoreGui:WaitForChild("RobloxPromptGui", 10)
        if not PromptGui then return end
        local Overlay = PromptGui:WaitForChild("promptOverlay", 10)
        if not Overlay then return end

        Overlay.ChildAdded:Connect(function(Child)
            if Child.Name == "ErrorPrompt" then
                IsHopping = true
                while true do
                    print("Disconnected! Attempting to Rejoin...")
                    pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
                    task.wait(5)
                end
            end
        end)
    end)
end

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
            if UserConfig.Mobs[CleanName] == true then
                Count = Count + 1
            end
        end
    end
    return Count
end

function DetermineCurrentWorld()
    -- 1. Check ID Match
    if game.PlaceId == WORLD_2_ID then return 2 end
    if game.PlaceId == WORLD_1_ID then return 1 end

    -- 2. Fallback: Check for unique mobs if ID doesn't match
    -- If we see a Slime or Bomber, we are definitely in World 2
    local Living = Workspace:FindFirstChild("Living")
    if Living then
        for _, v in pairs(Living:GetChildren()) do
            local Name = CleanMobName(v.Name)
            if table.find(W2_LIST, Name) then
                if UserConfig.Debug then print("Detected World 2 via Mob: " .. Name) end
                return 2
            end
        end
    end

    -- Default to 1 if unsure
    return 1
end

function TeleportToIsland(IslandName)
    if IsHopping then return end
    IsHopping = true
    
    Notify("Hopper", "Teleporting to " .. IslandName)
    
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
    
    Notify("Hopper", "Finding smallest server...")
    
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

function AnalyzeIntent()
    local WantsW1 = false
    local WantsW2 = false

    for MobName, Enabled in pairs(UserConfig.Mobs) do
        if Enabled then
            if table.find(W1_LIST, MobName) then WantsW1 = true end
            if table.find(W2_LIST, MobName) then WantsW2 = true end
        end
    end

    return WantsW1, WantsW2
end

--// MAIN LOOP \\--

Notify("DonHub", "Headless Hopper v1.2 Started")
if UserConfig.Debug then
    print("Current Place ID: " .. game.PlaceId)
end

task.spawn(function()
    while true do
        task.wait(1)
        if not UserConfig.Enabled or IsHopping then continue end

        local MobsRemaining = GetMobCount()
        local WantsW1, WantsW2 = AnalyzeIntent()
        local CurrentWorld = DetermineCurrentWorld()

        if MobsRemaining == 0 then
            task.wait(UserConfig.HopDelay)
            if GetMobCount() > 0 then continue end

            if UserConfig.Debug then
                print("Clearing... World: " .. CurrentWorld .. " | WantsW1: " .. tostring(WantsW1) .. " | WantsW2: " .. tostring(WantsW2))
            end

            -- LOGIC TREE
            if WantsW1 and not WantsW2 then
                -- Only W1 Mobs
                if CurrentWorld == 1 then
                    ServerHop()
                else
                    TeleportToIsland(ARG_TO_W1)
                end

            elseif not WantsW1 and WantsW2 then
                -- Only W2 Mobs
                if CurrentWorld == 2 then
                    -- We are in W2, mobs are dead. Go to W1 to reset.
                    TeleportToIsland(ARG_TO_W1) 
                else
                    -- We are in W1, go to W2.
                    TeleportToIsland(ARG_TO_W2)
                end

            elseif WantsW1 and WantsW2 then
                -- Mixed Mobs
                if CurrentWorld == 1 then
                    TeleportToIsland(ARG_TO_W2)
                else
                    TeleportToIsland(ARG_TO_W1)
                end
            end
        end
    end
end)
