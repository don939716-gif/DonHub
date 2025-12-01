-- Made by Don

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
    SelectedOres = {},
    AttackDistance = 8, -- How close to get before mining
    SwingDelay = 0.5 -- How fast to swing
}

--// UI SETUP \\--

local Window = OrionLib:MakeWindow({Name = "The Forge | Script Hub", HidePremium = false, SaveConfig = true, ConfigFolder = "TheForgeHub"})

local FarmTab = Window:MakeTab({
	Name = "Auto Farm",
	Icon = "rbxassetid://4483345998",
	PremiumOnly = false
})

-- Get Ore Names from ReplicatedStorage for the Dropdown
local OreOptions = {}
local OresFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Ores")

for _, ore in pairs(OresFolder:GetChildren()) do
    table.insert(OreOptions, ore.Name)
end
table.sort(OreOptions) -- Sort alphabetically

--// UI ELEMENTS \\--

FarmTab:AddSection({
	Name = "Ore Selection"
})

FarmTab:AddDropdown({
	Name = "Select Ores to Farm",
	Default = "",
	Options = OreOptions,
	Callback = function(Value)
        -- Orion passes a table/string depending on multiselect, 
        -- but since this is a single select dropdown in standard Orion, 
        -- we might want to allow multiple. 
        -- For now, we assume the user selects one or we treat the input as the target.
        -- If you want multi-select, Orion's specific implementation varies, 
        -- so we will treat the 'Value' as the single target or add to a table.
        
        -- Logic: If Value is a string, we set it as the target. 
        -- If you want to support multiple, we would need a MultiDropdown (if supported) or a table logic.
        -- We will assume single selection for stability first.
		Config.SelectedOres = {Value} 
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
        if Value then
            print("Auto Farm Started")
        else
            -- Cancel current pathfinding if stopped
            local Char = GetCharacter()
            if Char and Char:FindFirstChild("Humanoid") then
                Char.Humanoid:MoveTo(Char.HumanoidRootPart.Position)
            end
        end
	end    
})

--// HELPER FUNCTIONS \\--

-- Function to get the real character (handling the workspace.Living folder)
function GetCharacter()
    if Workspace:FindFirstChild("Living") and Workspace.Living:FindFirstChild(LocalPlayer.Name) then
        return Workspace.Living[LocalPlayer.Name]
    end
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

-- Function to equip the pickaxe
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

-- Function to find the closest valid ore
function GetClosestOre()
    local Char = GetCharacter()
    local Root = Char and Char:FindFirstChild("HumanoidRootPart")
    if not Root then return nil end

    local ClosestOre = nil
    local ClosestDist = math.huge

    -- Look through the Rocks folder
    local RocksFolder = Workspace:WaitForChild("Rocks")
    
    -- We need to scan recursively because of the folder structure (Island1CaveStart -> SpawnLocation -> Ore)
    for _, Area in pairs(RocksFolder:GetChildren()) do
        for _, Container in pairs(Area:GetChildren()) do
            -- The ore is usually inside the Container (SpawnLocation or Model)
            -- We check children of the container to see if they match our selected list
            for _, Item in pairs(Container:GetChildren()) do
                if table.find(Config.SelectedOres, Item.Name) and Item:FindFirstChild("Hitbox") then
                    local Hitbox = Item.Hitbox
                    local Dist = (Root.Position - Hitbox.Position).Magnitude
                    
                    if Dist < ClosestDist then
                        ClosestDist = Dist
                        ClosestOre = Hitbox
                    end
                end
            end
        end
    end
    
    return ClosestOre
end

-- Function to swing the pickaxe
function MineOre()
    local args = {
        "Pickaxe"
    }
    
    -- Using pcall to prevent script crash if remote fails
    pcall(function()
        game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services"):WaitForChild("ToolService"):WaitForChild("RF"):WaitForChild("ToolActivated"):InvokeServer(unpack(args))
    end)
end

-- Pathfinding Function
function PathfindTo(TargetPosition)
    local Char = GetCharacter()
    local Root = Char and Char:FindFirstChild("HumanoidRootPart")
    local Humanoid = Char and Char:FindFirstChild("Humanoid")
    
    if not Root or not Humanoid then return end

    -- Calculate Path
    local Path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
        WaypointSpacing = 4
    })

    local Success, ErrorMessage = pcall(function()
        Path:ComputeAsync(Root.Position, TargetPosition)
    end)

    if Success and Path.Status == Enum.PathStatus.Success then
        local Waypoints = Path:GetWaypoints()
        
        for i, Waypoint in pairs(Waypoints) do
            if not Config.AutoFarm then break end
            
            -- Move to waypoint
            Humanoid:MoveTo(Waypoint.Position)
            
            -- Jump if needed
            if Waypoint.Action == Enum.PathWaypointAction.Jump then
                Humanoid.Jump = true
            end
            
            -- Wait until we reach the waypoint or get stuck
            local Reached = Humanoid.MoveToFinished:Wait()
            
            -- Check distance to actual target to see if we can stop early and mine
            if (Root.Position - TargetPosition).Magnitude < Config.AttackDistance then
                break
            end
        end
    else
        -- Fallback: Direct movement if pathfinding fails (short distance)
        Humanoid:MoveTo(TargetPosition)
    end
end

--// MAIN LOOP \\--

task.spawn(function()
    while true do
        task.wait() -- Prevent crashing
        
        if Config.AutoFarm then
            local Char = GetCharacter()
            
            if Char and Char:FindFirstChild("HumanoidRootPart") then
                EquipPickaxe()
                
                local TargetOreHitbox = GetClosestOre()
                
                if TargetOreHitbox then
                    local Root = Char.HumanoidRootPart
                    local Distance = (Root.Position - TargetOreHitbox.Position).Magnitude
                    
                    if Distance > Config.AttackDistance then
                        -- Move towards ore
                        OrionLib:MakeNotification({
                            Name = "Farming",
                            Content = "Moving to " .. TargetOreHitbox.Parent.Name,
                            Time = 1
                        })
                        PathfindTo(TargetOreHitbox.Position)
                    else
                        -- We are close enough, stop moving and mine
                        Char.Humanoid:MoveTo(Root.Position) -- Stop movement
                        
                        -- Look at ore
                        Root.CFrame = CFrame.new(Root.Position, Vector3.new(TargetOreHitbox.Position.X, Root.Position.Y, TargetOreHitbox.Position.Z))
                        
                        -- Swing until ore is gone or autofarm disabled
                        while Config.AutoFarm and TargetOreHitbox.Parent and TargetOreHitbox.Parent.Parent do
                            MineOre()
                            task.wait(Config.SwingDelay)
                            
                            -- Check distance again in case we got pushed
                            if (Root.Position - TargetOreHitbox.Position).Magnitude > Config.AttackDistance + 5 then
                                break -- Break inner loop to pathfind again
                            end
                        end
                    end
                else
                    -- No ore found
                     OrionLib:MakeNotification({
                        Name = "Warning",
                        Content = "No selected ores found nearby.",
                        Time = 2
                    })
                    task.wait(2)
                end
            end
        end
    end
end)

OrionLib:Init()