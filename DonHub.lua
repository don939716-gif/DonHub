--[[
    THE FORGE - MAP EDITOR TOOL
    1. Run this script.
    2. Use "Create Part" to smooth out terrain (make ramps/bridges).
    3. Use "Delete Part" to remove annoying walls/props.
    4. Click "Export Data" to copy the code to clipboard.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

--// DATA STORAGE \\--
local CreatedParts = {} -- Stores info about parts we made
local DeletedPaths = {} -- Stores FullPath of parts we deleted

--// STATE \\--
local ToolMode = "None" -- "Create", "Delete"
local CreateStep = 0
local Points = {}
local TempPart = nil
local SelectionBox = Instance.new("SelectionBox")
SelectionBox.Color3 = Color3.fromRGB(255, 0, 0)
SelectionBox.LineThickness = 0.05
SelectionBox.Parent = CoreGui

local HoveredPart = nil
local MultiSelectParts = {}

--// UI SETUP \\--
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MapEditorTool"
ScreenGui.Parent = CoreGui

local function CreateBtn(Text, Pos, Color, Callback)
    local Btn = Instance.new("TextButton")
    Btn.Parent = ScreenGui
    Btn.Size = UDim2.new(0, 100, 0, 40)
    Btn.Position = Pos
    Btn.BackgroundColor3 = Color
    Btn.Text = Text
    Btn.TextColor3 = Color3.new(1,1,1)
    Btn.Font = Enum.Font.GothamBold
    Btn.TextSize = 14
    
    local UICorner = Instance.new("UICorner")
    UICorner.Parent = Btn
    
    Btn.MouseButton1Click:Connect(Callback)
    return Btn
end

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Parent = ScreenGui
StatusLabel.Size = UDim2.new(0, 300, 0, 30)
StatusLabel.Position = UDim2.new(0.5, -150, 0, 10)
StatusLabel.BackgroundTransparency = 0.5
StatusLabel.BackgroundColor3 = Color3.new(0,0,0)
StatusLabel.TextColor3 = Color3.new(1,1,1)
StatusLabel.Text = "Mode: None"

local BtnCreate = CreateBtn("Create Part", UDim2.new(0, 10, 0.5, -60), Color3.fromRGB(0, 170, 0), function()
    ToolMode = "Create"
    CreateStep = 1
    Points = {}
    StatusLabel.Text = "Mode: Create (Click Point 1)"
    if TempPart then TempPart:Destroy() TempPart = nil end
    SelectionBox.Adornee = nil
end)

local BtnDelete = CreateBtn("Delete Part", UDim2.new(0, 10, 0.5, -10), Color3.fromRGB(170, 0, 0), function()
    ToolMode = "Delete"
    StatusLabel.Text = "Mode: Delete (Hover to select)"
    if TempPart then TempPart:Destroy() TempPart = nil end
end)

local BtnExport = CreateBtn("EXPORT", UDim2.new(0, 10, 0.5, 40), Color3.fromRGB(0, 100, 255), function()
    local Output = "--// MAP FIXES \\--\n\n"
    
    -- Generate Deletion Code
    Output = Output .. "-- Deleted Parts\n"
    for _, path in ipairs(DeletedPaths) do
        Output = Output .. "pcall(function() " .. path .. ":Destroy() end)\n"
    end
    
    -- Generate Creation Code
    Output = Output .. "\n-- Created Parts\n"
    for _, data in ipairs(CreatedParts) do
        Output = Output .. "local p = Instance.new('Part')\n"
        Output = Output .. "p.Anchored = true\n"
        Output = Output .. "p.CanCollide = true\n"
        Output = Output .. "p.Transparency = 0.5\n"
        Output = Output .. "p.Color = Color3.fromRGB(0, 255, 0)\n"
        Output = Output .. string.format("p.Size = Vector3.new(%.2f, %.2f, %.2f)\n", data.Size.X, data.Size.Y, data.Size.Z)
        Output = Output .. string.format("p.CFrame = CFrame.new(%.2f, %.2f, %.2f)\n", data.CFrame.X, data.CFrame.Y, data.CFrame.Z)
        Output = Output .. "p.Parent = workspace\n\n"
    end
    
    if setclipboard then
        setclipboard(Output)
        StatusLabel.Text = "Copied to Clipboard!"
    else
        print(Output)
        StatusLabel.Text = "Copied to Console (F9)"
    end
    task.wait(2)
    StatusLabel.Text = "Mode: " .. ToolMode
end)

--// LOGIC \\--

local function GetMouseHit()
    -- Mobile friendly raycast
    local mouseLocation = UserInputService:GetMouseLocation()
    local ray = workspace.CurrentCamera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
    local result = workspace:Raycast(ray.Origin, ray.Direction * 1000)
    if result then
        return result.Position, result.Instance
    end
    return Mouse.Hit.Position, Mouse.Target
end

-- Update Loop
RunService.RenderStepped:Connect(function()
    if ToolMode == "Delete" then
        local _, target = GetMouseHit()
        
        -- Handle Multi-Select (Shift)
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and target then
            MultiSelectParts = {}
            SelectionBox.Adornee = nil -- We will use a folder or custom highlighting later, but for now simple
            
            -- Simple logic: Get touching parts of same material
            -- Note: GetTouchingParts requires CanCollide=true usually, or a touch interest. 
            -- We will do a simple radius check for performance or just highlight the single target for safety.
            -- Implementing robust multi-select via script is heavy, let's stick to single highlight + visual cue
            
            HoveredPart = target
            SelectionBox.Adornee = target
            StatusLabel.Text = "Shift Held: Bulk Delete Ready (Click to confirm)"
        else
            HoveredPart = target
            SelectionBox.Adornee = target
            StatusLabel.Text = "Hovering: " .. (target and target.Name or "None")
        end
        
    elseif ToolMode == "Create" then
        SelectionBox.Adornee = nil
        if CreateStep == 2 and Points[1] then
            -- Visualizing the base
            local hitPos, _ = GetMouseHit()
            local p1 = Points[1]
            local p2 = hitPos
            
            local center = (p1 + p2) / 2
            local size = Vector3.new(math.abs(p1.X - p2.X), 0.2, math.abs(p1.Z - p2.Z))
            
            if not TempPart then
                TempPart = Instance.new("Part")
                TempPart.Anchored = true
                TempPart.CanCollide = false
                TempPart.Transparency = 0.5
                TempPart.Color = Color3.fromRGB(0, 255, 0)
                TempPart.Parent = workspace
            end
            TempPart.Size = size
            TempPart.CFrame = CFrame.new(center)
            
        elseif CreateStep == 3 and Points[1] and Points[2] then
            -- Visualizing the height
            local hitPos, _ = GetMouseHit()
            local p1 = Points[1]
            local p2 = Points[2]
            local height = math.abs(hitPos.Y - p1.Y)
            
            local centerBase = (p1 + p2) / 2
            local center = Vector3.new(centerBase.X, p1.Y + (height/2), centerBase.Z)
            local size = Vector3.new(math.abs(p1.X - p2.X), height, math.abs(p1.Z - p2.Z))
            
            if TempPart then
                TempPart.Size = size
                TempPart.CFrame = CFrame.new(center)
            end
        end
    end
end)

-- Input Handler
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        local hitPos, target = GetMouseHit()
        
        if ToolMode == "Create" then
            if CreateStep == 1 then
                Points[1] = hitPos
                CreateStep = 2
                StatusLabel.Text = "Click Point 2 (Diagonal Corner)"
            elseif CreateStep == 2 then
                Points[2] = hitPos
                CreateStep = 3
                StatusLabel.Text = "Click Point 3 (Height)"
            elseif CreateStep == 3 then
                -- Finalize
                if TempPart then
                    local FinalPart = TempPart:Clone()
                    FinalPart.Parent = workspace
                    FinalPart.CanCollide = true
                    FinalPart.Transparency = 0.5
                    
                    table.insert(CreatedParts, {
                        Size = FinalPart.Size,
                        CFrame = FinalPart.CFrame
                    })
                    
                    TempPart:Destroy()
                    TempPart = nil
                end
                CreateStep = 1
                Points = {}
                StatusLabel.Text = "Part Created! Click Point 1 for next."
            end
            
        elseif ToolMode == "Delete" then
            if target and target ~= workspace.Terrain then
                
                local ToDelete = {target}
                
                -- Shift Logic (Select touching with same material)
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
                    local params = OverlapParams.new()
                    params.FilterDescendantsInstances = {target}
                    params.FilterType = Enum.RaycastFilterType.Exclude
                    
                    local parts = workspace:GetPartBoundsInBox(target.CFrame, target.Size * 1.1, params)
                    for _, p in pairs(parts) do
                        if p:IsA("BasePart") and p.Material == target.Material then
                            table.insert(ToDelete, p)
                        end
                    end
                end
                
                for _, part in pairs(ToDelete) do
                    -- Generate path string
                    local path = "workspace"
                    local hierarchy = {}
                    local current = part
                    while current and current ~= game do
                        table.insert(hierarchy, 1, current.Name)
                        current = current.Parent
                    end
                    -- Remove "Workspace" from start if present (since we added it manually)
                    if hierarchy[1] == "Workspace" then table.remove(hierarchy, 1) end
                    
                    for _, name in ipairs(hierarchy) do
                        if name:match("^%d") or name:match("%W") then
                            path = path .. "[\"" .. name .. "\"]"
                        else
                            path = path .. "." .. name
                        end
                    end
                    
                    table.insert(DeletedPaths, path)
                    part:Destroy()
                end
                
                StatusLabel.Text = "Deleted " .. #ToDelete .. " parts."
            end
        end
    end
end)