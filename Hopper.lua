--[[
    DonHub - Headless Smart Hopper v1.3
    Type: Standalone Utility (No UI)
    Author: Don
    
    Updates:
    - Added On-Screen HUD for Mobile Debugging.
    - Added "Stuck Failsafe" to force rotation if PlaceID detection fails.
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
    HopDelay = 3,         
    AutoReconnect = true, 
    
    Mobs = {
        -- World 1
        ["Zombie"] = false,
        ["Delver Zombie"] = false,
        ["EliteZombie"] = false,
        ["Brute Zombie"] = false,

        -- World 2
        ["Bomber"] = true, -- Enabled
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
local ZeroMobStartTime = 0

--// HUD SETUP (Mobile Debug) \\--
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DonHub_DebugHUD"
if RunService:IsStudio() then ScreenGui.Parent = LocalPlayer.PlayerGui else ScreenGui.Parent = CoreGui end

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Parent = ScreenGui
StatusLabel.Size = UDim2.new(0.5, 0, 0.1, 0)
StatusLabel.Position = UDim2.new(0.25, 0, 0.05, 0)
StatusLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
StatusLabel.BackgroundTransparency = 0.5
StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
StatusLabel.TextScaled = true
StatusLabel.Text = "Initializing..."
StatusLabel.BorderSizePixel = 0
local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 8)
UICorner.Parent = StatusLabel

function UpdateHUD(Text)
    StatusLabel.Text = Text
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
                UpdateHUD("DISCONNECTED - REJOINING...")
                while true do
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

    -- 2. Fallback: Check for unique mobs
    local Living = Workspace:FindFirstChild("Living")
    if Living then
        for _, v in pairs(Living:GetChildren()) do
            local Name = CleanMobName(v.Name)
            if table.find(W2_LIST, Name) then return 2 end
        end
    end

    -- Default to 1 if unsure (This is what causes the bug if W2 mobs are dead)
    return 1
end

function TeleportToIsland(IslandName)
    if IsHopping then return end
    IsHopping = true
    
    UpdateHUD("Teleporting to: " .. IslandName)
    
    task.spawn(function()
        local Remote = ReplicatedStorage.Shared.Packages.Knit.Services.PortalService.RF.TeleportToIsland
        local Success, Err = pcall(function()
            Remote:InvokeServer(IslandName)
        end)
        
        if not Success then
            UpdateHUD("Teleport Failed!")
            task.wait(2)
            IsHopping = false
        end
    end)
end

function ServerHop()
    if IsHopping then return end
    IsHopping = true
    
    UpdateHUD("Hopping Server...")
    
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

task.spawn(function()
    while true do
        task.wait(1)
        if not UserConfig.Enabled or IsHopping then continue end

        local MobsRemaining = GetMobCount()
        local WantsW1, WantsW2 = AnalyzeIntent()
        local CurrentWorld = DetermineCurrentWorld()
        
        -- Update HUD
        UpdateHUD(string.format("W%d | Mobs: %d | ID: %d", CurrentWorld, MobsRemaining, game.PlaceId))

        if MobsRemaining == 0 then
            -- Timer Logic for Stuck Failsafe
            if ZeroMobStartTime == 0 then
                ZeroMobStartTime = tick()
            end
            
            -- Wait delay
            if tick() - ZeroMobStartTime < UserConfig.HopDelay then
                continue
            end
            
            -- STUCK FAILSAFE:
            -- If we have 0 mobs for > 10 seconds, and we are farming W2, force a reset to W1.
            -- This handles the case where the script thinks we are in W1 but we are actually in W2.
            if tick() - ZeroMobStartTime > 10 and WantsW2 and not WantsW1 then
                 UpdateHUD("Stuck Detected! Forcing W1 Reset...")
                 TeleportToIsland(ARG_TO_W1)
                 continue
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
                    TeleportToIsland(ARG_TO_W1) -- Loop via W1
                else
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
        else
            ZeroMobStartTime = 0 -- Reset timer if mobs found
        end
    end
end)
