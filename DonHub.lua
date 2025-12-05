--[[
    DonHub - The Forge Script Hub
    Version: v1.2.0
    Author: Don
    License: Private
]]

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

--// CONFIGURATION \\--
local Config = {
    -- General
    AutoFarmRocks = false,
    AutoFarmMobs = false,
    
    -- Rock Settings
    SelectedRocks = {},
    
    -- Mob Settings
    SelectedMobs = {},
    
    -- Shared Combat/Movement
    AttackDistance = 7,
    SwingDelay = 0.3,
    RunSpeed = 21.69,
    WalkSpeed = 11.79
}

--// PARRY CONFIGURATION \\--
local ParryConfig = {
    Enabled = true,
    DetectionRange = 10,
    BlockDuration = 0.25, 
    
    -- Format: ["MobName - SoundName"] = DelaySeconds
    Delays = {
        ["EliteZombie - Colossal Weapon Swing 2"] = 0.409,
        ["Zombie - Zombie Swing 1"] = 0.822,
        ["Zombie - Zombie Swing 2"] = 0.822,
        ["EliteZombie - Colossal Weapon Swing 1"] = 0.373,
        ["Brute Zombie - Zombie Swing 2"] = 0.480,
        ["Delver Zombie - Zombie Swing 1"] = 0.722,
        ["Delver Zombie - Zombie Swing 2"] = 0.539,
        ["Brute Zombie - Zombie Swing 1"] = 0.506,
        ["Axe Skeleton - Straight Swing 1"] = 0.531,
        ["Reaper - Greataxe Swing 1"] = 0.150,
        ["Deathaxe Skeleton - Zombie Swing 2"] = 0.698,
        ["Elite Rogue Skeleton - Dagger Swing 2"] = 0.013,
        ["Deathaxe Skeleton - Zombie Swing 1"] = 1.079,
        ["Blazing Slime - Zombie Swing 1"] = 0.175,
        ["Elite Rogue Skeleton - Dagger Swing 1"] = 0.300,
        ["Elite Deathaxe Skeleton - Greataxe Swing 1"] = 1.184,
        ["Skeleton Rogue - Dagger Swing 1"] = 0.264,
        ["Reaper - Greataxe Swing 2"] = 0.131,
        ["Skeleton Rogue - Dagger Swing 2"] = 0.499,
        ["Axe Skeleton - Straight Swing 2"] = 0.259,
    }
}

--// ASSET CACHING \\--
local WeaponMap = {} -- [WeaponName] = CategoryName
local RunAnimationIds = {} -- [Category] = AnimationId String

-- Pre-scan Weapon Categories
local EquipAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Equipments"):WaitForChild("Weapons")
for _, CategoryFolder in pairs(EquipAssets:GetChildren()) do
    for _, WeaponModel in pairs(CategoryFolder:GetChildren()) do
        WeaponMap[WeaponModel.Name] = CategoryFolder.Name
    end
end

-- Pre-scan Run Animations
local AnimAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Animations"):WaitForChild("Movement")
for _, CategoryFolder in pairs(AnimAssets:GetChildren()) do
    local RunAnim = CategoryFolder:FindFirstChild("Run")
    if RunAnim and RunAnim:IsA("Animation") then
        RunAnimationIds[CategoryFolder.Name] = RunAnim.AnimationId
    end
end

-- Default IDs
local ID_RunDefault = "rbxassetid://120321298562953"
local ID_RunPickaxe = "rbxassetid://91424712336158"

--// STATE VARIABLES \\--
local CurrentTarget = nil 
local CurrentAnimTrack = nil
local CurrentAnimId = nil
local SpeedState = { Connection = nil, Humanoid = nil, IsRunning = false }
local IsParrying = false
local ActiveMobConnections = {} -- [Model] = Connection

--// HELPER FUNCTIONS \\--

function GetCharacter()
    if Workspace:FindFirstChild("Living") then
        local LivingChar = Workspace.Living:FindFirstChild(LocalPlayer.Name)
        if LivingChar then return LivingChar end
    end
    return LocalPlayer.Character
end

function CleanMobName(Name)
    return string.gsub(Name, "%d+$", "")
end

function GetEquippedWeaponCategory(Char)
    if not Char then return nil end
    for _, Child in pairs(Char:GetChildren()) do
        if WeaponMap[Child.Name] then
            return WeaponMap[Child.Name]
        end
    end
    return nil
end

