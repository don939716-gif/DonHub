--[[
    DonHub - Parry Timing Logger V2
    Game: The Forge
    Author: Don
    
    Instructions:
    1. Run Script.
    2. Let a mob hit you.
    3. The script calculates the exact delay between the Sound and the Damage.
    4. Click "Copy Table" and paste it into your Hub's ParryConfig.
]]

local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

--// CONFIGURATION \\--
local TargetSounds = {
    "Zombie Swing 1", "Zombie Swing 2", 
    "Colossal Weapon Swing 1", "Colossal Weapon Swing 2", 
    "Dagger Swing 1", "Dagger Swing 2", 
    "Gauntlet Swing 1", "Gauntlet Swing 2", 
    "Greataxe Swing 1", "Greataxe Swing 2", 
    "Greatsword Swing 1", "Greatsword Swing 2", 
    "Katana Swing 1", "Katana Swing 2", "Katana Swing 3", 
    "Straight Swing 1", "Straight Swing 2"
}

--// UI CREATION \\--
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DonHub_ParryLogger_V2"
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
MainFrame.Size = UDim2.new(0, 320, 0, 400)
MainFrame.Active = true
MainFrame.Draggable = true

local Title = Instance.new("TextLabel")
Title.Parent = MainFrame
Title.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
Title.Size = UDim2.new(1, 0, 0, 30)
Title.Font = Enum.Font.GothamBold
Title.Text = "Parry Timing Logger V2"
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
UIListLayout.SortOrder = Enum.SortOrder.Name -- Sorts alphabetically by sound name
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
ClearBtn.Text = "Reset"
ClearBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ClearBtn.TextSize = 14

--// LOGIC VARIABLES \\--
local LoggedData = {} -- [SoundName] = {Time = 0.25, Label = Instance}
local RecentSounds = {} -- { {Name, Time} }
local MaxSoundAge = 2.0 -- Seconds to keep a sound in memory
local OldHealth = 0

--// FUNCTIONS \\--

local function UpdateUI(SoundName, Delay)
    local FormattedDelay = string.format("%.3f", Delay)
    
    if LoggedData[SoundName] then
        -- Update Existing
        LoggedData[SoundName].Time = Delay
        LoggedData[SoundName].Label.Text = string.format("%s : %ss", SoundName, FormattedDelay)
        
        -- Flash effect to show update
        task.spawn(function()
            LoggedData[SoundName].Label.TextColor3 = Color3.fromRGB(0, 255, 0)
            task.wait(0.2)
            LoggedData[SoundName].Label.TextColor3 = Color3.fromRGB(200, 200, 200)
        end)
    else
        -- Create New
        local Label = Instance.new("TextLabel")
        Label.Name = SoundName -- For sorting
        Label.Parent = Scroll
        Label.BackgroundTransparency = 1
        Label.Size = UDim2.new(1, 0, 0, 20)
        Label.Font = Enum.Font.Code
        Label.Text = string.format("%s : %ss", SoundName, FormattedDelay)
        Label.TextColor3 = Color3.fromRGB(200, 200, 200)
        Label.TextXAlignment = Enum.TextXAlignment.Left
        Label.TextSize = 12
        
        LoggedData[SoundName] = {
            Time = Delay,
            Label = Label
        }
    end
end

local function MonitorMob(Mob)
    if not Mob:FindFirstChild("HumanoidRootPart") then return end
    
    Mob.HumanoidRootPart.ChildAdded:Connect(function(Child)
        if Child:IsA("Sound") and table.find(TargetSounds, Child.Name) then
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
        task.wait() -- Fast check
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
                    
                    -- We look for sounds that happened BEFORE the hit (Diff > 0)
                    -- But not too long ago
                    if Diff > 0 and Diff < ShortestDiff then
                        ShortestDiff = Diff
                        BestMatch = SoundData
                    end
                end
                
                if BestMatch then
                    -- Subtract a tiny buffer (0.05) to ensure block starts slightly before hit
                    -- But keep it raw for the logger so you see the exact delay
                    UpdateUI(BestMatch.Name, ShortestDiff)
                    
                    -- Clear recent sounds to prevent double logging the same swing
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
    local Lines = {}
    for Name, Data in pairs(LoggedData) do
        -- Format: ["Sound Name"] = 0.123,
        table.insert(Lines, string.format("    [\"%s\"] = %.3f,", Name, Data.Time))
    end
    
    local Result = table.concat(Lines, "\n")
    setclipboard(Result)
    
    CopyBtn.Text = "Copied to Clipboard!"
    task.wait(1)
    CopyBtn.Text = "Copy Table"
end)

ClearBtn.MouseButton1Click:Connect(function()
    LoggedData = {}
    for _, child in pairs(Scroll:GetChildren()) do
        if child:IsA("TextLabel") then child:Destroy() end
    end
end)