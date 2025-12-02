local OrionLib = loadstring(game:HttpGet(('https://raw.githubusercontent.com/jensonhirst/Orion/main/source')))()
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

--// CONFIGURATION \\--
local Config = {
    AutoFarmRocks = false,
    AutoFarmMobs = false,
    SelectedRocks = {}, -- Multi-select table
    SelectedMobs = {},  -- Multi-select table
    AttackDistance = 7,
    SwingDelay = 0.3,
    RunSpeed = 21.69,
    WalkSpeed = 11.79,
    
    -- Parry Config
    AutoParry = true,
    ParryDistance = 10,
    ParryReactionTime = 0.25, -- Delay after sound before blocking
    BlockDuration = 0.25,     -- How long to hold block
}

--// SOUNDS TO PARRY \\--
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

--// STATE VARIABLES \\--
local CurrentAnimTrack = nil
local IsBlocking = false
local ActiveParries = {} -- Debounce table for sounds
local SpeedState = { Connection = nil, Humanoid = nil, IsRunning = false }

--// ANIMATION ASSETS \\--
local Anim_RunDefault = Instance.new("Animation")
Anim_RunDefault.AnimationId = "rbxassetid://120321298562953"

local Anim_RunPickaxe = Instance.new("Animation")
Anim_RunPickaxe.AnimationId = "rbxassetid://91424712336158" -- Also used for Weapon run usually

--// UI SETUP \\--
local Window = OrionLib:MakeWindow({Name = "The Forge | Script Hub V11", HidePremium = false, SaveConfig = true, ConfigFolder = "TheForgeHub_V11"})

-- TABS
local FarmTab = Window:MakeTab({ Name = "Rock Farm", Icon = "rbxassetid://4483345998", PremiumOnly = false })
local MobTab = Window:MakeTab({ Name = "Mob Farm", Icon = "rbxassetid://4483345998", PremiumOnly = false })

--// DATA GATHERING \\--
local RockOptions = {}
local RocksAssetFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Rocks")
for _, rock in pairs(RocksAssetFolder:GetChildren()) do table.insert(RockOptions, rock.Name) end
table.sort(RockOptions)

local MobOptions = {}
local MobsAssetFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Mobs")
for _, mob in pairs(MobsAssetFolder:GetChildren()) do table.insert(MobOptions, mob.Name) end
table.sort(MobOptions)

--// UI FUNCTIONS \\--

-- Multi-Select Helper
local function ToggleSelection(List, Value)
    if table.find(List, Value) then
        table.remove(List, table.find(List, Value))
        OrionLib:MakeNotification({Name = "Removed", Content = "Removed " .. Value, Time = 1})
    else
        table.insert(List, Value)
        OrionLib:MakeNotification({Name = "Added", Content = "Added " .. Value, Time = 1})
    end
end

--// ROCK FARM UI \\--
FarmTab:AddSection({ Name = "Rock Selection (Multi-Select)" })
FarmTab:AddDropdown({
	Name = "Toggle Rocks",
	Default = "",
	Options = RockOptions,
	Callback = function(Value)
		ToggleSelection(Config.SelectedRocks, Value)
	end    
})

FarmTab:AddSection({ Name = "Automation" })
FarmTab:AddToggle({
	Name = "Enable Rock Farm",
	Default = false,
	Callback = function(Value)
		Config.AutoFarmRocks = Value
        if not Value then StopAllActions() end
	end    
})

--// MOB FARM UI \\--
MobTab:AddSection({ Name = "Mob Selection (Multi-Select)" })
MobTab:AddDropdown({
	Name = "Toggle Mobs",
	Default = "",
	Options = MobOptions,
	Callback = function(Value)
		ToggleSelection(Config.SelectedMobs, Value)
	end    
})

MobTab:AddSection({ Name = "Automation" })
MobTab:AddToggle({
	Name = "Enable Mob Farm",
	Default = false,
	Callback = function(Value)
		Config.AutoFarmMobs = Value
        if not Value then StopAllActions() end
	end    
})

