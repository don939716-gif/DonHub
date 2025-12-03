local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer

--// CONFIGURATION \\--
local Config = {
    AutoFarmRocks = false,
    AutoFarmMobs = false,
    SelectedRocks = {},
    SelectedMobs = {},
    AttackDistance = 7,
    SwingDelay = 0.3,
    RunSpeed = 21.69,
    WalkSpeed = 11.79,
    
    -- Parry Configuration
    ParryEnabled = true,
    ParryDelay = 0.25,
    BlockDuration = 0.25,
    ParryDistance = 15
}

--// PARRY SOUND LIST \\--
local ParrySounds = {
    "Zombie Swing 1", "Zombie Swing 2", 
    "Colossal Weapon Swing 1", "Colossal Weapon Swing 2", 
    "Dagger Swing 1", "Dagger Swing 2", 
    "Gauntlet Swing 1", "Gauntlet Swing 2", 
    "Greataxe Swing 1", "Greataxe Swing 2", 
    "Greatsword Swing 1", "Greatsword Swing 2", 
    "Katana Swing 1", "Katana Swing 2", "Katana Swing 3", 
    "Straight Swing 1", "Straight Swing 2"
}

--// ANIMATION ASSETS \\--
local Anim_RunDefault = Instance.new("Animation")
Anim_RunDefault.AnimationId = "rbxassetid://120321298562953"

local Anim_RunPickaxe = Instance.new("Animation")
Anim_RunPickaxe.AnimationId = "rbxassetid://91424712336158"

--// STATE VARIABLES \\--
local CurrentTarget = nil 
local CurrentAnimTrack = nil
local IsParrying = false
local SpeedState = { Connection = nil, Humanoid = nil, IsRunning = false }
local MobileButtonGui = nil

--// ASSET LOADING (SAFE MODE) \\--
local RockOptions = {}
local MobOptions = {}

-- Attempt to load assets with a timeout to prevent freezing
task.spawn(function()
    pcall(function()
        local Assets = ReplicatedStorage:WaitForChild("Assets", 5)
        if Assets then
            if Assets:FindFirstChild("Rocks") then
                for _, rock in pairs(Assets.Rocks:GetChildren()) do table.insert(RockOptions, rock.Name) end
            end
            if Assets:FindFirstChild("Mobs") then
                for _, mob in pairs(Assets.Mobs:GetChildren()) do table.insert(MobOptions, mob.Name) end
            end
        end
    end)
end)

