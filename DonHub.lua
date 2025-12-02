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
    SelectedRocks = {},
    SelectedMobs = {},
    AttackDistance = 7,
    SwingDelay = 0.3,
    RunSpeed = 21.69,
    WalkSpeed = 11.79,
    ParryEnabled = true,
    ParryDelay = 0.25, -- Time between sound and block
    BlockDuration = 0.25 -- How long to hold block
}

--// SOUND LIST FOR PARRY \\--
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
local CurrentAnimTrack = nil
local SpeedState = { Connection = nil, Humanoid = nil, IsRunning = false }
local ActionState = { IsParrying = false, CurrentTarget = nil }

--// UI SETUP \\--
local Window = OrionLib:MakeWindow({Name = "The Forge | Script Hub V11", HidePremium = false, SaveConfig = true, ConfigFolder = "TheForgeHub_V11"})

-- TABS
local FarmTab = Window:MakeTab({Name = "Rock Farm", Icon = "rbxassetid://4483345998", PremiumOnly = false})
local MobTab = Window:MakeTab({Name = "Mob Farm", Icon = "rbxassetid://4483345998", PremiumOnly = false})

--// POPULATE LISTS \\--
local RockOptions = {}
local RocksAssetFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Rocks")
for _, rock in pairs(RocksAssetFolder:GetChildren()) do table.insert(RockOptions, rock.Name) end
table.sort(RockOptions)

local MobOptions = {}
-- We scan workspace.Living initially, but this might change, so we can also check ReplicatedStorage Assets if available
-- For now, we scan current workspace + ReplicatedStorage Assets Mobs if they exist
local MobsAssetFolder = ReplicatedStorage:WaitForChild("Assets"):FindFirstChild("Mobs")
if MobsAssetFolder then
    for _, mob in pairs(MobsAssetFolder:GetChildren()) do table.insert(MobOptions, mob.Name) end
else
    -- Fallback to scanning workspace
    for _, obj in pairs(Workspace:WaitForChild("Living"):GetChildren()) do
        if not Players:GetPlayerFromCharacter(obj) then table.insert(MobOptions, obj.Name) end
    end
end
table.sort(MobOptions)

--// UI HELPER: MULTI-SELECT LOGIC \\--
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
FarmTab:AddSection({Name = "Rock Selection (Multi-Select)"})
FarmTab:AddDropdown({
    Name = "Select Rocks", Default = "", Options = RockOptions,
    Callback = function(Value) ToggleSelection(Config.SelectedRocks, Value) end
})

FarmTab:AddSection({Name = "Automation"})
FarmTab:AddToggle({
    Name = "Enable Rock Auto Farm", Default = false,
    Callback = function(Value)
        Config.AutoFarmRocks = Value
        if not Value then StopAllActions() end
    end
})

--// MOB FARM UI \\--
MobTab:AddSection({Name = "Mob Selection (Multi-Select)"})
MobTab:AddDropdown({
    Name = "Select Mobs", Default = "", Options = MobOptions,
    Callback = function(Value) ToggleSelection(Config.SelectedMobs, Value) end
})

MobTab:AddSection({Name = "Automation"})
MobTab:AddToggle({
    Name = "Enable Mob Auto Farm", Default = false,
    Callback = function(Value)
        Config.AutoFarmMobs = Value
        if not Value then StopAllActions() end
    end
})

MobTab:AddToggle({
    Name = "Enable Auto Parry", Default = true,
    Callback = function(Value) Config.ParryEnabled = Value end
})

--// HELPER FUNCTIONS \\--

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

function StopAllActions()
    ManageRunState(false)
    local Char = GetCharacter()
    if Char and Char:FindFirstChild("Humanoid") then
        Char.Humanoid:MoveTo(Char.HumanoidRootPart.Position)
    end
    ActionState.CurrentTarget = nil
end

--// COMBAT & MINING REMOTES \\--
function SwingTool(ToolName)
    local args = { ToolName }
    pcall(function()
        game:GetService("ReplicatedStorage").Shared.Packages.Knit.Services.ToolService.RF.ToolActivated:InvokeServer(unpack(args))
    end)
