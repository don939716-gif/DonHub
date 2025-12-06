--[[
    DonHub - Headless Smart Hopper
    Type: Standalone Utility (No UI)
    Author: Don
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

--// USER CONFIGURATION \\--
-- Set these to true/false based on what you are farming.
local UserConfig = {
    Enabled = true,       -- Master switch
    HopDelay = 3,         -- Seconds to wait after clearing mobs before hopping
    
    Mobs = {
        -- World 1
        ["Zombie"] = false,
        ["Delver Zombie"] = true,
        ["EliteZombie"] = false,
        ["Brute Zombie"] = false,

        -- World 2
        ["Bomber"] = true,
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
    StarterGui:SetCore("SendNotification", {
        Title = Title,
        Text = Text,
        Duration = 5
    })
    print("[DonHub Hopper]: " .. Text)
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
            -- Check if this specific mob is enabled in config
            if UserConfig.Mobs[CleanName] == true then
                Count = Count + 1
            end
        end
    end
    return Count
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

Notify("DonHub", "Headless Hopper Started")

task.spawn(function()
    while true do
        task.wait(1)
        if not UserConfig.Enabled or IsHopping then continue end

        local MobsRemaining = GetMobCount()
        local WantsW1, WantsW2 = AnalyzeIntent()
        local CurrentWorld = (game.PlaceId == WORLD_2_ID) and 2 or 1

        if MobsRemaining == 0 then
            -- Wait delay to ensure spawns aren't just lagging
            task.wait(UserConfig.HopDelay)
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