-- Wait briefly for assets to populate, but don't block execution
local StartTime = tick()
while (#RockOptions == 0 or #MobOptions == 0) and (tick() - StartTime) < 2 do
    task.wait(0.1)
end

-- Fallback if empty
if #RockOptions == 0 then table.insert(RockOptions, "None Found") end
if #MobOptions == 0 then table.insert(MobOptions, "None Found") end

table.sort(RockOptions)
table.sort(MobOptions)

--// UI SETUP \\--
local Window = Fluent:CreateWindow({
    Title = "The Forge | Script Hub V13",
    SubTitle = "by DonHub",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Farm = Window:AddTab({ Title = "Auto Farm", Icon = "pickaxe" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

--// UI ELEMENTS \\--

Tabs.Farm:AddParagraph({
    Title = "Instructions",
    Content = "Select items below, then enable the farm. \nUse the Mobile Button to toggle UI."
})

-- ROCKS SECTION
Tabs.Farm:AddSection("Rock Mining")

local RockDropdown = Tabs.Farm:AddDropdown("RockSelection", {
    Title = "Select Rocks",
    Values = RockOptions,
    Multi = true,
    Default = {},
})

RockDropdown:OnChanged(function(Value)
    Config.SelectedRocks = {}
    for Name, Selected in pairs(Value) do
        if Selected and Name ~= "None Found" then table.insert(Config.SelectedRocks, Name) end
    end
end)

Tabs.Farm:AddToggle("AutoFarmRocks", {Title = "Enable Rock Farm", Default = false }):OnChanged(function(Value)
    Config.AutoFarmRocks = Value
    Config.AutoFarmMobs = false
    ResetFarm()
end)

-- MOBS SECTION
Tabs.Farm:AddSection("Mob Farming")

local MobDropdown = Tabs.Farm:AddDropdown("MobSelection", {
    Title = "Select Mobs",
    Values = MobOptions,
    Multi = true,
    Default = {},
})

MobDropdown:OnChanged(function(Value)
    Config.SelectedMobs = {}
    for Name, Selected in pairs(Value) do
        if Selected and Name ~= "None Found" then table.insert(Config.SelectedMobs, Name) end
    end
end)

Tabs.Farm:AddToggle("AutoFarmMobs", {Title = "Enable Mob Farm", Default = false }):OnChanged(function(Value)
    Config.AutoFarmMobs = Value
    Config.AutoFarmRocks = false
    ResetFarm()
end)

--// MOBILE TOGGLE BUTTON (PLAYERGUI) \\--
task.spawn(function()
    pcall(function()
        if LocalPlayer.PlayerGui:FindFirstChild("ForgeHubMobileButton") then
            LocalPlayer.PlayerGui.ForgeHubMobileButton:Destroy()
        end

        local ScreenGui = Instance.new("ScreenGui")
        ScreenGui.Name = "ForgeHubMobileButton"
        ScreenGui.Parent = LocalPlayer.PlayerGui
        ScreenGui.ResetOnSpawn = false

        local ToggleBtn = Instance.new("TextButton")
        ToggleBtn.Parent = ScreenGui
        ToggleBtn.Size = UDim2.new(0, 50, 0, 50)
        ToggleBtn.Position = UDim2.new(0.85, 0, 0.2, 0)
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
        ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        ToggleBtn.Text = "UI"
        ToggleBtn.TextSize = 20
        ToggleBtn.Font = Enum.Font.GothamBold
        ToggleBtn.BorderSizePixel = 0
        
        local Corner = Instance.new("UICorner")
        Corner.CornerRadius = UDim.new(1, 0)
        Corner.Parent = ToggleBtn
        
        -- Add Stroke for visibility
        local Stroke = Instance.new("UIStroke")
        Stroke.Parent = ToggleBtn
        Stroke.Color = Color3.fromRGB(100, 100, 100)
        Stroke.Thickness = 2

        -- Make Draggable
        local dragging, dragInput, dragStart, startPos
        ToggleBtn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = ToggleBtn.Position
            end
        end)
        
        ToggleBtn.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)
        
        game:GetService("UserInputService").InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - dragStart
                ToggleBtn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)

        -- Toggle Logic
        ToggleBtn.MouseButton1Click:Connect(function()
            pcall(function()
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftControl, false, game)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftControl, false, game)
            end)
        end)

        MobileButtonGui = ScreenGui
    end)
end)

--// HELPER FUNCTIONS \\--

function ResetFarm()
    CurrentTarget = nil
    ManageRunState(false)
    local Char = GetCharacter()
    if Char and Char:FindFirstChild("Humanoid") then
        Char.Humanoid:MoveTo(Char.HumanoidRootPart.Position)
    end
end

function GetCharacter()
    if Workspace:FindFirstChild("Living") then
        local LivingChar = Workspace.Living:FindFirstChild(LocalPlayer.Name)
        if LivingChar then return LivingChar end
    end
    return LocalPlayer.Character
end

function EquipTool(ToolName)
    local Char = GetCharacter()
    if not Char then return end
    if Char:FindFirstChild(ToolName) then return end

    local Backpack = LocalPlayer:FindFirstChild("Backpack")
    if Backpack and Backpack:FindFirstChild(ToolName) then
        Backpack[ToolName].Parent = Char
    end
end