end

function Block(IsBlocking)
    local RemoteName = IsBlocking and "StartBlock" or "StopBlock"
    pcall(function()
        game:GetService("ReplicatedStorage").Shared.Packages.Knit.Services.ToolService.RF[RemoteName]:InvokeServer()
    end)
end

--// TARGET FINDING \\--

function IsTargetBroken(Model)
    if not Model or not Model.Parent then return true end
    
    -- Check HP for Rocks
    local InfoFrame = Model:FindFirstChild("infoFrame")
    if InfoFrame and InfoFrame:FindFirstChild("Frame") then
        local HPLabel = InfoFrame.Frame:FindFirstChild("rockHP")
        if HPLabel and (HPLabel.Text == "0 HP" or string.sub(HPLabel.Text, 1, 2) == "0/") then
            return true
        end
    end
    
    -- Check HP for Mobs
    local Humanoid = Model:FindFirstChild("Humanoid")
    if Humanoid and Humanoid.Health <= 0 then
        return true
    end
    
    return false
end

function GetClosestTarget(IsMob)
    local Char = GetCharacter()
    local Root = Char and Char:FindFirstChild("HumanoidRootPart")
    if not Root then return nil end

    local ClosestTarget = nil
    local ClosestDist = math.huge
    local SelectedList = IsMob and Config.SelectedMobs or Config.SelectedRocks

    if IsMob then
        -- Scan Mobs in Workspace.Living
        if Workspace:FindFirstChild("Living") then
            for _, Obj in pairs(Workspace.Living:GetChildren()) do
                -- Filter Players
                if not Players:GetPlayerFromCharacter(Obj) and table.find(SelectedList, Obj.Name) then
                    local HRP = Obj:FindFirstChild("HumanoidRootPart")
                    local Hum = Obj:FindFirstChild("Humanoid")
                    if HRP and Hum and Hum.Health > 0 then
                        local Dist = (Root.Position - HRP.Position).Magnitude
                        if Dist < ClosestDist then
                            ClosestDist = Dist
                            ClosestTarget = HRP -- Return Hitbox/Root
                        end
                    end
                end
            end
        end
    else
        -- Scan Rocks
        local RocksFolder = Workspace:FindFirstChild("Rocks")
        if RocksFolder then
            for _, Area in pairs(RocksFolder:GetChildren()) do
                for _, Container in pairs(Area:GetChildren()) do
                    for _, Item in pairs(Container:GetChildren()) do
                        if table.find(SelectedList, Item.Name) and Item:FindFirstChild("Hitbox") then
                            if not IsTargetBroken(Item) then
                                local Hitbox = Item.Hitbox
                                local Dist = (Root.Position - Hitbox.Position).Magnitude
                                if Dist < ClosestDist then
                                    ClosestDist = Dist
                                    ClosestTarget = Hitbox
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

--// PARRY LOGIC \\--
function HandleParry()
    if not Config.ParryEnabled then return end
    
    -- Listener for sounds is set up via ChildAdded on nearby mobs
    -- We run a loop to attach listeners to new mobs
    local Char = GetCharacter()
    local Root = Char and Char:FindFirstChild("HumanoidRootPart")
    if not Root then return end

    if Workspace:FindFirstChild("Living") then
        for _, Mob in pairs(Workspace.Living:GetChildren()) do
            if not Players:GetPlayerFromCharacter(Mob) and Mob:FindFirstChild("HumanoidRootPart") then
                local HRP = Mob.HumanoidRootPart
                local Dist = (Root.Position - HRP.Position).Magnitude
                
                if Dist <= 10 then
                    -- Check if we already attached a listener (using a tag or attribute)
                    if not HRP:GetAttribute("ParryListener") then
                        HRP:SetAttribute("ParryListener", true)
                        
                        HRP.ChildAdded:Connect(function(Child)
                            if Child:IsA("Sound") and table.find(ParrySounds, Child.Name) then
                                -- Sound Detected!
                                task.spawn(function()
                                    if ActionState.IsParrying then return end
                                    
                                    -- Reaction Delay
                                    task.wait(Config.ParryDelay)
                                    
                                    ActionState.IsParrying = true
                                    
                                    -- Stop Moving
                                    local MyHum = Char:FindFirstChild("Humanoid")
                                    if MyHum then MyHum:MoveTo(Root.Position) end
                                    
                                    -- Block
                                    Block(true)
                                    task.wait(Config.BlockDuration)
                                    Block(false)
                                    
                                    ActionState.IsParrying = false
                                end)
                            end
                        end)
                    end
                end
            end
        end
    end