-- Speed & Animation Manager
function ManageRunState(ShouldRun)
    local Char = GetCharacter()
    if not Char then return end
    local Humanoid = Char:FindFirstChild("Humanoid")
    local Root = Char:FindFirstChild("HumanoidRootPart")
    local Animator = Humanoid and Humanoid:FindFirstChild("Animator")
    
    if not Humanoid or not Root then return end

    -- 1. Handle Speed
    if ShouldRun and not IsParrying then
        if SpeedState.Humanoid ~= Humanoid or not SpeedState.IsRunning then
            if SpeedState.Connection then SpeedState.Connection:Disconnect() end
            local function EnforceSpeed()
                if Humanoid.WalkSpeed ~= Config.RunSpeed then
                    Humanoid.WalkSpeed = Config.RunSpeed
                end
            end
            EnforceSpeed()
            SpeedState.Connection = Humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(EnforceSpeed)
            SpeedState.Humanoid = Humanoid
            SpeedState.IsRunning = true
        end
    else
        if SpeedState.Connection then
            SpeedState.Connection:Disconnect()
            SpeedState.Connection = nil
        end
        SpeedState.IsRunning = false
        SpeedState.Humanoid = nil
        Humanoid.WalkSpeed = Config.WalkSpeed
    end

    -- 2. Handle Animations (Run Only)
    if not Animator then return end

    -- Determine if we are actually moving
    local IsMoving = Root.Velocity.Magnitude > 0.5
    
    if IsMoving and ShouldRun and not IsParrying then
        local TargetId = ID_RunDefault
        
        -- Check for Pickaxe
        if Char:FindFirstChild("Pickaxe") then
            TargetId = ID_RunPickaxe
        else
            -- Check for Weapon
            local Category = GetEquippedWeaponCategory(Char)
            if Category and RunAnimationIds[Category] then
                TargetId = RunAnimationIds[Category]
            end
        end

        -- Play if not already playing
        if CurrentAnimId ~= TargetId or (CurrentAnimTrack and not CurrentAnimTrack.IsPlaying) then
            if CurrentAnimTrack then CurrentAnimTrack:Stop(0.2) end
            
            local NewAnim = Instance.new("Animation")
            NewAnim.AnimationId = TargetId
            
            pcall(function()
                CurrentAnimTrack = Animator:LoadAnimation(NewAnim)
                CurrentAnimTrack.Priority = Enum.AnimationPriority.Action
                CurrentAnimTrack.Looped = true
                CurrentAnimTrack:Play(0.2)
                CurrentAnimId = TargetId
            end)
        end
    else
        -- Stop Animation if not moving or not running
        if CurrentAnimTrack then
            CurrentAnimTrack:Stop(0.2)
            CurrentAnimTrack = nil
            CurrentAnimId = nil
        end
    end
end

function ResetFarmState()
    CurrentTarget = nil
    ManageRunState(false)
    local Char = GetCharacter()
    if Char and Char:FindFirstChild("Humanoid") then
        Char.Humanoid:MoveTo(Char.HumanoidRootPart.Position)
    end
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

function IsRockBroken(Hitbox)
    if not Hitbox or not Hitbox.Parent then return true end
    local RockModel = Hitbox.Parent
    
    local InfoFrame = RockModel:FindFirstChild("infoFrame")
    if InfoFrame then
        local Frame = InfoFrame:FindFirstChild("Frame")
        if Frame then
            local HPLabel = Frame:FindFirstChild("rockHP")
            if HPLabel then
                if HPLabel.Text == "0 HP" or string.sub(HPLabel.Text, 1, 2) == "0/" then
                    return true
                end
            end
        end
    end
    return false
end

function GetClosestRock()
    local Char = GetCharacter()
    local Root = Char and Char:FindFirstChild("HumanoidRootPart")
    if not Root then return nil end

    local ClosestRock = nil
    local ClosestDist = math.huge

    local RocksFolder = Workspace:FindFirstChild("Rocks")
    if not RocksFolder then return nil end
    
    for _, Area in pairs(RocksFolder:GetChildren()) do
        for _, Container in pairs(Area:GetChildren()) do
            for _, Item in pairs(Container:GetChildren()) do
                if table.find(Config.SelectedRocks, Item.Name) and Item:FindFirstChild("Hitbox") then
                    local Hitbox = Item.Hitbox
                    if not IsRockBroken(Hitbox) then
                        local Dist = (Root.Position - Hitbox.Position).Magnitude
                        if Dist < ClosestDist then
                            ClosestDist = Dist
                            ClosestRock = Hitbox
                        end
                    end
                end
            end
        end
    end
    return ClosestRock