function ManageRunState(ShouldRun)
    local Char = GetCharacter()
    if not Char then return end
    local Humanoid = Char:FindFirstChild("Humanoid")
    local Animator = Humanoid and Humanoid:FindFirstChild("Animator")
    
    if not Humanoid then return end

    if IsParrying then
        if SpeedState.Connection then SpeedState.Connection:Disconnect() SpeedState.Connection = nil end
        Humanoid.WalkSpeed = 0 
        return
    end

    if ShouldRun then
        if SpeedState.Humanoid ~= Humanoid or not SpeedState.IsRunning then
            if SpeedState.Connection then SpeedState.Connection:Disconnect() end
            local function EnforceSpeed()
                if not IsParrying and Humanoid.WalkSpeed ~= Config.RunSpeed then
                    Humanoid.WalkSpeed = Config.RunSpeed
                end
            end
            EnforceSpeed()
            SpeedState.Connection = Humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(EnforceSpeed)
            SpeedState.Humanoid = Humanoid
            SpeedState.IsRunning = true
        end

        if CurrentAnimTrack and CurrentAnimTrack.IsPlaying then return end
        if Animator then
            local AnimationToLoad = Anim_RunDefault
            if Char:FindFirstChild("Pickaxe") or Char:FindFirstChild("Weapon") then
                AnimationToLoad = Anim_RunPickaxe
            end
            pcall(function()
                CurrentAnimTrack = Animator:LoadAnimation(AnimationToLoad)
                CurrentAnimTrack.Priority = Enum.AnimationPriority.Action 
                CurrentAnimTrack.Looped = true
                CurrentAnimTrack:Play()
            end)
        end
    else
        if SpeedState.Connection then
            SpeedState.Connection:Disconnect()
            SpeedState.Connection = nil
        end
        SpeedState.IsRunning = false
        SpeedState.Humanoid = nil
        Humanoid.WalkSpeed = Config.WalkSpeed

        if CurrentAnimTrack then
            CurrentAnimTrack:Stop()
            CurrentAnimTrack = nil
        end
    end
end

--// AUTO PARRY LOGIC \\--

function PerformParry()
    if IsParrying then return end
    IsParrying = true
    
    local Char = GetCharacter()
    if Char and Char:FindFirstChild("Humanoid") then
        Char.Humanoid:MoveTo(Char.HumanoidRootPart.Position)
        Char.Humanoid.WalkSpeed = 0
    end

    task.spawn(function()
        task.wait(Config.ParryDelay)
        pcall(function()
            game:GetService("ReplicatedStorage").Shared.Packages.Knit.Services.ToolService.RF.StartBlock:InvokeServer()
        end)
        task.wait(Config.BlockDuration)
        pcall(function()
            game:GetService("ReplicatedStorage").Shared.Packages.Knit.Services.ToolService.RF.StopBlock:InvokeServer()
        end)
        IsParrying = false
    end)
end

function SetupMobListener(Mob)
    if not Mob:IsA("Model") then return end
    if Players:GetPlayerFromCharacter(Mob) then return end
    
    local Root = Mob:WaitForChild("HumanoidRootPart", 5)
    if not Root then return end

    Root.ChildAdded:Connect(function(Child)
        if not Config.ParryEnabled then return end
        if table.find(ParrySounds, Child.Name) then
            local Char = GetCharacter()
            if Char and Char:FindFirstChild("HumanoidRootPart") then
                local Dist = (Char.HumanoidRootPart.Position - Root.Position).Magnitude
                if Dist <= Config.ParryDistance then
                    PerformParry()
                end
            end
        end
    end)
end

if Workspace:FindFirstChild("Living") then
    for _, Mob in pairs(Workspace.Living:GetChildren()) do SetupMobListener(Mob) end
    Workspace.Living.ChildAdded:Connect(SetupMobListener)
end

--// COMBAT & MINING LOGIC \\--

function IsRockBroken(Hitbox)
    if not Hitbox or not Hitbox.Parent then return true end
    local InfoFrame = Hitbox.Parent:FindFirstChild("infoFrame")
    if InfoFrame and InfoFrame:FindFirstChild("Frame") and InfoFrame.Frame:FindFirstChild("rockHP") then
        local Text = InfoFrame.Frame.rockHP.Text
        return Text == "0 HP" or string.sub(Text, 1, 2) == "0/"
    end
    return false
