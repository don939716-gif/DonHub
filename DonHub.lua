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
    SelectedRocks = {}, -- Renamed to Rocks
    AttackDistance = 8,
    SwingDelay = 0.5
}

--// UI SETUP \\--

local Window = OrionLib:MakeWindow({Name = "The Forge | Script Hub", HidePremium = false, SaveConfig = true, ConfigFolder = "TheForgeHub_V2"})

local FarmTab = Window:MakeTab({
	Name = "Auto Farm",
	Icon = "rbxassetid://4483345998",
	PremiumOnly = false
})

-- Get Rock Names from ReplicatedStorage for the Dropdown
local RockOptions = {}
-- Changed from Assets.Ores to Assets.Rocks as requested
local RocksAssetFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Rocks")

for _, rock in pairs(RocksAssetFolder:GetChildren()) do
    table.insert(RockOptions, rock.Name)
end
table.sort(RockOptions) -- Sort alphabetically

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
        
        -- Safety check to prevent UI freezing if character is missing
        pcall(function()
            if Value then
                print("Auto Farm Started")
            else
                -- Cancel movement immediately when disabled
                local Char = nil
                if Workspace:FindFirstChild("Living") and Workspace.Living:FindFirstChild(LocalPlayer.Name) then
                    Char = Workspace.Living[LocalPlayer.Name]
                elseif LocalPlayer.Character then
                    Char = LocalPlayer.Character
                end

                if Char and Char:FindFirstChild("Humanoid") and Char:FindFirstChild("HumanoidRootPart") then
                    Char.Humanoid:MoveTo(Char.HumanoidRootPart.Position)
                end
            end
        end)
	end    
})

--// HELPER FUNCTIONS \\--

-- Robust function to get the real character
function GetCharacter()
    -- The Forge puts characters in workspace.Living
    if Workspace:FindFirstChild("Living") then
        local LivingChar = Workspace.Living:FindFirstChild(LocalPlayer.Name)
        if LivingChar then return LivingChar end
    end
    -- Fallback to standard character
    return LocalPlayer.Character
end

function EquipPickaxe()
    local Char = GetCharacter()
    if not Char then return end
    
    -- Check if already equipped
    if Char:FindFirstChild("Pickaxe") then return end

    -- Check Backpack
    local Backpack = LocalPlayer:FindFirstChild("Backpack")
    if Backpack and Backpack:FindFirstChild("Pickaxe") then
        Backpack.Pickaxe.Parent = Char
    end
end

function GetClosestRock()
    local Char = GetCharacter()
    local Root = Char and Char:FindFirstChild("HumanoidRootPart")
    if not Root then return nil end

    local ClosestRock = nil
    local ClosestDist = math.huge

    local RocksFolder = Workspace:FindFirstChild("Rocks")
    if not RocksFolder then return nil end
    
    -- Recursively scan the Rocks folder
    -- Structure: Rocks -> Area -> SpawnLocation -> RockName -> Hitbox
    for _, Area in pairs(RocksFolder:GetChildren()) do
        for _, Container in pairs(Area:GetChildren()) do
            -- Check children of the container (SpawnLocation)
            for _, Item in pairs(Container:GetChildren()) do
                -- Check if the Item name matches our selection (e.g., "Pebble")
                if table.find(Config.SelectedRocks, Item.Name) and Item:FindFirstChild("Hitbox") then
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

    local Path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
        WaypointSpacing = 4,
        Costs = {
            Water = 20
        }
    })

    local Success, ErrorMessage = pcall(function()
        Path:ComputeAsync(Root.Position, TargetPosition)
    end)

    if Success and Path.Status == Enum.PathStatus.Success then
        local Waypoints = Path:GetWaypoints()
        
        for i, Waypoint in pairs(Waypoints) do
            -- Stop if toggle is turned off
            if not Config.AutoFarm then break end
            
            -- Re-check character existence in case of death during path
            if not Char or not Char.Parent then break end

            Humanoid:MoveTo(Waypoint.Position)
            
            if Waypoint.Action == Enum.PathWaypointAction.Jump then
                Humanoid.Jump = true
            end
            
            -- MoveToFinished with a timeout to prevent getting stuck
            local MoveSuccess = Humanoid.MoveToFinished:Wait()
            
            -- Check distance to actual target to see if we can stop early
            if (Root.Position - TargetPosition).Magnitude < Config.AttackDistance then
                break
            end
        end
    else
        -- Fallback: Direct movement
        Humanoid:MoveTo(TargetPosition)
    end
end

--// MAIN LOOP \\--

task.spawn(function()
    while true do
        task.wait() -- Always wait to prevent crash
        
        if Config.AutoFarm then
            local Char = GetCharacter()
            
            if Char and Char:FindFirstChild("HumanoidRootPart") and Char:FindFirstChild("Humanoid") and Char.Humanoid.Health > 0 then
                EquipPickaxe()
                
                local TargetHitbox = GetClosestRock()
                
                if TargetHitbox then
                    local Root = Char.HumanoidRootPart
                    local Distance = (Root.Position - TargetHitbox.Position).Magnitude
                    
                    if Distance > Config.AttackDistance then
                        -- Move towards rock
                        OrionLib:MakeNotification({
                            Name = "Farming",
                            Content = "Moving to " .. TargetHitbox.Parent.Name,
                            Time = 1
                        })
                        PathfindTo(TargetHitbox.Position)
                    else
                        -- Close enough to mine
                        Char.Humanoid:MoveTo(Root.Position) -- Stop moving
                        
                        -- Face the rock
                        Root.CFrame = CFrame.new(Root.Position, Vector3.new(TargetHitbox.Position.X, Root.Position.Y, TargetHitbox.Position.Z))
                        
                        -- Mine loop
                        local StuckCounter = 0
                        while Config.AutoFarm and TargetHitbox.Parent and TargetHitbox.Parent.Parent do
                            MineRock()
                            task.wait(Config.SwingDelay)
                            
                            -- Verify we are still close
                            if (Root.Position - TargetHitbox.Position).Magnitude > Config.AttackDistance + 5 then
                                break 
                            end
                            
                            -- Verify character is still alive
                            if not Char or not Char.Parent or Char.Humanoid.Health <= 0 then
                                break
                            end
                        end
                    end
                else
                    -- No rocks found
                    task.wait(1)
                end
            else
                -- Character not found or dead, wait for respawn
                task.wait(1)
            end
        end
    end
end)

OrionLib:Init()