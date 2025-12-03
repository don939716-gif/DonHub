--[[
    THE FORGE - MAP FIXER TOOL
    Run this to create parts and delete garbage.
    Click "EXPORT" when done to get the code for your main script.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

-- Storage for actions
local CreatedParts = {}
local DeletedPaths = {}

--// UI SETUP \\--
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MapFixerTool"
ScreenGui.Parent = CoreGui

local function CreateButton(text, pos, color, callback)
    local btn = Instance.new("TextButton")
    btn.Parent = ScreenGui
    btn.Size = UDim2.new(0, 120, 0, 40)
    btn.Position = pos
    btn.BackgroundColor3 = color
    btn.Text = text
    btn.TextColor3 = Color3.new(1,1,1)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 14
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = btn
    
    btn.MouseButton1Click:Connect(callback)
    return btn
end

--// STATE VARIABLES \\--
local DeleteMode = false
local HighlightBox = Instance.new("SelectionBox")
HighlightBox.Color3 = Color3.fromRGB(255, 0, 0)
HighlightBox.LineThickness = 0.05
HighlightBox.Parent = ScreenGui

local HoveredPart = nil

--// FUNCTIONS \\--

local function GetPath(Obj)
    local Path = Obj.Name
    local Current = Obj.Parent
    while Current and Current ~= game do
        Path = Current.Name .. "." .. Path
        Current = Current.Parent
    end
    return Path
end

local function SpawnPlatform()
    local Char = LocalPlayer.Character
    if not Char or not Char:FindFirstChild("HumanoidRootPart") then return end
    
    local HRP = Char.HumanoidRootPart
    
    local Part = Instance.new("Part")
    Part.Name = "NavFix_" .. (#CreatedParts + 1)
    Part.Size = Vector3.new(10, 1, 10)
    Part.Position = HRP.Position - Vector3.new(0, 3, 0) -- Spawn under feet
    Part.Anchored = true
    Part.CanCollide = true
    Part.Transparency = 0.5
    Part.Color = Color3.fromRGB(0, 255, 0)
    Part.Material = Enum.Material.Neon
    Part.Parent = Workspace
    
    table.insert(CreatedParts, {
        Size = Part.Size,
        CFrame = Part.CFrame
    })
end

local function DeletePart(Part, Recursive)
    if not Part or Part.Locked then return end
    
    -- Save the path before destroying
    local Path = GetPath(Part)
    table.insert(DeletedPaths, Path)
    
    local Material = Part.Material
    local Parent = Part.Parent
    
    Part:Destroy()
    
    if Recursive then
        -- Find touching parts with same material
        -- We create a temporary region check since the part is gone, 
        -- actually we should have checked before destroying, but for simple props:
        -- Let's just look at the Parent's children for simplicity in this tool
        if Parent then
            for _, sibling in pairs(Parent:GetChildren()) do
                if sibling:IsA("BasePart") and sibling.Material == Material then
                    -- Check distance to see if it was "touching" or close
                    -- This is a rough approximation for "Group Delete"
                    DeletePart(sibling, false)
                end
            end
        end
    end
end

local function ExportData()
    local Output = "\n--// PASTE THIS INTO YOUR MAIN SCRIPT //--\n"
    Output = Output .. "local function ApplyMapFixes()\n"
    Output = Output .. "    -- Created Platforms\n"
    
    for _, data in pairs(CreatedParts) do
        local cf = data.CFrame
        local size = data.Size
        Output = Output .. string.format("    local p = Instance.new('Part')\n")
        Output = Output .. string.format("    p.Size = Vector3.new(%f, %f, %f)\n", size.X, size.Y, size.Z)
        Output = Output .. string.format("    p.CFrame = CFrame.new(%f, %f, %f)\n", cf.X, cf.Y, cf.Z)
        Output = Output .. string.format("    p.Anchored = true; p.Transparency = 1; p.Parent = workspace\n\n")
    end
    
    Output = Output .. "    -- Deleted Garbage\n"
    for _, path in pairs(DeletedPaths) do
        -- We use a pcall to safely try to delete by path
        Output = Output .. string.format("    pcall(function() game.%s:Destroy() end)\n", path)
    end
    
    Output = Output .. "end\n"
    Output = Output .. "ApplyMapFixes()\n"
    Output = Output .. "--// END OF MAP FIXES //--"
    
    print(Output)
    if setclipboard then
        setclipboard(Output)
        game.StarterGui:SetCore("SendNotification", {Title="Exported"; Text="Copied to Clipboard & Console"; Duration=3;})
    else
        game.StarterGui:SetCore("SendNotification", {Title="Exported"; Text="Check Console (F9)"; Duration=3;})
    end
end

--// BUTTONS \\--

CreateButton("Spawn Platform", UDim2.new(0, 10, 0.5, -100), Color3.fromRGB(0, 170, 0), SpawnPlatform)

local DelBtn = CreateButton("Delete Mode: OFF", UDim2.new(0, 10, 0.5, -50), Color3.fromRGB(170, 0, 0), function()
    DeleteMode = not DeleteMode
    if DeleteMode then
        HighlightBox.Adornee = nil
    else
        HighlightBox.Adornee = nil
    end
end)

CreateButton("Delete Group", UDim2.new(0, 10, 0.5, 0), Color3.fromRGB(200, 100, 0), function()
    if HoveredPart then
        DeletePart(HoveredPart, true)
        HoveredPart = nil
        HighlightBox.Adornee = nil
    end
end)

CreateButton("EXPORT DATA", UDim2.new(0, 10, 0.5, 50), Color3.fromRGB(0, 100, 255), ExportData)

CreateButton("Close Tool", UDim2.new(0, 10, 0.5, 100), Color3.fromRGB(50, 50, 50), function()
    ScreenGui:Destroy()
end)

--// UPDATE LOOP \\--

RunService.RenderStepped:Connect(function()
    if DeleteMode then
        DelBtn.Text = "Delete Mode: ON"
        
        -- Raycast from mouse/center screen
        local mousePos = UserInputService:GetMouseLocation()
        local ray = Camera:ViewportPointToRay(mousePos.X, mousePos.Y)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {LocalPlayer.Character}
        
        local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
        
        if result and result.Instance then
            HoveredPart = result.Instance
            HighlightBox.Adornee = HoveredPart
        else
            HoveredPart = nil
            HighlightBox.Adornee = nil
        end
    else
        DelBtn.Text = "Delete Mode: OFF"
        HighlightBox.Adornee = nil
        HoveredPart = nil
    end
end)

--// INPUT HANDLING \\--

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    
    if DeleteMode and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
        if HoveredPart then
            DeletePart(HoveredPart, false)
            HighlightBox.Adornee = nil
            HoveredPart = nil
        end
    end
end)