MobTab:AddSection({ Name = "Combat Config" })
MobTab:AddToggle({
    Name = "Auto Parry",
    Default = true,
    Callback = function(Value) Config.AutoParry = Value end
})

--// HELPER FUNCTIONS \\--

function GetCharacter()
    if Workspace:FindFirstChild("Living") then
        local LivingChar = Workspace.Living:FindFirstChild(LocalPlayer.Name)
        if LivingChar then return LivingChar end
    end
    return LocalPlayer.Character
end

function StopAllActions()
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

--// COMBAT & PARRY LOGIC \\--

function PerformBlock()
    if IsBlocking then return end
    IsBlocking = true
    
    local Char = GetCharacter()
    if Char and Char:FindFirstChild("Humanoid") then
        Char.Humanoid:MoveTo(Char.HumanoidRootPart.Position) -- Stop Moving
    end

    -- Start Block
    pcall(function()
        game:GetService("ReplicatedStorage").Shared.Packages.Knit.Services.ToolService.RF.StartBlock:InvokeServer()
    end)

    task.wait(Config.BlockDuration)

    -- Stop Block
    pcall(function()
        game:GetService("ReplicatedStorage").Shared.Packages.Knit.Services.ToolService.RF.StopBlock:InvokeServer()
    end)
    
    IsBlocking = false
end

