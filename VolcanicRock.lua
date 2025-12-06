--[[
    DonHub - Volcanic Rock Hopper
    Type: Standalone Utility (No UI)
    Target: Volcanic Rock (World 2 Exclusive)
    
    Features:
    - Scans 'Island2VolcanicDepths' for Volcanic Rocks.
    - Loops W2 -> W1 -> W2 if no rocks found.
    - Spam-fires Teleport Remote to ensure success.
    - Auto-Reconnect Failsafe.
    - On-Screen HUD.
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
    HopDelay = 1,         -- Seconds to wait after confirming no rocks before hopping
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

--// HUD SETUP \\--
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DonHub_RockHUD"
if RunService:IsStudio() then ScreenGui.Parent = LocalPlayer.PlayerGui else ScreenGui.Parent = CoreGui end

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Parent = ScreenGui
StatusLabel.Size = UDim2.new(0.5, 0, 0.1, 0)
StatusLabel.Position = UDim2.new(0.25, 0, 0.05, 0)
StatusLabel.BackgroundColor3 = Color3.fromRGB(30, 0, 0) -- Red tint for Volcanic
StatusLabel.BackgroundTransparency = 0.5
StatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
StatusLabel.TextScaled = true
StatusLabel.Text = "Initializing Rock Scanner..."
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
    if not AreaFolder then return 0 end -- Likely in W1 or folder missing
    
    local Count = 0
    for _, SpawnLocation in pairs(AreaFolder:GetChildren()) do
        -- The rock model is named "Volcanic Rock" inside the SpawnLocation
        if SpawnLocation:FindFirstChild("Volcanic Rock") then
            -- Optional: Check if it has a Hitbox to ensure it's mineable
            if SpawnLocation["Volcanic Rock"]:FindFirstChild("Hitbox") then
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

    -- 2. Fallback: Check for W2 specific folder
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
        
        -- Loop Fire until we leave the server
        while true do
            UpdateHUD("Sending Teleport Request... (" .. IslandName .. ")")
            local Success, Err = pcall(function()
                Remote:InvokeServer(IslandName)
            end)
            
            if not Success then
                warn("Teleport Attempt Failed: " .. tostring(Err))
            end
            
            -- Wait 1.5 seconds before trying again to prevent crashing but ensure success
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
        local RockCount = 0
        
        if CurrentWorld == 2 then
            RockCount = GetVolcanicRockCount()
        end
        
        -- Update HUD
        UpdateHUD(string.format("W%d | Volcanic Rocks: %d", CurrentWorld, RockCount))

        -- LOGIC
        if CurrentWorld == 2 then
            if RockCount == 0 then
                -- Timer Logic to prevent instant hopping on load
                if ZeroRockStartTime == 0 then
                    ZeroRockStartTime = tick()
                end
                
                if tick() - ZeroRockStartTime >= UserConfig.HopDelay then
                    -- No rocks found in W2 -> Go to W1 to reset
                    TeleportToIslandLoop(ARG_TO_W1)
                end
            else
                ZeroRockStartTime = 0 -- Reset timer if rocks found
            end
        elseif CurrentWorld == 1 then
            -- We are in W1 -> Go to W2 immediately
            TeleportToIslandLoop(ARG_TO_W2)
        end
    end
end)