end

function GetClosestMob()
    local Char = GetCharacter()
    local Root = Char and Char:FindFirstChild("HumanoidRootPart")
    if not Root then return nil end

    local ClosestMob = nil
    local ClosestDist = math.huge
    
    local Living = Workspace:FindFirstChild("Living")
    if not Living then return nil end

    for _, Model in pairs(Living:GetChildren()) do
        if not Players:GetPlayerFromCharacter(Model) and Model:FindFirstChild("HumanoidRootPart") and Model:FindFirstChild("Humanoid") then
            local CleanName = CleanMobName(Model.Name)
            if table.find(Config.SelectedMobs, CleanName) then
                if Model.Humanoid.Health > 0 then
                    local Dist = (Root.Position - Model.HumanoidRootPart.Position).Magnitude
                    if Dist < ClosestDist then
                        ClosestDist = Dist
                        ClosestMob = Model.HumanoidRootPart
                    end
                end
            end
        end
    end
    return ClosestMob
end

function SwingTool(ToolName)
    local args = { ToolName }
    pcall(function()
        game:GetService("ReplicatedStorage").Shared.Packages.Knit.Services.ToolService.RF.ToolActivated:InvokeServer(unpack(args))
    end)
end

function PerformParry(Delay)
    if IsParrying then return end
    IsParrying = true
    
    -- Stop Movement
    local Char = GetCharacter()
    if Char and Char:FindFirstChild("Humanoid") then
        Char.Humanoid:MoveTo(Char.HumanoidRootPart.Position)
    end
    ManageRunState(false)

    -- Wait Windup
    task.wait(Delay)

    -- Block
    pcall(function()
        game:GetService("ReplicatedStorage").Shared.Packages.Knit.Services.ToolService.RF.StartBlock:InvokeServer()
    end)

    -- Hold Block
    task.wait(ParryConfig.BlockDuration)

    -- Unblock
    pcall(function()
        game:GetService("ReplicatedStorage").Shared.Packages.Knit.Services.ToolService.RF.StopBlock:InvokeServer()
    end)

    IsParrying = false
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
        AgentRadius = 3,
        AgentHeight = 5,
        AgentCanJump = true,
        WaypointSpacing = 8,
        Costs = { Water = 20 }
    })

    local Success, _ = pcall(function()
        Path:ComputeAsync(Root.Position, TargetPart.Position)
    end)

    if Success and Path.Status == Enum.PathStatus.Success then
        local Waypoints = Path:GetWaypoints()
        ManageRunState(true)

        for i, Waypoint in pairs(Waypoints) do
            if not (Config.AutoFarmRocks or Config.AutoFarmMobs) then break end
            if not Char or not Char.Parent then break end
            
            while IsParrying do task.wait() end

            if not TargetPart or not TargetPart.Parent then return end
            if Config.AutoFarmRocks and IsRockBroken(TargetPart) then return end
            if Config.AutoFarmMobs and TargetPart.Parent.Humanoid.Health <= 0 then return end

            Humanoid:MoveTo(Waypoint.Position)
            
            if Waypoint.Action == Enum.PathWaypointAction.Jump then
                Humanoid.Jump = true
            end
            
            local Timeout = 0
            while (Config.AutoFarmRocks or Config.AutoFarmMobs) do
                if IsParrying then 
                    Humanoid:MoveTo(Root.Position)
                    break 
                end

                local DistToWaypoint = (Root.Position - Waypoint.Position).Magnitude
                if DistToWaypoint < 4 then break end
                
                Timeout = Timeout + 0.1
                if Timeout > 2 then break end

                if (Root.Position - TargetPart.Position).Magnitude < Config.AttackDistance then
                    return
                end
                
                task.wait(0.1)
            end
        end
    else
        ManageRunState(true)
        Humanoid:MoveTo(TargetPart.Position)
    end
end

