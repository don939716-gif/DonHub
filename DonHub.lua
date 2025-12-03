local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")

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
    WalkSpeed = 11.79
}

--// PARRY CONFIGURATION (In-Code) \\--
local ParryConfig = {
    Enabled = true,
    ReactionDelay = 0.25, -- Delay after sound is detected before blocking
    BlockDuration = 0.25, -- How long to hold block
    DetectionRange = 15   -- Studs
}

local AttackSounds = {
    ["Zombie Swing 1"] = true, ["Zombie Swing 2"] = true,
    ["Colossal Weapon Swing 1"] = true, ["Colossal Weapon Swing 2"] = true,
    ["Dagger Swing 1"] = true, ["Dagger Swing 2"] = true,
    ["Gauntlet Swing 1"] = true, ["Gauntlet Swing 2"] = true,
    ["Greataxe Swing 1"] = true, ["Greataxe Swing 2"] = true,
    ["Greatsword Swing 1"] = true, ["Greatsword Swing 2"] = true,
    ["Katana Swing 1"] = true, ["Katana Swing 2"] = true, ["Katana Swing 3"] = true,
    ["Straight Swing 1"] = true, ["Straight Swing 2"] = true
}

--// STATE VARIABLES \\--
local CurrentTarget = nil
local CurrentAnimTrack = nil
local IsBlocking = false
local SpeedState = { Connection = nil, Humanoid = nil, IsRunning = false }
local ConnectedMobs = {} -- Tracks mobs we are listening to for parrying