end

--// MOVEMENT & ANIMATION \\--
function ManageRunState(ShouldRun)
    local Char = GetCharacter()
    if not Char then return end
    local Humanoid = Char:FindFirstChild("Humanoid")
    local Animator = Humanoid and Humanoid:FindFirstChild("Animator")
    if not Humanoid then return end

    if ShouldRun and not ActionState.IsParrying then
        -- Force Speed
        if SpeedState.Humanoid ~= Humanoid or not SpeedState.IsRunning then
            if SpeedState.Connection then SpeedState.Connection:Disconnect() end
            local function EnforceSpeed()
                if Humanoid.WalkSpeed ~= Config.RunSpeed then Humanoid.WalkSpeed = Config.RunSpeed end
            end
            EnforceSpeed()
            SpeedState.Connection = Humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(EnforceSpeed)
            SpeedState.Humanoid = Humanoid
            SpeedState.IsRunning = true
        end
        -- Play Anim
        if Animator and (not CurrentAnimTrack or not CurrentAnimTrack.IsPlaying) then
            local Anim = Char:FindFirstChild("Pickaxe") and Anim_RunPickaxe or Anim_RunDefault
            pcall(function()
                CurrentAnimTrack = Animator:LoadAnimation(Anim)
                CurrentAnimTrack.Priority = Enum.AnimationPriority.Action
                CurrentAnimTrack.Looped = true
                CurrentAnimTrack:Play()
            end)
        end
    else
        -- Stop Speed
        if SpeedState.Connection then SpeedState.Connection:Disconnect() SpeedState.Connection = nil end
        SpeedState.IsRunning = false
        Humanoid.WalkSpeed = Config.WalkSpeed
        -- Stop Anim
        if CurrentAnimTrack then CurrentAnimTrack:Stop() CurrentAnimTrack = nil end
    end
end

