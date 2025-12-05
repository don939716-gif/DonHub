--[[
    DonHub - Parry Timing Logger V5 (Distance Fixed)
    Game: The Forge
    Author: Don
    
    CHANGELOG:
    - Added 15 Stud Distance Check.
    - Reduced Sound Memory to 1.0s to prevent matching old swings.
    - Ignores sounds if the player is too far away.
]]

local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

--// CLEANUP OLD INSTANCES \\--
if getgenv().DonHubLoggerConnections then
    for _, connection in pairs(getgenv().DonHubLoggerConnections) do
        if connection then connection:Disconnect() end
    end
end
getgenv().DonHubLoggerConnections = {}

local OldUI = CoreGui:FindFirstChild("DonHub_ParryLogger_V5")
if OldUI then OldUI:Destroy() end

--// UI CREATION \\--
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DonHub_ParryLogger_V5"
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
MainFrame.Size = UDim2.new(0, 350, 0, 400)
MainFrame.Active = true
MainFrame.Draggable = true

local Title = Instance.new("TextLabel")
Title.Parent = MainFrame
Title.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
Title.Size = UDim2.new(1, 0, 0, 30)
Title.Font = Enum.Font.GothamBold
Title.Text = "Parry Logger v5 (Max 15 Studs)"
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
UIListLayout.SortOrder = Enum.SortOrder.Name
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
local LoggedData = {} 
local RecentSounds = {} 
local MaxSoundAge = 1.0 -- Reduced from 2.0 to 1.0 for tighter accuracy
local OldHealth = 0

--// FUNCTIONS \\--

function CleanMobName(Name)
    return string.gsub(Name, "%d+$", "")
end

local function UpdateUI(MobName, SoundName, Delay)
    local FormattedDelay = string.format("%.3f", Delay)
    local Key = MobName .. " - " .. SoundName
    
    if LoggedData[Key] then
        -- Update Existing
        LoggedData[Key].Time = Delay
        LoggedData[Key].Label.Text = string.format("%s : %ss", Key, FormattedDelay)
        
        task.spawn(function()
            LoggedData[Key].Label.TextColor3 = Color3.fromRGB(0, 255, 0)
            task.wait(0.2)
            LoggedData[Key].Label.TextColor3 = Color3.fromRGB(200, 200, 200)
        end)
    else
        -- Create New
        local Label = Instance.new("TextLabel")
        Label.Name = Key 
        Label.Parent = Scroll
        Label.BackgroundTransparency = 1
        Label.Size = UDim2.new(1, 0, 0, 20)
        Label.Font = Enum.Font.Code
        Label.Text = string.format("%s : %ss", Key, FormattedDelay)
        Label.TextColor3 = Color3.fromRGB(200, 200, 200)
        Label.TextXAlignment = Enum.TextXAlignment.Left
        Label.TextSize = 11 
        
        LoggedData[Key] = {
            Time = Delay,
            Label = Label
        }
    end
end

local function MonitorMob(Mob)
    if not Mob:FindFirstChild("HumanoidRootPart") then return end
    
    local CleanName = CleanMobName(Mob.Name)
    
    local Conn = Mob.HumanoidRootPart.ChildAdded:Connect(function(Child)
        if Child:IsA("Sound") and string.find(Child.Name, "Swing") then
            
            -- DISTANCE CHECK: Only record if player is close (15 studs)
            local MyChar = LocalPlayer.Character
            if MyChar and MyChar:FindFirstChild("HumanoidRootPart") and Mob:FindFirstChild("HumanoidRootPart") then
                local Dist = (MyChar.HumanoidRootPart.Position - Mob.HumanoidRootPart.Position).Magnitude
                
                if Dist <= 15 then
                    table.insert(RecentSounds, {
                        Mob = CleanName,
                        Sound = Child.Name,
                        Time = os.clock()
                    })
                end
            end
        end
    end)
    
    table.insert(getgenv().DonHubLoggerConnections, Conn)
end

--// LISTENERS \\--

-- 1. Damage Listener
local DamageConn = RunService.Heartbeat:Connect(function()
    local Char = LocalPlayer.Character
    if Char and Char:FindFirstChild("Humanoid") then
        local Hum = Char.Humanoid
        
        if OldHealth == 0 then OldHealth = Hum.Health end
        
        if Hum.Health < OldHealth then
            local HitTime = os.clock()
            local BestMatch = nil
            local ShortestDiff = MaxSoundAge
            
            for i = #RecentSounds, 1, -1 do
                local SoundData = RecentSounds[i]
                local Diff = HitTime - SoundData.Time
                
                -- Only match if sound happened BEFORE hit and within 1 second
                if Diff > 0 and Diff < ShortestDiff then
                    ShortestDiff = Diff
                    BestMatch = SoundData
                end
            end
            
            if BestMatch then
                UpdateUI(BestMatch.Mob, BestMatch.Sound, ShortestDiff)
                RecentSounds = {} -- Clear immediately to prevent stale data
            end
        end
        
        OldHealth = Hum.Health
    end
end)
table.insert(getgenv().DonHubLoggerConnections, DamageConn)

-- 2. Cleanup Old Sounds
local CleanupConn = task.spawn(function()
    while true do
        task.wait(0.2) -- Check more frequently
        local Now = os.clock()
        for i = #RecentSounds, 1, -1 do
            if (Now - RecentSounds[i].Time) > MaxSoundAge then
                table.remove(RecentSounds, i)
            end
        end
    end
end)

-- 3. Monitor Mobs
local Living = Workspace:WaitForChild("Living")
for _, Mob in pairs(Living:GetChildren()) do
    if not Players:GetPlayerFromCharacter(Mob) then
        MonitorMob(Mob)
    end
end

local LivingConn = Living.ChildAdded:Connect(function(Mob)
    if not Players:GetPlayerFromCharacter(Mob) then
        MonitorMob(Mob)
    end
end)
table.insert(getgenv().DonHubLoggerConnections, LivingConn)

--// BUTTONS \\--

CopyBtn.MouseButton1Click:Connect(function()
    local Lines = {}
    for Key, Data in pairs(LoggedData) do
        -- Format: ["MobName - SoundName"] = 0.123,
        table.insert(Lines, string.format("    [\"%s\"] = %.3f,", Key, Data.Time))
    end
    
    local Result = table.concat(Lines, "\n")
    setclipboard(Result)
    
    CopyBtn.Text = "Copied!"
    task.wait(1)
    CopyBtn.Text = "Copy Table"
end)

ClearBtn.MouseButton1Click:Connect(function()
    LoggedData = {}
    for _, child in pairs(Scroll:GetChildren()) do
        if child:IsA("TextLabel") then child:Destroy() end
    end
end)