--// UI SETUP \\--
local Window = Fluent:CreateWindow({
    Title = "The Forge | Script Hub V12",
    SubTitle = "by DonHub",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Farm = Window:AddTab({ Title = "Auto Farm", Icon = "pickaxe" }),
    MobFarm = Window:AddTab({ Title = "Mob Farm", Icon = "swords" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

--// MOBILE TOGGLE UI \\--
local MobileGui = Instance.new("ScreenGui")
MobileGui.Name = "TheForgeMobileGUI"
MobileGui.Parent = CoreGui

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Name = "ToggleBtn"
ToggleBtn.Parent = MobileGui
ToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
ToggleBtn.BorderSizePixel = 0
ToggleBtn.Position = UDim2.new(0.8, 0, 0.1, 0)
ToggleBtn.Size = UDim2.new(0, 50, 0, 50)
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.Text = "UI"
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.TextSize = 20
ToggleBtn.AutoButtonColor = true

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 10)
UICorner.Parent = ToggleBtn

local UIStroke = Instance.new("UIStroke")
UIStroke.Color = Color3.fromRGB(100, 100, 100)
UIStroke.Thickness = 2
UIStroke.Parent = ToggleBtn

-- Mobile Button Logic
local IsOpen = true
ToggleBtn.MouseButton1Click:Connect(function()
    IsOpen = not IsOpen
    Window.Root.Visible = IsOpen
end)

-- Cleanup function for when script reloads/destroys
local function Cleanup()
    MobileGui:Destroy()
    for _, conn in pairs(ConnectedMobs) do
        if conn then conn:Disconnect() end
    end
end

--// DATA GATHERING \\--

-- Get Rock Names
local RockOptions = {}
local RocksAssetFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Rocks")
for _, rock in pairs(RocksAssetFolder:GetChildren()) do
    table.insert(RockOptions, rock.Name)
end
table.sort(RockOptions)

-- Get Mob Names (Scan Workspace.Living)
local MobOptions = {}
local MobSet = {}
local LivingFolder = Workspace:WaitForChild("Living")

local function RefreshMobs()
    MobOptions = {}
    MobSet = {}
    for _, model in pairs(LivingFolder:GetChildren()) do
        if model:IsA("Model") and model:FindFirstChild("Humanoid") and not Players:GetPlayerFromCharacter(model) then
            -- Clean name (remove numbers if needed, though game usually keeps them clean or we want specific IDs)
            -- For dropdown, we usually want unique names.
            -- Assuming names like "Zombie" or "Delver Zombie"
            local Name = model.Name
            -- Optional: Strip numbers if names are like "Zombie123"
            -- Name = string.match(Name, "^%D+") or Name 
            
            if not MobSet[Name] then
                MobSet[Name] = true
                table.insert(MobOptions, Name)
            end
        end
    end
    table.sort(MobOptions)
end
RefreshMobs()

--// UI ELEMENTS - ROCKS \\--

local RockDropdown = Tabs.Farm:AddDropdown("RockSelection", {
    Title = "Select Rocks",
    Description = "Select multiple rocks to farm.",
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

local RockToggle = Tabs.Farm:AddToggle("AutoFarmRocks", {Title = "Enable Rock Farm", Default = false })
RockToggle:OnChanged(function(Value)
    Config.AutoFarmRocks = Value
    if Value then Config.AutoFarmMobs = false end -- Mutually exclusive
    ResetFarmState(Value)
end)

--// UI ELEMENTS - MOBS \\--

local MobDropdown = Tabs.MobFarm:AddDropdown("MobSelection", {
    Title = "Select Mobs",
    Description = "Select multiple mobs to hunt.",
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

Tabs.MobFarm:AddButton({
    Title = "Refresh Mob List",
    Description = "Click this if new mobs spawned.",
    Callback = function()
        RefreshMobs()
        MobDropdown:SetValues(MobOptions)
    end
})

local MobToggle = Tabs.MobFarm:AddToggle("AutoFarmMobs", {Title = "Enable Mob Farm", Default = false })
MobToggle:OnChanged(function(Value)
    Config.AutoFarmMobs = Value
    if Value then Config.AutoFarmRocks = false end -- Mutually exclusive
    ResetFarmState(Value)
end)

--// HELPER FUNCTIONS \\--

function ResetFarmState(Value)
    pcall(function()
        if Value then
            print("Farm Started")
        else
            CurrentTarget = nil
            ManageRunState(false)
            local Char = GetCharacter()
            if Char and Char:FindFirstChild("Humanoid") then
                Char.Humanoid:MoveTo(Char.HumanoidRootPart.Position)
            end
        end
    end)
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

-- Speed & Animation Manager
function ManageRunState(ShouldRun)
    local Char = GetCharacter()
    if not Char then return end
    local Humanoid = Char:FindFirstChild("Humanoid")
    local Animator = Humanoid and Humanoid:FindFirstChild("Animator")
    
    if not Humanoid then return end

    if ShouldRun and not IsBlocking then
        -- Force Speed
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

        -- Play Animation
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
        -- Stop Speed
        if SpeedState.Connection then
            SpeedState.Connection:Disconnect()
            SpeedState.Connection = nil
        end
        SpeedState.IsRunning = false
        SpeedState.Humanoid = nil
        Humanoid.WalkSpeed = Config.WalkSpeed

        -- Stop Animation
        if CurrentAnimTrack then
            CurrentAnimTrack:Stop()
            CurrentAnimTrack = nil
        end
    end
end

--// PARRY LOGIC \\--

function PerformBlock()
    if IsBlocking then return end
    IsBlocking = true
    
    local Char = GetCharacter()
    if Char and Char:FindFirstChild("Humanoid") then
        -- Stop moving immediately
        Char.Humanoid:MoveTo(Char.HumanoidRootPart.Position)
        ManageRunState(false)
    end

    -- Start Block
    pcall(function()
        game:GetService("ReplicatedStorage").Shared.Packages.Knit.Services.ToolService.RF.StartBlock:InvokeServer()
    end)

    task.wait(ParryConfig.BlockDuration)

    -- Stop Block
    pcall(function()
        game:GetService("ReplicatedStorage").Shared.Packages.Knit.Services.ToolService.RF.StopBlock:InvokeServer()
    end)

    IsBlocking = false
end

-- Background loop to listen for parry sounds
task.spawn(function()
    while true do
        task.wait(0.1)
        if not ParryConfig.Enabled then continue end

        local Char = GetCharacter()
        if not Char or not Char:FindFirstChild("HumanoidRootPart") then continue end
        local MyRoot = Char.HumanoidRootPart

        -- Scan nearby mobs
        for _, mob in pairs(LivingFolder:GetChildren()) do
            if mob:IsA("Model") and mob:FindFirstChild("HumanoidRootPart") and mob:FindFirstChild("Humanoid") then
                -- Filter Players
                if Players:GetPlayerFromCharacter(mob) then continue end
                
                -- Check Distance
                local Dist = (mob.HumanoidRootPart.Position - MyRoot.Position).Magnitude
                
                if Dist <= ParryConfig.DetectionRange then
                    -- Connect listener if not already connected
                    if not ConnectedMobs[mob] then
                        ConnectedMobs[mob] = mob.HumanoidRootPart.ChildAdded:Connect(function(Child)
                            if Child:IsA("Sound") and AttackSounds[Child.Name] then
                                -- Sound detected! Wait delay then block
                                task.delay(ParryConfig.ReactionDelay, function()
                                    PerformBlock()
                                end)
                            end
                        end)
                    end
                else
                    -- Cleanup distant mobs
                    if ConnectedMobs[mob] then
                        ConnectedMobs[mob]:Disconnect()
                        ConnectedMobs[mob] = nil
                    end
                end
            end
        end
        
        -- Cleanup dead/removed mobs from table
        for mob, conn in pairs(ConnectedMobs) do
            if not mob.Parent then
                conn:Disconnect()
                ConnectedMobs[mob] = nil
            end
        end
    end
end)

--// FARMING LOGIC \\--

function IsRockBroken(Hitbox)
    if not Hitbox or not Hitbox.Parent then return true end
    local RockModel = Hitbox.Parent
    local InfoFrame = RockModel:FindFirstChild("infoFrame")
    if InfoFrame and InfoFrame:FindFirstChild("Frame") and InfoFrame.Frame:FindFirstChild("rockHP") then
        local Text = InfoFrame.Frame.rockHP.Text
        if Text == "0 HP" or string.sub(Text, 1, 2) == "0/" then return true end
    end
    return false
end

function GetClosestRock()
    local Char = GetCharacter()
    local Root = Char and Char:FindFirstChild("HumanoidRootPart")
    if not Root then return nil end

    local Closest, ClosestDist = nil, math.huge
    local RocksFolder = Workspace:FindFirstChild("Rocks")
    if not RocksFolder then return nil end
    
    for _, Area in pairs(RocksFolder:GetChildren()) do
        for _, Container in pairs(Area:GetChildren()) do
            for _, Item in pairs(Container:GetChildren()) do
                if table.find(Config.SelectedRocks, Item.Name) and Item:FindFirstChild("Hitbox") then
                    if not IsRockBroken(Item.Hitbox) then
                        local Dist = (Root.Position - Item.Hitbox.Position).Magnitude
                        if Dist < ClosestDist then
                            ClosestDist = Dist
                            Closest = Item.Hitbox
                        end
                    end
                end
            end
        end
    end
    return Closest
end

function GetClosestMob()
    local Char = GetCharacter()
    local Root = Char and Char:FindFirstChild("HumanoidRootPart")
    if not Root then return nil end

    local Closest, ClosestDist = nil, math.huge
    
    for _, mob in pairs(LivingFolder:GetChildren()) do
        if mob:IsA("Model") and mob:FindFirstChild("HumanoidRootPart") and mob:FindFirstChild("Humanoid") then
            if Players:GetPlayerFromCharacter(mob) then continue end -- Skip Players
            if mob.Humanoid.Health <= 0 then continue end -- Skip Dead
            
            if table.find(Config.SelectedMobs, mob.Name) then
                local Dist = (Root.Position - mob.HumanoidRootPart.Position).Magnitude
                if Dist < ClosestDist then
                    ClosestDist = Dist
                    Closest = mob.HumanoidRootPart
                end
            end
        end
    end
    return Closest
end

function SwingTool(ToolName)
    local args = { ToolName }
    pcall(function()
        game:GetService("ReplicatedStorage").Shared.Packages.Knit.Services.ToolService.RF.ToolActivated:InvokeServer(unpack(args))
    end)
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
            if not (Config.AutoFarmRocks or Config.AutoFarmMobs) then break end
            if IsBlocking then 
                -- Wait while blocking
                while IsBlocking do task.wait(0.1) end
                -- Recalculate path might be needed, but for now just continue
            end

            -- Check if target is invalid
            if not TargetPart or not TargetPart.Parent then return end
            if Config.AutoFarmRocks and IsRockBroken(TargetPart) then return end
            if Config.AutoFarmMobs and TargetPart.Parent.Humanoid.Health <= 0 then return end

            Humanoid:MoveTo(Waypoint.Position)
            if Waypoint.Action == Enum.PathWaypointAction.Jump then Humanoid.Jump = true end
            
            local Timeout = 0
            while (Config.AutoFarmRocks or Config.AutoFarmMobs) do
                if IsBlocking then break end -- Break wait loop to handle block
                
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
        
        if IsBlocking then
            -- Do nothing while blocking
            task.wait(0.1)
            continue
        end

        if Config.AutoFarmRocks or Config.AutoFarmMobs then
            local Char = GetCharacter()
            
            if Char and Char:FindFirstChild("HumanoidRootPart") and Char:FindFirstChild("Humanoid") and Char.Humanoid.Health > 0 then
                
                -- DETERMINE MODE & TARGET
                local ToolName = "Pickaxe"
                if Config.AutoFarmMobs then ToolName = "Weapon" end
                
                EquipTool(ToolName)

                -- Target Validation
                if CurrentTarget then
                    if not CurrentTarget.Parent then
                        CurrentTarget = nil
                    elseif Config.AutoFarmRocks and IsRockBroken(CurrentTarget) then
                        CurrentTarget = nil
                    elseif Config.AutoFarmMobs and CurrentTarget.Parent.Humanoid.Health <= 0 then
                        CurrentTarget = nil
                    else
                        local Dist = (Char.HumanoidRootPart.Position - CurrentTarget.Position).Magnitude
                        if Dist > 300 then CurrentTarget = nil end
                    end
                end

                -- Target Acquisition
                if not CurrentTarget then
                    if Config.AutoFarmRocks then
                        CurrentTarget = GetClosestRock()
                    elseif Config.AutoFarmMobs then
                        CurrentTarget = GetClosestMob()
                    end
                end
                
                -- Execution
                if CurrentTarget then
                    local Root = Char.HumanoidRootPart
                    local Distance = (Root.Position - CurrentTarget.Position).Magnitude
                    
                    if Distance > Config.AttackDistance then
                        -- RUNNING
                        Fluent:Notify({Title = "Farming", Content = "Moving to " .. CurrentTarget.Parent.Name, Duration = 1})
                        PathfindTo(CurrentTarget)
                    else
                        -- ATTACKING
                        ManageRunState(false)
                        Char.Humanoid:MoveTo(Root.Position)
                        
                        -- Face Target
                        local LookPos = CurrentTarget.Position
                        Root.CFrame = CFrame.new(Root.Position, Vector3.new(LookPos.X, Root.Position.Y, LookPos.Z))
                        
                        while (Config.AutoFarmRocks or Config.AutoFarmMobs) and CurrentTarget and CurrentTarget.Parent do
                            if IsBlocking then 
                                task.wait(0.1) 
                                continue 
                            end

                            -- Break conditions
                            if Config.AutoFarmRocks and IsRockBroken(CurrentTarget) then CurrentTarget = nil break end
                            if Config.AutoFarmMobs and CurrentTarget.Parent.Humanoid.Health <= 0 then CurrentTarget = nil break end

                            -- Face Target Logic
                            local CurrentLook = Root.CFrame.LookVector
                            local TargetDir = (CurrentTarget.Position - Root.Position).Unit
                            if (CurrentLook.X * TargetDir.X + CurrentLook.Z * TargetDir.Z) < 0.5 then
                                Root.CFrame = CFrame.new(Root.Position, Vector3.new(CurrentTarget.Position.X, Root.Position.Y, CurrentTarget.Position.Z))
                            end

                            -- Jump if high
                            if CurrentTarget.Position.Y > (Root.Position.Y + 3.5) then Char.Humanoid.Jump = true end

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
        else
            ManageRunState(false)
        end
    end
end)

--// CLEANUP ON DESTROY \\--
Fluent:OnUnload(function()
    Cleanup()
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
    Title = "The Forge Hub",
    Content = "Script Loaded Successfully!",
    Duration = 5
})