-- Auto Parry Loop
task.spawn(function()
    while true do
        task.wait() -- Fast check
        if Config.AutoParry and (Config.AutoFarmMobs or Config.AutoFarmRocks) then
            local Char = GetCharacter()
            local Root = Char and Char:FindFirstChild("HumanoidRootPart")
            
            if Root then
                -- Scan Living folder
                if Workspace:FindFirstChild("Living") then
                    for _, Entity in pairs(Workspace.Living:GetChildren()) do
                        -- Filter out self and Players
                        if Entity ~= Char and not Players:GetPlayerFromCharacter(Entity) then
                            local EntityRoot = Entity:FindFirstChild("HumanoidRootPart")
                            if EntityRoot and (EntityRoot.Position - Root.Position).Magnitude <= Config.ParryDistance then
                                
                                -- Check Sounds in HRP
                                for _, Sound in pairs(EntityRoot:GetChildren()) do
                                    if Sound:IsA("Sound") and table.find(ParrySounds, Sound.Name) and Sound.Playing then
                                        
                                        -- Debounce check (don't block same sound twice)
                                        if not ActiveParries[Sound] then
                                            ActiveParries[Sound] = true
                                            
                                            -- Handle Parry Logic in new thread
                                            task.spawn(function()
                                                task.wait(Config.ParryReactionTime) -- Reaction Delay
                                                PerformBlock()
                                                
                                                -- Cleanup debounce after sound finishes
                                                task.wait(2) 
                                                ActiveParries[Sound] = nil
                                            end)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

--// MOVEMENT & STATE \\--

function ManageRunState(ShouldRun)
    local Char = GetCharacter()
    if not Char then return end
    local Humanoid = Char:FindFirstChild("Humanoid")
    local Animator = Humanoid and Humanoid:FindFirstChild("Animator")
    if not Humanoid then return end

    if ShouldRun and not IsBlocking then
        -- Speed Enforcer
        if SpeedState.Humanoid ~= Humanoid or not SpeedState.IsRunning then
            if SpeedState.Connection then SpeedState.Connection:Disconnect() end
            local function EnforceSpeed()
                if Humanoid.WalkSpeed ~= Config.RunSpeed and not IsBlocking then
                    Humanoid.WalkSpeed = Config.RunSpeed
                end
            end
            EnforceSpeed()
            SpeedState.Connection = Humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(EnforceSpeed)
            SpeedState.Humanoid = Humanoid
            SpeedState.IsRunning = true
        end

        -- Animation
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
        -- Stop
        if SpeedState.Connection then SpeedState.Connection:Disconnect() SpeedState.Connection = nil end
        SpeedState.IsRunning = false
        Humanoid.WalkSpeed = Config.WalkSpeed
        if CurrentAnimTrack then CurrentAnimTrack:Stop() CurrentAnimTrack = nil end
    end
end

function PathfindTo(TargetPosition)
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

    local Success = pcall(function() Path:ComputeAsync(Root.Position, TargetPosition) end)

    if Success and Path.Status == Enum.PathStatus.Success then
        local Waypoints = Path:GetWaypoints()
        ManageRunState(true)

        for i, Waypoint in pairs(Waypoints) do
            if not Config.AutoFarmRocks and not Config.AutoFarmMobs then break end
            
            -- PAUSE MOVEMENT IF BLOCKING
            while IsBlocking do
                ManageRunState(false) -- Stop run anim
                task.wait()
            end
            ManageRunState(true) -- Resume run

            Humanoid:MoveTo(Waypoint.Position)
            if Waypoint.Action == Enum.PathWaypointAction.Jump then Humanoid.Jump = true end
            
            local Timeout = 0
            while (Config.AutoFarmRocks or Config.AutoFarmMobs) do
                -- Pause if blocking
                if IsBlocking then break end

                local DistToWaypoint = (Root.Position - Waypoint.Position).Magnitude
                if DistToWaypoint < 4 then break end
                
                Timeout = Timeout + 0.1
                if Timeout > 2 then break end

                -- If close to final target, break early
                if (Root.Position - TargetPosition).Magnitude < Config.AttackDistance then return end
                
                task.wait(0.1)
            end
        end
    else
        ManageRunState(true)
        Humanoid:MoveTo(TargetPosition)
    end
end

--// LOGIC: ROCKS \\--

function IsRockBroken(RockModel)
    if not RockModel or not RockModel.Parent then return true end
    local InfoFrame = RockModel:FindFirstChild("infoFrame")
    if InfoFrame then
        local Frame = InfoFrame:FindFirstChild("Frame")
        if Frame then
            local HPLabel = Frame:FindFirstChild("rockHP")
            if HPLabel and (HPLabel.Text == "0 HP" or string.sub(HPLabel.Text, 1, 2) == "0/") then
                return true
            end
        end
    end
    return false
end

function GetClosestRock()
    local Char = GetCharacter()
    local Root = Char and Char:FindFirstChild("HumanoidRootPart")
    if not Root then return nil end
    local Closest, ClosestDist = nil, math.huge

    if Workspace:FindFirstChild("Rocks") then
        for _, Area in pairs(Workspace.Rocks:GetChildren()) do
            for _, Container in pairs(Area:GetChildren()) do
                for _, Item in pairs(Container:GetChildren()) do
                    if table.find(Config.SelectedRocks, Item.Name) and Item:FindFirstChild("Hitbox") then
                        if not IsRockBroken(Item) then
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
    end
    return Closest
end

function MineRock()
    pcall(function()
        game:GetService("ReplicatedStorage").Shared.Packages.Knit.Services.ToolService.RF.ToolActivated:InvokeServer("Pickaxe")
    end)
end

--// LOGIC: MOBS \\--

function GetClosestMob()
    local Char = GetCharacter()
    local Root = Char and Char:FindFirstChild("HumanoidRootPart")
    if not Root then return nil end
    local Closest, ClosestDist = nil, math.huge

    if Workspace:FindFirstChild("Living") then
        for _, Entity in pairs(Workspace.Living:GetChildren()) do
            if Entity ~= Char and not Players:GetPlayerFromCharacter(Entity) then
                if table.find(Config.SelectedMobs, Entity.Name) and Entity:FindFirstChild("HumanoidRootPart") and Entity:FindFirstChild("Humanoid") and Entity.Humanoid.Health > 0 then
                    local Dist = (Root.Position - Entity.HumanoidRootPart.Position).Magnitude
                    if Dist < ClosestDist then
                        ClosestDist = Dist
                        Closest = Entity.HumanoidRootPart
                    end
                end
            end
        end
    end
    return Closest
end

function AttackMob()
    pcall(function()
        game:GetService("ReplicatedStorage").Shared.Packages.Knit.Services.ToolService.RF.ToolActivated:InvokeServer("Weapon")
    end)
end

--// MAIN LOOPS \\--

-- Rock Farm Loop
task.spawn(function()
    while true do
        task.wait()
        if Config.AutoFarmRocks and not Config.AutoFarmMobs then
            local Char = GetCharacter()
            if Char and Char:FindFirstChild("HumanoidRootPart") and Char.Humanoid.Health > 0 then
                EquipTool("Pickaxe")
                local TargetHitbox = GetClosestRock()
                
                if TargetHitbox then
                    local Root = Char.HumanoidRootPart
                    local RockModel = TargetHitbox.Parent
                    local Dist = (Root.Position - TargetHitbox.Position).Magnitude
                    
                    if Dist > Config.AttackDistance then
                        OrionLib:MakeNotification({Name = "Farming", Content = "Running to " .. RockModel.Name, Time = 1})
                        PathfindTo(TargetHitbox.Position)
                    else
                        -- MINING PHASE
                        ManageRunState(false)
                        Char.Humanoid:MoveTo(Root.Position)
                        
                        -- Look at rock once
                        local LookPos = TargetHitbox.Position
                        Root.CFrame = CFrame.new(Root.Position, Vector3.new(LookPos.X, Root.Position.Y, LookPos.Z))

                        -- Lock on until broken
                        while Config.AutoFarmRocks and RockModel and RockModel.Parent do
                            if IsRockBroken(RockModel) then break end
                            if IsBlocking then 
                                task.wait() 
                            else
                                MineRock()
                                task.wait(Config.SwingDelay)
                            end
                            
                            -- Break if too far (safety only, increased range)
                            if (Root.Position - TargetHitbox.Position).Magnitude > Config.AttackDistance + 15 then break end
                            if Char.Humanoid.Health <= 0 then break end
                        end
                    end
                end
            end
        end
    end
end)

-- Mob Farm Loop
task.spawn(function()
    while true do
        task.wait()
        if Config.AutoFarmMobs and not Config.AutoFarmRocks then
            local Char = GetCharacter()
            if Char and Char:FindFirstChild("HumanoidRootPart") and Char.Humanoid.Health > 0 then
                EquipTool("Weapon")
                local TargetHRP = GetClosestMob()
                
                if TargetHRP then
                    local Root = Char.HumanoidRootPart
                    local MobModel = TargetHRP.Parent
                    local Dist = (Root.Position - TargetHRP.Position).Magnitude
                    
                    if Dist > Config.AttackDistance then
                        OrionLib:MakeNotification({Name = "Combat", Content = "Running to " .. MobModel.Name, Time = 1})
                        PathfindTo(TargetHRP.Position)
                    else
                        -- ATTACK PHASE
                        ManageRunState(false)
                        Char.Humanoid:MoveTo(Root.Position)
                        
                        local LookPos = TargetHRP.Position
                        Root.CFrame = CFrame.new(Root.Position, Vector3.new(LookPos.X, Root.Position.Y, LookPos.Z))

                        while Config.AutoFarmMobs and MobModel and MobModel.Parent and MobModel:FindFirstChild("Humanoid") and MobModel.Humanoid.Health > 0 do
                            if IsBlocking then
                                task.wait()
                            else
                                -- Update facing
                                Root.CFrame = CFrame.new(Root.Position, Vector3.new(TargetHRP.Position.X, Root.Position.Y, TargetHRP.Position.Z))
                                AttackMob()
                                task.wait(Config.SwingDelay)
                            end

                            if (Root.Position - TargetHRP.Position).Magnitude > Config.AttackDistance + 10 then break end
                            if Char.Humanoid.Health <= 0 then break end
                        end
                    end
                end
            end
        end
    end
end)

OrionLib:Init()