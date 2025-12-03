--[[
    DonHub - Parry Timing Logger
    Game: The Forge
    Author: Don
    Usage: Run script -> Let mob hit you -> Copy timing -> Update Hub Config
]]

local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

--// UI CREATION \\--
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DonHub_ParryLogger"
if RunService:IsStudio() then
    ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
else
    ScreenGui.Parent = CoreGui
end

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Parent = ScreenGui
MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
MainFrame.BorderSizePixel = 0
MainFrame.Position = UDim2.new(0.7, 0, 0.1, 0)
MainFrame.Size = UDim2.new(0, 300, 0, 400)
MainFrame.Active = true
MainFrame.Draggable = true

local Title = Instance.new("TextLabel")
Title.Parent = MainFrame
Title.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
Title.Size = UDim2.new(1, 0, 0, 30)
Title.Font = Enum.Font.GothamBold
Title.Text = "Parry Timing Logger"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 14

local Scroll = Instance.new("ScrollingFrame")
Scroll.Parent = MainFrame
Scroll.BackgroundTransparency = 1
Scroll.Position = UDim2.new(0, 10, 0, 40)
Scroll.Size = UDim2.new(1, -20, 1, -90)
Scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
Scroll.ScrollBarThickness = 4

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.Parent = Scroll
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 5)

UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    Scroll.CanvasSize = UDim2.new(0, 0, 0, UIListLayout.AbsoluteContentSize.Y)
end)

local CopyBtn = Instance.new("TextButton")
CopyBtn.Parent = MainFrame
CopyBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
CopyBtn.Position = UDim2.new(0, 10, 1, -40)
CopyBtn.Size = UDim2.new(0.45, 0, 0, 30)
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Text = "Copy Table"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 14

local ClearBtn = Instance.new("TextButton")
ClearBtn.Parent = MainFrame
ClearBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
ClearBtn.Position = UDim2.new(0.55, 0, 1, -40)
ClearBtn.Size = UDim2.new(0.45, 0, 0, 30)
ClearBtn.Font = Enum.Font.GothamBold
ClearBtn.Text = "Clear"
ClearBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ClearBtn.TextSize = 14

--// LOGIC VARIABLES \\--
local Logs = {} -- Stores formatted strings
local RecentSounds = {} -- { {Name, Time} }
local MaxSoundAge = 2.0 -- Seconds to keep a sound in memory
local OldHealth = 0

--// FUNCTIONS \\--

local function AddLog(SoundName, Delay)
    local FormattedDelay = string.format("%.3f", Delay)
    local LogString = string.format("[\"%s\"] = %s,", SoundName, FormattedDelay)
    
    table.insert(Logs, LogString)
    
    local Label = Instance.new("TextLabel")
    Label.Parent = Scroll
    Label.BackgroundTransparency = 1
    Label.Size = UDim2.new(1, 0, 0, 20)
    Label.Font = Enum.Font.Code
    Label.Text = SoundName .. " : " .. FormattedDelay .. "s"
    Label.TextColor3 = Color3.fromRGB(200, 200, 200)
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.TextSize = 12
    
    Scroll.CanvasPosition = Vector2.new(0, 9999)
end

local function MonitorMob(Mob)
    if not Mob:FindFirstChild("HumanoidRootPart") then return end
    
    Mob.HumanoidRootPart.ChildAdded:Connect(function(Child)
        if Child:IsA("Sound") then
            table.insert(RecentSounds, {
                Name = Child.Name,
                Time = os.clock()
            })
        end
    end)
end

--// LISTENERS \\--

-- 1. Listen for Damage (The "Hit")
task.spawn(function()
    while true do
        task.wait(0.1)
        local Char = LocalPlayer.Character
        if Char and Char:FindFirstChild("Humanoid") then
            local Hum = Char.Humanoid
            
            if OldHealth == 0 then OldHealth = Hum.Health end
            
            if Hum.Health < OldHealth then
                -- DAMAGE TAKEN! Find the sound that caused it.
                local HitTime = os.clock()
                local BestMatch = nil
                local ShortestDiff = MaxSoundAge
                
                -- Look backwards through recent sounds
                for i = #RecentSounds, 1, -1 do
                    local SoundData = RecentSounds[i]
                    local Diff = HitTime - SoundData.Time
                    
                    if Diff > 0 and Diff < ShortestDiff then
                        ShortestDiff = Diff
                        BestMatch = SoundData
                    end
                end
                
                if BestMatch then
                    AddLog(BestMatch.Name, ShortestDiff)
                    -- Clear recent sounds to prevent double logging
                    RecentSounds = {} 
                end
            end
            
            OldHealth = Hum.Health
        end
    end
end)

-- 2. Cleanup Old Sounds
task.spawn(function()
    while true do
        task.wait(0.5)
        local Now = os.clock()
        for i = #RecentSounds, 1, -1 do
            if (Now - RecentSounds[i].Time) > MaxSoundAge then
                table.remove(RecentSounds, i)
            end
        end
    end
end)

-- 3. Monitor Existing Mobs
local Living = Workspace:WaitForChild("Living")
for _, Mob in pairs(Living:GetChildren()) do
    if not Players:GetPlayerFromCharacter(Mob) then
        MonitorMob(Mob)
    end
end

-- 4. Monitor New Mobs
Living.ChildAdded:Connect(function(Mob)
    if not Players:GetPlayerFromCharacter(Mob) then
        MonitorMob(Mob)
    end
end)

--// BUTTONS \\--

CopyBtn.MouseButton1Click:Connect(function()
    local Result = table.concat(Logs, "\n")
    setclipboard(Result)
    CopyBtn.Text = "Copied!"
    task.wait(1)
    CopyBtn.Text = "Copy Table"
end)

ClearBtn.MouseButton1Click:Connect(function()
    Logs = {}
    for _, child in pairs(Scroll:GetChildren()) do
        if child:IsA("TextLabel") then child:Destroy() end
    end
end)