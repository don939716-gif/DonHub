local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

--// CONFIGURATION \\--
local Config = {
    AutoFarm = false,
    SelectedRocks = {},
    AttackDistance = 7,
    SwingDelay = 0.3,
    RunSpeed = 21.69,
    WalkSpeed = 11.79
}

--// ANIMATION ASSETS \\--
local Anim_RunDefault = Instance.new("Animation")
Anim_RunDefault.AnimationId = "rbxassetid://120321298562953"

local Anim_RunPickaxe = Instance.new("Animation")
Anim_RunPickaxe.AnimationId = "rbxassetid://91424712336158"

--// STATE VARIABLES \\--
local CurrentTarget = nil -- The rock we are currently locked onto
local CurrentAnimTrack = nil
local SpeedState = { Connection = nil, Humanoid = nil, IsRunning = false }

--// UI SETUP \\--
local Window = Fluent:CreateWindow({
    Title = "The Forge | Script Hub V11",
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

-- Get Rock Names
local RockOptions = {}
local RocksAssetFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Rocks")

for _, rock in pairs(RocksAssetFolder:GetChildren()) do
    table.insert(RockOptions, rock.Name)
end
table.sort(RockOptions)

--// UI ELEMENTS \\--

local RockDropdown = Tabs.Farm:AddDropdown("RockSelection", {
    Title = "Select Rocks",
    Description = "Select multiple rocks to farm.",
    Values = RockOptions,
    Multi = true,
    Default = {},
})

RockDropdown:OnChanged(function(Value)
    -- Fluent returns a table like { ["Pebble"] = true, ["Rock"] = false }
    Config.SelectedRocks = {}
    for Name, Selected in pairs(Value) do
        if Selected then
            table.insert(Config.SelectedRocks, Name)
        end
    end
end)

local FarmToggle = Tabs.Farm:AddToggle("AutoFarm", {Title = "Enable AI Auto Farm", Default = false })

FarmToggle:OnChanged(function(Value)
    Config.AutoFarm = Value
    
    pcall(function()
        if Value then
            print("Auto Farm Started")
        else
            -- Reset everything when disabled
            CurrentTarget = nil
            ManageRunState(false)
            local Char = GetCharacter()
            if Char and Char:FindFirstChild("Humanoid") then
                Char.Humanoid:MoveTo(Char.HumanoidRootPart.Position)
            end
        end
    end)
end)

--// HELPER FUNCTIONS \\--

function GetCharacter()
    if Workspace:FindFirstChild("Living") then
        local LivingChar = Workspace.Living:FindFirstChild(LocalPlayer.Name)
        if LivingChar then return LivingChar end
    end
    return LocalPlayer.Character
end

function EquipPickaxe()
    local Char = GetCharacter()
    if not Char then return end
    if Char:FindFirstChild("Pickaxe") then return end

    local Backpack = LocalPlayer:FindFirstChild("Backpack")
    if Backpack and Backpack:FindFirstChild("Pickaxe") then
        Backpack.Pickaxe.Parent = Char
    end
end

-- Speed & Animation Manager
function ManageRunState(ShouldRun)
    local Char = GetCharacter()
    if not Char then return end
    local Humanoid = Char:FindFirstChild("Humanoid")
    local Animator = Humanoid and Humanoid:FindFirstChild("Animator")
    
    if not Humanoid then return end

    if ShouldRun then
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
            if Char:FindFirstChild("Pickaxe") then
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
                -- Check if name is in our selected list
                if table.find(Config.SelectedRocks, Item.Name) and Item:FindFirstChild("Hitbox") then
                    local Hitbox = Item.Hitbox
                    -- IMPORTANT: Don't select broken rocks
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

function MineRock()
    local args = { "Pickaxe" }
    pcall(function()
        game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services"):WaitForChild("ToolService"):WaitForChild("RF"):WaitForChild("ToolActivated"):InvokeServer(unpack(args))
    end)
end

function PathfindTo(TargetHitbox)
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

    local Success, ErrorMessage = pcall(function()
        Path:ComputeAsync(Root.Position, TargetHitbox.Position)
    end)

    if Success and Path.Status == Enum.PathStatus.Success then
        local Waypoints = Path:GetWaypoints()
        
        ManageRunState(true)

        for i, Waypoint in pairs(Waypoints) do
            if not Config.AutoFarm then break end
            if not Char or not Char.Parent then break end
            
            -- Stop if target is broken while moving
            if IsRockBroken(TargetHitbox) then return end

            -- "Walk Past" Logic:
            -- If we find a DIFFERENT rock that is very close while running, switch to it.
            -- We only do this if we are NOT already close to our target.
            local DistToTarget = (Root.Position - TargetHitbox.Position).Magnitude
            if DistToTarget > 20 then
                 local NearbyRock = GetClosestRock()
                 if NearbyRock and NearbyRock ~= TargetHitbox then
                     local DistToNearby = (Root.Position - NearbyRock.Position).Magnitude
                     if DistToNearby < Config.AttackDistance then
                         -- We found a closer rock on the way! Switch target.
                         CurrentTarget = NearbyRock
                         return 
                     end
                 end
            end

            Humanoid:MoveTo(Waypoint.Position)
            
            if Waypoint.Action == Enum.PathWaypointAction.Jump then
                Humanoid.Jump = true
            end
            
            local Timeout = 0
            while Config.AutoFarm do
                local DistToWaypoint = (Root.Position - Waypoint.Position).Magnitude
                if DistToWaypoint < 4 then break end
                
                Timeout = Timeout + 0.1
                if Timeout > 2 then break end

                -- Check if we reached the target early
                if (Root.Position - TargetHitbox.Position).Magnitude < Config.AttackDistance then
                    return
                end
                
                task.wait(0.1)
            end
        end
    else
        ManageRunState(true)
        Humanoid:MoveTo(TargetHitbox.Position)
    end
end

--// MAIN LOOP \\--

task.spawn(function()
    while true do
        task.wait() -- Main loop speed
        
        if Config.AutoFarm then
            local Char = GetCharacter()
            
            if Char and Char:FindFirstChild("HumanoidRootPart") and Char:FindFirstChild("Humanoid") and Char.Humanoid.Health > 0 then
                EquipPickaxe()
                
                -- 1. TARGET VALIDATION
                -- If we have a target, check if it's still valid
                if CurrentTarget then
                    if IsRockBroken(CurrentTarget) or not CurrentTarget.Parent then
                        CurrentTarget = nil -- Target died, clear it
                    else
                        -- Check if we somehow got too far from it (e.g. fell off cliff)
                        local Dist = (Char.HumanoidRootPart.Position - CurrentTarget.Position).Magnitude
                        if Dist > 200 then 
                            CurrentTarget = nil -- Abandon target if absurdly far
                        end
                    end
                end

                -- 2. TARGET ACQUISITION
                -- Only look for a new target if we don't have one
                if not CurrentTarget then
                    CurrentTarget = GetClosestRock()
                end
                
                -- 3. EXECUTION
                if CurrentTarget then
                    local Root = Char.HumanoidRootPart
                    local Distance = (Root.Position - CurrentTarget.Position).Magnitude
                    
                    if Distance > Config.AttackDistance then
                        -- RUNNING STATE
                        Fluent:Notify({
                            Title = "Farming",
                            Content = "Running to " .. CurrentTarget.Parent.Name,
                            Duration = 1
                        })
                        PathfindTo(CurrentTarget)
                    else
                        -- MINING STATE
                        ManageRunState(false) -- Stop running
                        Char.Humanoid:MoveTo(Root.Position) -- Stop moving
                        
                        -- Face Rock ONCE
                        local LookPos = CurrentTarget.Position
                        Root.CFrame = CFrame.new(Root.Position, Vector3.new(LookPos.X, Root.Position.Y, LookPos.Z))
                        
                        -- Mine until broken or disabled
                        -- We use a loop here to stay focused on THIS rock
                        while Config.AutoFarm and CurrentTarget and CurrentTarget.Parent do
                            if IsRockBroken(CurrentTarget) then
                                CurrentTarget = nil -- Mark as done
                                break 
                            end

                            -- Anti-Twitch: Only correct angle if pushed significantly
                            local CurrentLook = Root.CFrame.LookVector
                            local TargetDir = (CurrentTarget.Position - Root.Position).Unit
                            local DotProduct = CurrentLook.X * TargetDir.X + CurrentLook.Z * TargetDir.Z
                            if DotProduct < 0.5 then
                                Root.CFrame = CFrame.new(Root.Position, Vector3.new(CurrentTarget.Position.X, Root.Position.Y, CurrentTarget.Position.Z))
                            end

                            -- Jump if high
                            if CurrentTarget.Position.Y > (Root.Position.Y + 3.5) then
                                Char.Humanoid.Jump = true
                            end

                            MineRock()
                            task.wait(Config.SwingDelay)
                            
                            -- Safety Checks
                            if not Char or not Char.Parent or Char.Humanoid.Health <= 0 then break end
                            if (Root.Position - CurrentTarget.Position).Magnitude > Config.AttackDistance + 5 then break end
                        end
                    end
                else
                    -- No targets found
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