function PathfindTo(TargetPosition, IsMob)
    local Char = GetCharacter()
    if not Char then return end
    local Root = Char:FindFirstChild("HumanoidRootPart")
    local Humanoid = Char:FindFirstChild("Humanoid")
    if not Root or not Humanoid then return end

    if Root.Anchored == false then pcall(function() Root:SetNetworkOwner(LocalPlayer) end) end

    local Path = PathfindingService:CreatePath({
        AgentRadius = 3, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 8, Costs = { Water = 20 }
    })

    local Success = pcall(function() Path:ComputeAsync(Root.Position, TargetPosition) end)

    if Success and Path.Status == Enum.PathStatus.Success then
        local Waypoints = Path:GetWaypoints()
        ManageRunState(true)

        for i, Waypoint in pairs(Waypoints) do
            if ActionState.IsParrying then 
                repeat task.wait() until not ActionState.IsParrying 
                ManageRunState(true) -- Resume running
            end
            
            if (Config.AutoFarmRocks or Config.AutoFarmMobs) == false then break end
            
            -- Check if we walked past a better target (Only if we aren't locked on)
            -- BUT user requested: "not switch rocks as I am already mining". 
            -- This function is for MOVING. Once we reach, we lock.
            -- However, if we are moving to Rock A (far) and walk past Rock B (close), we SHOULD switch.
            -- The issue was switching WHILE mining. That is handled in the Main Loop.
            
            local Nearby = GetClosestTarget(IsMob)
            if Nearby and (Root.Position - Nearby.Position).Magnitude < Config.AttackDistance then
                return -- Exit to attack/mine immediately
            end

            Humanoid:MoveTo(Waypoint.Position)
            if Waypoint.Action == Enum.PathWaypointAction.Jump then Humanoid.Jump = true end
            
            local Timeout = 0
            while (Config.AutoFarmRocks or Config.AutoFarmMobs) do
                if ActionState.IsParrying then break end -- Break wait loop to handle parry
                
                local Dist = (Root.Position - Waypoint.Position).Magnitude
                if Dist < 4 then break end
                
                Timeout = Timeout + 0.1
                if Timeout > 2 then break end
                
                -- Check for nearby targets again
                local Check = GetClosestTarget(IsMob)
                if Check and (Root.Position - Check.Position).Magnitude < Config.AttackDistance then return end
                
                task.wait(0.1)
            end
        end
    else
        ManageRunState(true)
        Humanoid:MoveTo(TargetPosition)
    end
end

--// MAIN LOGIC LOOP \\--
task.spawn(function()
    while true do
        task.wait()
        
        -- Run Parry Logic constantly
        HandleParry()
        
        if ActionState.IsParrying then
            -- Do nothing else while parrying
            task.wait(0.1)
        elseif Config.AutoFarmRocks or Config.AutoFarmMobs then
            local Char = GetCharacter()
            local IsMobFarm = Config.AutoFarmMobs
            
            if Char and Char:FindFirstChild("HumanoidRootPart") and Char:FindFirstChild("Humanoid") and Char.Humanoid.Health > 0 then
                
                -- Equip Correct Tool
                if IsMobFarm then EquipTool("Weapon") else EquipTool("Pickaxe") end
                
                local Target = GetClosestTarget(IsMobFarm)
                
                if Target then
                    ActionState.CurrentTarget = Target
                    local Root = Char.HumanoidRootPart
                    local TargetModel = Target.Parent
                    local Dist = (Root.Position - Target.Position).Magnitude
                    
                    if Dist > Config.AttackDistance then
                        -- Move
                        OrionLib:MakeNotification({Name = "Farming", Content = "Moving to " .. TargetModel.Name, Time = 1})
                        PathfindTo(Target.Position, IsMobFarm)
                    else
                        -- Attack / Mine
                        ManageRunState(false)
                        Char.Humanoid:MoveTo(Root.Position)
                        
                        -- Look at target once
                        local LookPos = Target.Position
                        Root.CFrame = CFrame.new(Root.Position, Vector3.new(LookPos.X, Root.Position.Y, LookPos.Z))
                        
                        -- Locked Loop (Prevents switching)
                        while (Config.AutoFarmRocks or Config.AutoFarmMobs) and Target and Target.Parent do
                            
                            -- Parry Check (Interrupt Attack)
                            if ActionState.IsParrying then
                                repeat task.wait() until not ActionState.IsParrying
                            end

                            if IsTargetBroken(Target.Parent) then break end
                            
                            -- Re-align if pushed
                            local CurrentLook = Root.CFrame.LookVector
                            local TargetDir = (Target.Position - Root.Position).Unit
                            if (CurrentLook.X * TargetDir.X + CurrentLook.Z * TargetDir.Z) < 0.5 then
                                Root.CFrame = CFrame.new(Root.Position, Vector3.new(Target.Position.X, Root.Position.Y, Target.Position.Z))
                            end
                            
                            -- Jump if target is high
                            if Target.Position.Y > (Root.Position.Y + 3.5) then Char.Humanoid.Jump = true end
                            
                            -- Swing
                            SwingTool(IsMobFarm and "Weapon" or "Pickaxe")
                            task.wait(Config.SwingDelay)
                            
                            -- Distance Break
                            if (Root.Position - Target.Position).Magnitude > Config.AttackDistance + 5 then break end
                            if Char.Humanoid.Health <= 0 then break end
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

OrionLib:Init()