end

function Attack(ToolName)
    local args = { ToolName }
    pcall(function()
        game:GetService("ReplicatedStorage").Shared.Packages.Knit.Services.ToolService.RF.ToolActivated:InvokeServer(unpack(args))
    end)
end

function GetClosestTarget(IsMob)
    local Char = GetCharacter()
    local Root = Char and Char:FindFirstChild("HumanoidRootPart")
    if not Root then return nil end

    local ClosestTarget = nil
    local ClosestDist = math.huge

    if IsMob then
        if Workspace:FindFirstChild("Living") then
            for _, Mob in pairs(Workspace.Living:GetChildren()) do
                if table.find(Config.SelectedMobs, Mob.Name) and not Players:GetPlayerFromCharacter(Mob) then
                    local MobRoot = Mob:FindFirstChild("HumanoidRootPart")
                    local Humanoid = Mob:FindFirstChild("Humanoid")
                    if MobRoot and Humanoid and Humanoid.Health > 0 then
                        local Dist = (Root.Position - MobRoot.Position).Magnitude
                        if Dist < ClosestDist then
                            ClosestDist = Dist
                            ClosestTarget = MobRoot
                        end
                    end
                end
            end
        end
    else
        if Workspace:FindFirstChild("Rocks") then
            for _, Area in pairs(Workspace.Rocks:GetChildren()) do
                for _, Container in pairs(Area:GetChildren()) do
                    for _, Item in pairs(Container:GetChildren()) do
                        if table.find(Config.SelectedRocks, Item.Name) and Item:FindFirstChild("Hitbox") then
                            if not IsRockBroken(Item.Hitbox) then
                                local Dist = (Root.Position - Item.Hitbox.Position).Magnitude
                                if Dist < ClosestDist then
                                    ClosestDist = Dist
                                    ClosestTarget = Item.Hitbox
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return ClosestTarget
end

function PathfindTo(TargetPart)
    local Char = GetCharacter()
    if not Char then return end
    local Root = Char:FindFirstChild("HumanoidRootPart")
    local Humanoid = Char:FindFirstChild("Humanoid")
    if not Root or not Humanoid then return end

    if Root.Anchored == false then
        pcall(function() Root:SetNetworkOwner(LocalPlayer) end)
    end

    local Path = PathfindingService:CreatePath({
        AgentRadius = 3, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 8, Costs = { Water = 20 }
    })

    local Success = pcall(function() Path:ComputeAsync(Root.Position, TargetPart.Position) end)

    if Success and Path.Status == Enum.PathStatus.Success then
        local Waypoints = Path:GetWaypoints()
        ManageRunState(true)

        for i, Waypoint in pairs(Waypoints) do
            if not Config.AutoFarmRocks and not Config.AutoFarmMobs then break end
            while IsParrying do task.wait() end

            if Config.AutoFarmRocks and IsRockBroken(TargetPart) then return end
            if Config.AutoFarmMobs and (not TargetPart.Parent or TargetPart.Parent.Humanoid.Health <= 0) then return end

            if Config.AutoFarmRocks then
                local DistToTarget = (Root.Position - TargetPart.Position).Magnitude
                if DistToTarget > 20 then
                     local Nearby = GetClosestTarget(false)
                     if Nearby and Nearby ~= TargetPart and (Root.Position - Nearby.Position).Magnitude < Config.AttackDistance then
                         CurrentTarget = Nearby
                         return 
                     end
                end
            end

            Humanoid:MoveTo(Waypoint.Position)
            if Waypoint.Action == Enum.PathWaypointAction.Jump then Humanoid.Jump = true end
            
            local Timeout = 0
            while (Config.AutoFarmRocks or Config.AutoFarmMobs) do
                if IsParrying then break end
                local DistToWaypoint = (Root.Position - Waypoint.Position).Magnitude
                if DistToWaypoint < 4 then break end
                Timeout = Timeout + 0.1
                if Timeout > 2 then break end
                if (Root.Position - TargetPart.Position).Magnitude < Config.AttackDistance then return end
                task.wait(0.1)
            end
        end
    else
        ManageRunState(true)
        Humanoid:MoveTo(TargetPart.Position)
    end
