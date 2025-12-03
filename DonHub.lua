--[[
    THE FORGE - MAP EDITOR TOOL V3
    1. Create Mode (4 Points):
       - Click 1: Start Corner
       - Click 2: End Corner (Sets Length & Axis)
       - Click 3: Width (Expands ONLY towards mouse)
       - Click 4: Height (Expands ONLY towards mouse)
    2. Delete Mode:
       - Hold SHIFT for Radius Select (Matches Material + Color, ignores Size >= 50).
    3. Toggle: Click button again to cancel.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

--// DATA STORAGE \\--
local CreatedParts = {} 
local DeletedPaths = {} 

--// STATE \\--
local ToolMode = "None"
local CreateStep = 0
local Points = {}
local TempPart = nil
local SelectionFolder = Instance.new("Folder")
SelectionFolder.Name = "SelectionHighlights"
SelectionFolder.Parent = CoreGui

local HoveredPart = nil
local GroupParts = {} 

--// UI SETUP \\--
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MapEditorToolV3"
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
StatusLabel.Size = UDim2.new(0, 400, 0, 30)
StatusLabel.Position = UDim2.new(0.5, -200, 0, 10)
StatusLabel.BackgroundTransparency = 0.5
StatusLabel.BackgroundColor3 = Color3.new(0,0,0)
StatusLabel.TextColor3 = Color3.new(1,1,1)
StatusLabel.Text = "Mode: None"

--// RESET FUNCTION \\--
local function ResetTool()
    ToolMode = "None"
    CreateStep = 0
    Points = {}
    if TempPart then TempPart:Destroy() TempPart = nil end
    SelectionFolder:ClearAllChildren()
    GroupParts = {}
    StatusLabel.Text = "Mode: None"
end

local BtnCreate = CreateBtn("Create Ramp", UDim2.new(0, 10, 0.5, -60), Color3.fromRGB(0, 170, 0), function()
    if ToolMode == "Create" then
        ResetTool() -- Toggle Off
    else
        ResetTool()
        ToolMode = "Create"
        CreateStep = 1
        StatusLabel.Text = "Step 1: Click Start Corner"
    end
end)

local BtnDelete = CreateBtn("Delete Part", UDim2.new(0, 10, 0.5, -10), Color3.fromRGB(170, 0, 0), function()
    if ToolMode == "Delete" then
        ResetTool() -- Toggle Off
    else
        ResetTool()
        ToolMode = "Delete"
        StatusLabel.Text = "Mode: Delete (Hold SHIFT for Radius Group)"
    end
end)

local BtnExport = CreateBtn("EXPORT", UDim2.new(0, 10, 0.5, 40), Color3.fromRGB(0, 100, 255), function()
    local Output = "--// MAP FIXES \\--\n\n"
    
    Output = Output .. "-- Deleted Parts\n"
    for _, path in ipairs(DeletedPaths) do
        Output = Output .. "pcall(function() " .. path .. ":Destroy() end)\n"
    end
    
    Output = Output .. "\n-- Created Parts\n"
    for _, data in ipairs(CreatedParts) do
        Output = Output .. "local p = Instance.new('Part')\n"
        Output = Output .. "p.Anchored = true\n"
        Output = Output .. "p.CanCollide = true\n"
        Output = Output .. "p.Transparency = 0.5\n"
        Output = Output .. "p.Color = Color3.fromRGB(0, 255, 0)\n"
        Output = Output .. "p.Material = Enum.Material.SmoothPlastic\n"
        Output = Output .. string.format("p.Size = Vector3.new(%.4f, %.4f, %.4f)\n", data.Size.X, data.Size.Y, data.Size.Z)
        Output = Output .. string.format("p.CFrame = CFrame.new(%.4f, %.4f, %.4f) * CFrame.Angles(%.4f, %.4f, %.4f)\n", 
            data.Pos.X, data.Pos.Y, data.Pos.Z, data.Rot.X, data.Rot.Y, data.Rot.Z)
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

--// HELPER FUNCTIONS \\--

local function GetMouseHit()
    local mouseLocation = UserInputService:GetMouseLocation()
    local ray = workspace.CurrentCamera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
    local result = workspace:Raycast(ray.Origin, ray.Direction * 2000)
    if result then
        return result.Position, result.Instance
    end
    return Mouse.Hit.Position, Mouse.Target
end

local function HighlightPart(TargetPart)
    local Box = Instance.new("SelectionBox")
    Box.Color3 = Color3.fromRGB(255, 0, 0)
    Box.LineThickness = 0.05
    Box.Adornee = TargetPart
    Box.Parent = SelectionFolder
end

local function IsSafeToDelete(Part)
    if not Part:IsA("BasePart") then return false end
    if Part == workspace.Terrain then return false end
    -- Size Safety Check (Ignore giant parts)
    if Part.Size.X >= 50 or Part.Size.Y >= 50 or Part.Size.Z >= 50 then return false end
    return true
end

-- Radius Flood Fill for Group Selection
local function FindConnectedParts(StartPart)
    if not IsSafeToDelete(StartPart) then return {} end

    local Found = {[StartPart] = true}
    local Queue = {StartPart}
    local Material = StartPart.Material
    local Color = StartPart.Color -- Match Color too
    
    local MaxSearch = 300 
    local Count = 0
    local SearchRadius = 10 -- 10 Stud Radius
    
    while #Queue > 0 and Count < MaxSearch do
        local Current = table.remove(Queue, 1)
        Count = Count + 1
        
        local Params = OverlapParams.new()
        Params.FilterDescendantsInstances = {Current} -- Don't check self
        Params.FilterType = Enum.RaycastFilterType.Exclude
        
        -- Sphere overlap check
        local PartsInRadius = workspace:GetPartBoundsInRadius(Current.Position, SearchRadius, Params)
        
        for _, p in ipairs(PartsInRadius) do
            if IsSafeToDelete(p) and not Found[p] then
                -- Check Material AND Color match
                if p.Material == Material and p.Color == Color then
                    Found[p] = true
                    table.insert(Queue, p)
                end
            end
        end
    end
    
    local Result = {}
    for p, _ in pairs(Found) do table.insert(Result, p) end
    return Result
end

--// RENDER LOOP \\--
RunService.RenderStepped:Connect(function()
    if ToolMode == "Delete" then
        SelectionFolder:ClearAllChildren()
        local _, target = GetMouseHit()
        
        if target and IsSafeToDelete(target) then
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
                -- Group Select
                GroupParts = FindConnectedParts(target)
                for _, p in ipairs(GroupParts) do
                    HighlightPart(p)
                end
                StatusLabel.Text = "Shift Held: " .. #GroupParts .. " parts (Radius 10, Mat+Color Match)"
            else
                -- Single Select
                GroupParts = {target}
                HighlightPart(target)
                StatusLabel.Text = "Hovering: " .. target.Name
            end
        else
            GroupParts = {}
        end
        
    elseif ToolMode == "Create" then
        local hitPos, _ = GetMouseHit()
        
        if not TempPart then
            TempPart = Instance.new("Part")
            TempPart.Anchored = true
            TempPart.CanCollide = false
            TempPart.Transparency = 0.5
            TempPart.Color = Color3.fromRGB(0, 255, 0)
            TempPart.Parent = workspace
        end

        if CreateStep == 2 and Points[1] then
            -- Step 2: Define Length & Incline (Line between P1 and P2)
            local P1 = Points[1]
            local P2 = hitPos
            local Mid = (P1 + P2) / 2
            local Dist = (P1 - P2).Magnitude
            
            TempPart.Size = Vector3.new(0.2, 0.2, Dist)
            TempPart.CFrame = CFrame.lookAt(Mid, P2)
            
        elseif CreateStep == 3 and Points[1] and Points[2] then
            -- Step 3: Directional Width Expansion
            local P1 = Points[1]
            local P2 = Points[2]
            local MidLine = (P1 + P2) / 2
            local BaseCF = CFrame.lookAt(MidLine, P2)
            
            -- Convert mouse hit to object space relative to the line
            local RelPos = BaseCF:PointToObjectSpace(hitPos)
            local Width = math.abs(RelPos.X)
            local Direction = math.sign(RelPos.X) -- -1 is left, 1 is right
            
            -- Shift center so edge stays at line
            local OffsetX = (Width / 2) * Direction
            local NewCenter = BaseCF * CFrame.new(OffsetX, 0, 0)
            
            TempPart.Size = Vector3.new(Width, 0.2, (P1-P2).Magnitude)
            TempPart.CFrame = NewCenter
            
        elseif CreateStep == 4 and Points[1] and Points[2] and Points[3] then
            -- Step 4: Directional Height Expansion
            local P1 = Points[1]
            local P2 = Points[2]
            local WidthData = Points[3] -- Contains {Width, CenterCF}
            
            local BaseCF = WidthData.CenterCF
            local RelPos = BaseCF:PointToObjectSpace(hitPos)
            local Height = math.abs(RelPos.Y)
            local Direction = math.sign(RelPos.Y) -- -1 is down, 1 is up
            
            -- Shift center so bottom/top stays at previous plane
            local OffsetY = (Height / 2) * Direction
            local NewCenter = BaseCF * CFrame.new(0, OffsetY, 0)
            
            TempPart.Size = Vector3.new(WidthData.Width, Height, (P1-P2).Magnitude)
            TempPart.CFrame = NewCenter
        end
    end
end)

--// INPUT HANDLER \\--
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        local hitPos, target = GetMouseHit()
        
        if ToolMode == "Create" then
            if CreateStep == 1 then
                Points[1] = hitPos
                CreateStep = 2
                StatusLabel.Text = "Step 2: Click End Corner (Length/Incline)"
                
            elseif CreateStep == 2 then
                Points[2] = hitPos
                CreateStep = 3
                StatusLabel.Text = "Step 3: Click to set Width (Expands towards mouse)"
                
            elseif CreateStep == 3 then
                -- Store Width and the CFrame calculated in RenderStepped
                -- We need to recalculate it exactly as the Render loop did to freeze it
                local P1 = Points[1]
                local P2 = Points[2]
                local MidLine = (P1 + P2) / 2
                local BaseCF = CFrame.lookAt(MidLine, P2)
                local RelPos = BaseCF:PointToObjectSpace(hitPos)
                local Width = math.abs(RelPos.X)
                local Direction = math.sign(RelPos.X)
                local OffsetX = (Width / 2) * Direction
                local NewCenter = BaseCF * CFrame.new(OffsetX, 0, 0)
                
                Points[3] = {Width = Width, CenterCF = NewCenter}
                
                CreateStep = 4
                StatusLabel.Text = "Step 4: Click to set Height (Expands towards mouse)"
                
            elseif CreateStep == 4 then
                -- Finalize
                if TempPart then
                    local FinalPart = TempPart:Clone()
                    FinalPart.Parent = workspace
                    FinalPart.CanCollide = true
                    FinalPart.Transparency = 0.5
                    
                    local rx, ry, rz = FinalPart.CFrame:ToEulerAnglesXYZ()
                    
                    table.insert(CreatedParts, {
                        Size = FinalPart.Size,
                        Pos = FinalPart.Position,
                        Rot = {X=rx, Y=ry, Z=rz}
                    })
                    
                    TempPart:Destroy()
                    TempPart = nil
                end
                CreateStep = 1
                Points = {}
                StatusLabel.Text = "Part Created! Click Start Corner for next."
            end
            
        elseif ToolMode == "Delete" then
            if #GroupParts > 0 then
                for _, part in ipairs(GroupParts) do
                    local path = "workspace"
                    local hierarchy = {}
                    local current = part
                    while current and current ~= game do
                        table.insert(hierarchy, 1, current.Name)
                        current = current.Parent
                    end
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
                StatusLabel.Text = "Deleted " .. #GroupParts .. " parts."
                SelectionFolder:ClearAllChildren()
                GroupParts = {}
            end
        end
    end
end)