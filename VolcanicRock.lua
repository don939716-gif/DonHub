--[[
    DonHub - Volcanic Rock Hopper v1.1
    Type: Standalone Utility (No UI)
    Target: Volcanic Rock (World 2 Exclusive)
    
    Updates:
    - Added Stagnation/Stale Check (Hops if count doesn't decrease for 60s).
    - Added Visual Countdown to HUD.
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
    HopDelay = 2,         -- Seconds to wait after 0 rocks found
    StaleTimeout = 60,    -- Seconds to wait if rock count doesn't decrease
    AutoReconnect = true, 
}

--// CONSTANTS \\--
local WORLD_1_ID = 76558904092080
local WORLD_2_ID = 129009554587176

local ARG_TO_W1 = "Stonewake's Cross"
local ARG_TO_W2 = "Forgotten Kingdom"

--// STATE \\--
local IsHopping = false
local ZeroRockStartTime = 0

-- Stagnation State
local LastRockCount = -1
local StagnantStartTime = 0

--// HUD SETUP \\--
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DonHub_RockHUD"
if RunService:IsStudio() then ScreenGui.Parent = LocalPlayer.PlayerGui else ScreenGui.Parent = CoreGui end

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Parent = ScreenGui
StatusLabel.Size = UDim2.new(0.5, 0, 0.1, 0)
StatusLabel.Position = UDim2.new(0.25, 0, 0.05, 0)
StatusLabel.BackgroundColor3 = Color3.fromRGB(30, 0, 0) 
StatusLabel.BackgroundTransparency = 0.5
StatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
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

function GetVolcanicRockCount()
    local RocksFolder = Workspace:FindFirstChild("Rocks")
    if not RocksFolder then return 0 end
    
    local AreaFolder = RocksFolder:FindFirstChild("Island2VolcanicDepths")
    if not AreaFolder then return 0 end 
    
    local Count = 0
    for _, SpawnLocation in pairs(AreaFolder:GetChildren()) do
        if SpawnLocation:FindFirstChild("Volcanic Rock") then
            if SpawnLocation["Volcanic Rock"]:FindFirstChild("Hitbox") then
                Count = Count + 1
            end
        end
    end
    return Count
end

function DetermineCurrentWorld()
    if game.PlaceId == WORLD_2_ID then return 2 end
    if game.PlaceId == WORLD_1_ID then return 1 end

    if Workspace:FindFirstChild("Rocks") and Workspace.Rocks:FindFirstChild("Island2VolcanicDepths") then
        return 2
    end

    return 1
end

function TeleportToIslandLoop(IslandName)
    if IsHopping then return end
    IsHopping = true
    
    UpdateHUD("Teleporting to: " .. IslandName)
    
    task.spawn(function()
        local Remote = ReplicatedStorage.Shared.Packages.Knit.Services.PortalService.RF.TeleportToIsland
        
        while true do
            UpdateHUD("Sending Teleport Request... (" .. IslandName .. ")")
            local Success, Err = pcall(function()
                Remote:InvokeServer(IslandName)
            end)
            
            if not Success then
                warn("Teleport Attempt Failed: " .. tostring(Err))
            end
            
            task.wait(1.5)
        end
    end)
end

--// MAIN LOOP \\--

task.spawn(function()
    while true do
        task.wait(1)
        if not UserConfig.Enabled or IsHopping then continue end

        local CurrentWorld = DetermineCurrentWorld()
        
        if CurrentWorld == 2 then
            local CurrentRockCount = GetVolcanicRockCount()
            local TimeSinceStagnant = tick() - StagnantStartTime
            local TimeRemaining = math.max(0, UserConfig.StaleTimeout - TimeSinceStagnant)
            
            -- HUD Update
            if CurrentRockCount > 0 then
                UpdateHUD(string.format("W2 | Rocks: %d | Stale: %ds", CurrentRockCount, math.floor(TimeSinceStagnant)))
            else
                UpdateHUD("W2 | Rocks: 0 | Hopping...")
            end

            -- LOGIC: Zero Rocks
            if CurrentRockCount == 0 then
                if ZeroRockStartTime == 0 then ZeroRockStartTime = tick() end
                
                if tick() - ZeroRockStartTime >= UserConfig.HopDelay then
                    TeleportToIslandLoop(ARG_TO_W1)
                end
                
                -- Reset Stagnant logic since we are at 0
                LastRockCount = 0
                StagnantStartTime = tick()
                
            -- LOGIC: Rocks Exist
            else
                ZeroRockStartTime = 0 -- Reset zero timer
                
                if CurrentRockCount < LastRockCount then
                    -- Progress made! Reset timer
                    LastRockCount = CurrentRockCount
                    StagnantStartTime = tick()
                elseif CurrentRockCount > LastRockCount then
                    -- Rocks respawned or just joined? Reset timer
                    LastRockCount = CurrentRockCount
                    StagnantStartTime = tick()
                else
                    -- Count is same (Stagnant)
                    if TimeSinceStagnant >= UserConfig.StaleTimeout then
                        UpdateHUD("Server Stale! Hopping...")
                        task.wait(1)
                        TeleportToIslandLoop(ARG_TO_W1)
                    end
                end
            end
            
        elseif CurrentWorld == 1 then
            UpdateHUD("W1 Detected -> Going to W2")
            TeleportToIslandLoop(ARG_TO_W2)
        end
    end
end)