--// UI SETUP \\--
local Window = Fluent:CreateWindow({
    Title = "DonHub | The Forge",
    SubTitle = "v1.2.0",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Main", Icon = "home" }),
    Farm = Window:AddTab({ Title = "Rock Farm", Icon = "pickaxe" }),
    MobFarm = Window:AddTab({ Title = "Mob Farm", Icon = "sword" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

--// MOBILE TOGGLE BUTTON \\--
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DonHub_MobileToggle"
if RunService:IsStudio() then
    ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
else
    ScreenGui.Parent = CoreGui
end

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Name = "Toggle"
ToggleBtn.Parent = ScreenGui
ToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
ToggleBtn.BorderSizePixel = 0
ToggleBtn.Position = UDim2.new(0.85, 0, 0.8, 0)
ToggleBtn.Size = UDim2.new(0, 50, 0, 50)
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.Text = "UI"
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.TextSize = 18
ToggleBtn.AutoButtonColor = true

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 10)
UICorner.Parent = ToggleBtn

ToggleBtn.MouseButton1Click:Connect(function()
    Window:Minimize()
end)

--// DATA LOADING \\--

local RockOptions = {}
local RocksAssetFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Rocks")
for _, rock in pairs(RocksAssetFolder:GetChildren()) do
    table.insert(RockOptions, rock.Name)
end
table.sort(RockOptions)

local MobOptions = {}
local MobsAssetFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Mobs")
for _, mob in pairs(MobsAssetFolder:GetChildren()) do
    if mob.Name ~= "Zombie3" then
        table.insert(MobOptions, mob.Name)
    end
end
table.sort(MobOptions)

--// UI ELEMENTS \\--

Tabs.Main:AddParagraph({
    Title = "Welcome to DonHub",
    Content = "Select a farming mode from the tabs on the left.\n\nFeatures:\n- Auto Mine Rocks\n- Auto Farm Mobs\n- Auto Parry (Precision Timings)\n- Dynamic Weapon Animations\n- Mobile Support"
})

local RockDropdown = Tabs.Farm:AddDropdown("RockSelection", {
    Title = "Select Rocks",
    Description = "Select rocks to mine.",
    Values = RockOptions,
    Multi = true,
    Default = {},
})

RockDropdown:OnChanged(function(Value)
    Config.SelectedRocks = {}
    for Name, Selected in pairs(Value) do
        if Selected then table.insert(Config.SelectedRocks, Name) end
    end
end)

local RockFarmToggle = Tabs.Farm:AddToggle("AutoFarmRocks", {Title = "Enable Rock Farm", Default = false })
RockFarmToggle:OnChanged(function(Value)
    Config.AutoFarmRocks = Value
    if Value then Config.AutoFarmMobs = false end
    ResetFarmState()
end)

local MobDropdown = Tabs.MobFarm:AddDropdown("MobSelection", {
    Title = "Select Mobs",
    Description = "Select mobs to hunt.",
    Values = MobOptions,
    Multi = true,
    Default = {},
})

MobDropdown:OnChanged(function(Value)
    Config.SelectedMobs = {}
    for Name, Selected in pairs(Value) do
        if Selected then table.insert(Config.SelectedMobs, Name) end
    end
end)

local MobFarmToggle = Tabs.MobFarm:AddToggle("AutoFarmMobs", {Title = "Enable Mob Farm", Default = false })
MobFarmToggle:OnChanged(function(Value)
    Config.AutoFarmMobs = Value
    if Value then Config.AutoFarmRocks = false end
    ResetFarmState()
end)

--// PARRY SYSTEM \\--

task.spawn(function()
    while true do
        task.wait(0.1)
        if not ParryConfig.Enabled then continue end
        
        local Char = GetCharacter()
        local Root = Char and Char:FindFirstChild("HumanoidRootPart")
        if not Root then continue end

        local Living = Workspace:FindFirstChild("Living")
        if not Living then continue end

        for _, Mob in pairs(Living:GetChildren()) do
            if Mob:FindFirstChild("HumanoidRootPart") and not Players:GetPlayerFromCharacter(Mob) then
                local MobRoot = Mob.HumanoidRootPart
                local Dist = (Root.Position - MobRoot.Position).Magnitude
                
                if Dist <= ParryConfig.DetectionRange then
                    if not ActiveMobConnections[Mob] then
                        ActiveMobConnections[Mob] = MobRoot.ChildAdded:Connect(function(Child)
                            -- Construct Key: "MobName - SoundName"
                            local CleanName = CleanMobName(Mob.Name)
                            local Key = CleanName .. " - " .. Child.Name
                            
                            local Delay = ParryConfig.Delays[Key]
                            if Delay then
                                task.spawn(function() PerformParry(Delay) end)
                            end
                        end)
                    end
                else
                    if ActiveMobConnections[Mob] then
                        ActiveMobConnections[Mob]:Disconnect()
                        ActiveMobConnections[Mob] = nil
                    end
                end
            end
        end
        
        for Mob, Connection in pairs(ActiveMobConnections) do
            if not Mob.Parent then
                Connection:Disconnect()
                ActiveMobConnections[Mob] = nil
            end
        end
    end
end)

--// MAIN LOOP \\--

task.spawn(function()
    while true do
        task.wait()
        
        -- Animation Update Loop
        if not IsParrying then
            -- Check if we are farming OR if the player is manually moving
            local ShouldRun = Config.AutoFarmRocks or Config.AutoFarmMobs
            
            -- If not farming, check manual movement
            if not ShouldRun then
                local Char = GetCharacter()
                if Char and Char:FindFirstChild("Humanoid") then
                    if Char.Humanoid.MoveDirection.Magnitude > 0 then
                        ShouldRun = true
                    end
                end
            end
            
            ManageRunState(ShouldRun)
        end

        if IsParrying then 
            task.wait(0.1)
            continue 
        end

        if Config.AutoFarmRocks or Config.AutoFarmMobs then
            local Char = GetCharacter()
            
            if Char and Char:FindFirstChild("HumanoidRootPart") and Char:FindFirstChild("Humanoid") and Char.Humanoid.Health > 0 then
                
                local IsMobFarm = Config.AutoFarmMobs
                local ToolName = IsMobFarm and "Weapon" or "Pickaxe"
                EquipTool(ToolName)

                if CurrentTarget then
                    if not CurrentTarget.Parent then
                        CurrentTarget = nil
                    elseif IsMobFarm and CurrentTarget.Parent.Humanoid.Health <= 0 then
                        CurrentTarget = nil
                    elseif not IsMobFarm and IsRockBroken(CurrentTarget) then
                        CurrentTarget = nil
                    else
                        local Dist = (Char.HumanoidRootPart.Position - CurrentTarget.Position).Magnitude
                        if Dist > 200 then CurrentTarget = nil end
                    end
                end

                if not CurrentTarget then
                    if IsMobFarm then
                        CurrentTarget = GetClosestMob()
                    else
                        CurrentTarget = GetClosestRock()
                    end
                end
                
                if CurrentTarget then
                    local Root = Char.HumanoidRootPart
                    local Distance = (Root.Position - CurrentTarget.Position).Magnitude
                    
                    if Distance > Config.AttackDistance then
                        Fluent:Notify({
                            Title = "DonHub",
                            Content = "Moving to " .. (IsMobFarm and CleanMobName(CurrentTarget.Parent.Name) or CurrentTarget.Parent.Name),
                            Duration = 1
                        })
                        PathfindTo(CurrentTarget)
                    else
                        -- Stop running animation when we reach target and stop moving
                        ManageRunState(false) 
                        Char.Humanoid:MoveTo(Root.Position)
                        
                        local LookPos = CurrentTarget.Position
                        Root.CFrame = CFrame.new(Root.Position, Vector3.new(LookPos.X, Root.Position.Y, LookPos.Z))
                        
                        while (Config.AutoFarmRocks or Config.AutoFarmMobs) and CurrentTarget and CurrentTarget.Parent do
                            if IsParrying then 
                                task.wait() 
                                continue 
                            end

                            if IsMobFarm then
                                if CurrentTarget.Parent.Humanoid.Health <= 0 then CurrentTarget = nil break end
                            else
                                if IsRockBroken(CurrentTarget) then CurrentTarget = nil break end
                            end

                            local CurrentLook = Root.CFrame.LookVector
                            local TargetDir = (CurrentTarget.Position - Root.Position).Unit
                            local DotProduct = CurrentLook.X * TargetDir.X + CurrentLook.Z * TargetDir.Z
                            if DotProduct < 0.5 then
                                Root.CFrame = CFrame.new(Root.Position, Vector3.new(CurrentTarget.Position.X, Root.Position.Y, CurrentTarget.Position.Z))
                            end

                            if CurrentTarget.Position.Y > (Root.Position.Y + 3.5) then
                                Char.Humanoid.Jump = true
                            end

                            SwingTool(ToolName)
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
        end
    end
end)

--// CLEANUP \\--
Window:OnUnload(function()
    ScreenGui:Destroy()
    Config.AutoFarmRocks = false
    Config.AutoFarmMobs = false
    ParryConfig.Enabled = false
    ManageRunState(false)
end)

--// SAVE MANAGER \\--
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)
Fluent:Notify({
    Title = "DonHub",
    Content = "Loaded v1.2.0 Successfully!",
    Duration = 5
})
