local OrionLib = loadstring(game:HttpGet(('https://raw.githubusercontent.com/jensonhirst/Orion/main/source')))()
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- Configuration Variables
local Config = {
    AutoFarm = false,
    SelectedRocks = {},
    AttackDistance = 7, 
    SwingDelay = 0.3
}

-- Animation Variables
local WalkAnimID = "rbxassetid://180426354"
local CurrentWalkTrack = nil

--// UI SETUP \\--

local Window = OrionLib:MakeWindow({Name = "The Forge | Script Hub V4", HidePremium = false, SaveConfig = true, ConfigFolder = "TheForgeHub_V4"})

local FarmTab = Window:MakeTab({
	Name = "Auto Farm",
	Icon = "rbxassetid://4483345998",
	PremiumOnly = false
})

-- Get Rock Names
local RockOptions = {}
local RocksAssetFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Rocks")

for _, rock in pairs(RocksAssetFolder:GetChildren()) do
    table.insert(RockOptions, rock.Name)
end
table.sort(RockOptions)

--// UI ELEMENTS \\--

FarmTab:AddSection({
	Name = "Rock Selection"
})

FarmTab:AddDropdown({
	Name = "Select Rocks to Farm",
	Default = "",
	Options = RockOptions,
	Callback = function(Value)
		Config.SelectedRocks = {Value} 
	end    
})

FarmTab:AddSection({
	Name = "Automation"
})

FarmTab:AddToggle({
	Name = "Enable AI Auto Farm",
	Default = false,
	Callback = function(Value)
		Config.AutoFarm = Value
        
        pcall(function()
            if Value then
                print("Auto Farm Started")
            else
                -- Stop movement and animation
                ManageWalkAnim(false)
                local Char = GetCharacter()
                if Char and Char:FindFirstChild("Humanoid") then
                    Char.Humanoid:MoveTo(Char.HumanoidRootPart.Position)
                end
            end
        end)
	end    
})

--// HELPER FUNCTIONS \\--

function GetCharacter()
    if Workspace:FindFirstChild("Living") then
        local LivingChar = Workspace.Living:FindFirstChild(LocalPlayer.Name)
        if LivingChar then return LivingChar end
    end
    return LocalPlayer.Character
end

-- New Function to Handle Walking Animation
function ManageWalkAnim(ShouldPlay)
    local Char = GetCharacter()
    if not Char then return end
    local Humanoid = Char:FindFirstChild("Humanoid")
    local Animator = Humanoid and Humanoid:FindFirstChild("Animator")
    
    if not Animator then return end

    if ShouldPlay then
        -- Check if track exists and is valid for current character
        if not CurrentWalkTrack or CurrentWalkTrack.Animation.AnimationId ~= WalkAnimID or CurrentWalkTrack.Parent ~= Animator then
            local Anim = Instance.new("Animation")
            Anim.AnimationId = WalkAnimID
            CurrentWalkTrack = Animator:LoadAnimation(Anim)
            CurrentWalkTrack.Looped = true
            CurrentWalkTrack.Priority = Enum.AnimationPriority.Movement
        end
        
        if not CurrentWalkTrack.IsPlaying then
            CurrentWalkTrack:Play()
        end
    else
        -- Stop animation
        if CurrentWalkTrack and CurrentWalkTrack.IsPlaying then
            CurrentWalkTrack:Stop()
        end
    end
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

function IsRockBroken(RockModel)
    if not RockModel or not RockModel.Parent then return true end
    
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
                    if not IsRockBroken(Item) then
                        local Hitbox = Item.Hitbox
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
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
        WaypointSpacing = 4,
        Costs = { Water = 20 }
    })

    local Success, ErrorMessage = pcall(function()
        Path:ComputeAsync(Root.Position, TargetPosition)
    end)

    if Success and Path.Status == Enum.PathStatus.Success then
        local Waypoints = Path:GetWaypoints()
        
        for i, Waypoint in pairs(Waypoints) do
            if not Config.AutoFarm then break end
            if not Char or not Char.Parent then break end

            -- Start Walking Animation
            ManageWalkAnim(true)

            Humanoid:MoveTo(Waypoint.Position)
            
            if Waypoint.Action == Enum.PathWaypointAction.Jump then
                Humanoid.Jump = true
            end
            
            local Reached = Humanoid.MoveToFinished:Wait()
            
            if (Root.Position - TargetPosition).Magnitude < Config.AttackDistance then
                break
            end
        end
    else
        -- Fallback direct move
        ManageWalkAnim(true)
        Humanoid:MoveTo(TargetPosition)
    end
end

--// MAIN LOOP \\--

task.spawn(function()
    while true do
        task.wait()
        
        if Config.AutoFarm then
            local Char = GetCharacter()
            
            if Char and Char:FindFirstChild("HumanoidRootPart") and Char:FindFirstChild("Humanoid") and Char.Humanoid.Health > 0 then
                EquipPickaxe()
                
                local TargetHitbox = GetClosestRock()
                
                if TargetHitbox then
                    local Root = Char.HumanoidRootPart
                    local RockModel = TargetHitbox.Parent
                    local Distance = (Root.Position - TargetHitbox.Position).Magnitude
                    
                    if Distance > Config.AttackDistance then
                        -- Move towards rock
                        OrionLib:MakeNotification({
                            Name = "Farming",
                            Content = "Moving to " .. RockModel.Name,
                            Time = 1
                        })
                        PathfindTo(TargetHitbox.Position)
                    else
                        -- Close enough to mine
                        ManageWalkAnim(false) -- Stop walking animation
                        Char.Humanoid:MoveTo(Root.Position) 
                        
                        while Config.AutoFarm and RockModel and RockModel.Parent do
                            
                            if IsRockBroken(RockModel) then
                                break 
                            end

                            local LookPos = TargetHitbox.Position
                            Root.CFrame = CFrame.new(Root.Position, LookPos)
                            
                            if LookPos.Y > (Root.Position.Y + 3.5) then
                                Char.Humanoid.Jump = true
                            end

                            MineRock()
                            task.wait(Config.SwingDelay)
                            
                            if (Root.Position - TargetHitbox.Position).Magnitude > Config.AttackDistance + 4 then
                                break 
                            end
                            
                            if not Char or not Char.Parent or Char.Humanoid.Health <= 0 then
                                break
                            end
                        end
                    end
                else
                    -- No rocks found, stop animation
                    ManageWalkAnim(false)
                    task.wait(0.5)
                end
            else
                task.wait(1)
            end
        end
    end
end)

OrionLib:Init()