end

--// MAIN LOOP \\--
task.spawn(function()
    while true do
        task.wait()
        if IsParrying then task.wait(0.1) continue end

        if Config.AutoFarmRocks or Config.AutoFarmMobs then
            local Char = GetCharacter()
            if Char and Char:FindFirstChild("HumanoidRootPart") and Char:FindFirstChild("Humanoid") and Char.Humanoid.Health > 0 then
                
                local IsMobMode = Config.AutoFarmMobs
                local ToolName = IsMobMode and "Weapon" or "Pickaxe"
                EquipTool(ToolName)
                
                if CurrentTarget then
                    if IsMobMode then
                        if not CurrentTarget.Parent or CurrentTarget.Parent.Humanoid.Health <= 0 then CurrentTarget = nil end
                    else
                        if IsRockBroken(CurrentTarget) or not CurrentTarget.Parent then CurrentTarget = nil end
                    end
                    if CurrentTarget then
                        local Dist = (Char.HumanoidRootPart.Position - CurrentTarget.Position).Magnitude
                        if Dist > 300 then CurrentTarget = nil end
                    end
                end

                if not CurrentTarget then CurrentTarget = GetClosestTarget(IsMobMode) end
                
                if CurrentTarget then
                    local Root = Char.HumanoidRootPart
                    local Distance = (Root.Position - CurrentTarget.Position).Magnitude
                    
                    if Distance > Config.AttackDistance then
                        Fluent:Notify({ Title = "Farming", Content = "Moving to " .. CurrentTarget.Parent.Name, Duration = 1 })
                        PathfindTo(CurrentTarget)
                    else
                        ManageRunState(false)
                        Char.Humanoid:MoveTo(Root.Position)
                        
                        local LookPos = CurrentTarget.Position
                        Root.CFrame = CFrame.new(Root.Position, Vector3.new(LookPos.X, Root.Position.Y, LookPos.Z))
                        
                        while (Config.AutoFarmRocks or Config.AutoFarmMobs) and CurrentTarget and CurrentTarget.Parent do
                            if IsParrying then task.wait() continue end
                            if IsMobMode then
                                if CurrentTarget.Parent.Humanoid.Health <= 0 then CurrentTarget = nil break end
                            else
                                if IsRockBroken(CurrentTarget) then CurrentTarget = nil break end
                            end

                            local CurrentLook = Root.CFrame.LookVector
                            local TargetDir = (CurrentTarget.Position - Root.Position).Unit
                            if (CurrentLook.X * TargetDir.X + CurrentLook.Z * TargetDir.Z) < 0.5 then
                                Root.CFrame = CFrame.new(Root.Position, Vector3.new(CurrentTarget.Position.X, Root.Position.Y, CurrentTarget.Position.Z))
                            end

                            if CurrentTarget.Position.Y > (Root.Position.Y + 3.5) then Char.Humanoid.Jump = true end

                            Attack(ToolName)
                            task.wait(Config.SwingDelay)
                            
                            if not Char or not Char.Parent or Char.Humanoid.Health <= 0 then break end
                            if (Root.Position - CurrentTarget.Position).Magnitude > Config.AttackDistance + 5 then break end
                        end
                    end
                else
                    ManageRunState(false)
                    task.wait(0.5)
                end
            else
                task.wait(1)
            end
        else
            ManageRunState(false)
        end
    end
end)

Window:OnDestroy(function()
    if MobileButtonGui then MobileButtonGui:Destroy() end
end)

SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)
Fluent:Notify({ Title = "The Forge Hub", Content = "Script Loaded!", Duration = 3 })