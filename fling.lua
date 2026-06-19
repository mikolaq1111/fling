-- ╔══════════════════════════════════════════════════════════════╗
-- ║           FLING SCRIPT v3.0 — by m1koli4ik                  ║
-- ║      Premium GUI · Anti-Fling Bypass · Anti-Fling Shield     ║
-- ╚══════════════════════════════════════════════════════════════╝

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local HttpService      = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

-- ════════════════════════════════════════════════
--  STATE
-- ════════════════════════════════════════════════
local selectedPlayers  = {}   -- { [Player] = true }
local flingAllActive   = false
local antiFlingEnabled = false
local antiFlingConn    = nil
local savedCFrame      = nil

-- ════════════════════════════════════════════════
--  HELPERS
-- ════════════════════════════════════════════════
local function getHRP(player)
    local c = player and player.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(player)
    local c = player and player.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function savePosition()
    local hrp = getHRP(LocalPlayer)
    if hrp then savedCFrame = hrp.CFrame end
end

local function restorePosition()
    local hrp = getHRP(LocalPlayer)
    if hrp and savedCFrame then
        hrp.CFrame = savedCFrame
    end
end

-- ════════════════════════════════════════════════
--  ANTI-FLING BYPASS CORE
--  Works by: teleporting on top of target, forcing
--  PlatformStand, injecting high-force BodyVelocity,
--  AND setting raw AssemblyLinearVelocity each frame.
--  This bypasses most anti-fling scripts which only
--  destroy BodyMovers or reset CFrame on .Changed.
-- ════════════════════════════════════════════════
local function flingPlayer(target)
    if not target or target == LocalPlayer then return end

    local myHRP     = getHRP(LocalPlayer)
    local targetHRP = getHRP(target)
    local targetHum = getHumanoid(target)

    if not myHRP or not targetHRP or not targetHum then return end

    savePosition()

    -- Step 1: Teleport onto target
    myHRP.CFrame = targetHRP.CFrame * CFrame.new(0, 2.5, 0)
    task.wait(0.02)

    -- Step 2: Force target into Physics state (bypasses most locks)
    pcall(function() targetHum:ChangeState(Enum.HumanoidStateType.Physics) end)
    pcall(function() targetHum.PlatformStand = true end)

    -- Step 3: Remove any existing BodyMovers on target
    for _, v in ipairs(targetHRP:GetChildren()) do
        if v:IsA("BodyVelocity") or v:IsA("BodyForce") or
           v:IsA("BodyAngularVelocity") or v:IsA("VectorForce") then
            v:Destroy()
        end
    end

    -- Step 4: Inject high-force BodyVelocity with extreme random direction
    local direction = Vector3.new(
        math.random(-1, 1) ~= 0 and math.random(-1, 1) or 1,
        1,
        math.random(-1, 1) ~= 0 and math.random(-1, 1) or 1
    ).Unit

    local flingVec = direction * Vector3.new(
        math.random(8000, 12000),
        math.random(5000, 8000),
        math.random(8000, 12000)
    )

    local bv    = Instance.new("BodyVelocity")
    bv.Name     = "FLING_" .. HttpService:GenerateGUID(false)
    bv.Velocity = flingVec
    bv.MaxForce = Vector3.new(1e12, 1e12, 1e12)
    bv.P        = 1e9
    bv.Parent   = targetHRP

    -- Step 5: Per-frame velocity override for 0.2 s (beats anti-fling reset loops)
    local t0 = tick()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if tick() - t0 > 0.2 then
            conn:Disconnect()
            pcall(function() bv:Destroy() end)
            pcall(function() targetHum.PlatformStand = false end)
            pcall(function()
                targetHum:ChangeState(Enum.HumanoidStateType.GettingUp)
            end)
            return
        end
        pcall(function()
            targetHRP.AssemblyLinearVelocity = flingVec
        end)
        -- Re-inject if anti-fling destroyed our bv
        if not bv.Parent then
            local bv2    = Instance.new("BodyVelocity")
            bv2.Name     = bv.Name
            bv2.Velocity = flingVec
            bv2.MaxForce = Vector3.new(1e12, 1e12, 1e12)
            bv2.P        = 1e9
            bv2.Parent   = targetHRP
            bv = bv2
        end
    end)

    -- Return to saved spot
    task.delay(0.07, restorePosition)
end

-- ════════════════════════════════════════════════
--  FLING ALL
-- ════════════════════════════════════════════════
local flingAllStatusUpdate = nil  -- callback set by GUI

local function startFlingAll()
    if flingAllActive then return end
    flingAllActive = true
    task.spawn(function()
        while flingAllActive do
            for _, p in ipairs(Players:GetPlayers()) do
                if not flingAllActive then break end
                if p ~= LocalPlayer then
                    if flingAllStatusUpdate then
                        flingAllStatusUpdate("Flinging: " .. p.Name)
                    end
                    flingPlayer(p)
                    task.wait(0.4)
                end
            end
            task.wait(0.5)
        end
        if flingAllStatusUpdate then
            flingAllStatusUpdate("Idle — Ready")
        end
    end)
end

local function stopFlingAll()
    flingAllActive = false
end

-- ════════════════════════════════════════════════
--  ANTI-FLING SHIELD  (protect local player)
-- ════════════════════════════════════════════════
local function enableAntiFling()
    if antiFlingConn then return end
    antiFlingConn = RunService.Heartbeat:Connect(function()
        local hrp = getHRP(LocalPlayer)
        local hum = getHumanoid(LocalPlayer)
        if not hrp or not hum then return end

        -- Destroy injected movers
        for _, v in ipairs(hrp:GetChildren()) do
            if v:IsA("BodyVelocity") or v:IsA("BodyForce") or
               v:IsA("BodyAngularVelocity") or v:IsA("VectorForce") then
                v:Destroy()
            end
        end

        -- Cap velocity
        pcall(function()
            local vel = hrp.AssemblyLinearVelocity
            if vel.Magnitude > 75 then
                hrp.AssemblyLinearVelocity = vel.Unit * 75
            end
        end)

        -- Keep PlatformStand off
        if hum.PlatformStand then hum.PlatformStand = false end
    end)
end

local function disableAntiFling()
    if antiFlingConn then antiFlingConn:Disconnect(); antiFlingConn = nil end
end

-- ════════════════════════════════════════════════
--  GUI CONSTRUCTION
-- ════════════════════════════════════════════════
local oldGui = LocalPlayer.PlayerGui:FindFirstChild("FlingGUI_v3")
if oldGui then oldGui:Destroy() end

local ScreenGui             = Instance.new("ScreenGui")
ScreenGui.Name              = "FlingGUI_v3"
ScreenGui.ResetOnSpawn      = false
ScreenGui.ZIndexBehavior    = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset    = true
ScreenGui.Parent            = LocalPlayer.PlayerGui

-- ── Palette ───────────────────────────────────
local C = {
    bg      = Color3.fromRGB(9,   9,  18),
    panel   = Color3.fromRGB(16,  16, 30),
    card    = Color3.fromRGB(22,  22, 42),
    accent1 = Color3.fromRGB(120, 60, 255),
    accent2 = Color3.fromRGB(60, 180, 255),
    danger  = Color3.fromRGB(255, 60,  90),
    success = Color3.fromRGB(60,  230, 130),
    warning = Color3.fromRGB(255, 185,  40),
    text    = Color3.fromRGB(235, 235, 255),
    sub     = Color3.fromRGB(130, 130, 170),
    border  = Color3.fromRGB(45,  45,  80),
    sel     = Color3.fromRGB(55,  35, 115),
}

-- ── Builders ──────────────────────────────────
local function corner(r, parent)
    local u = Instance.new("UICorner")
    u.CornerRadius = UDim.new(0, r)
    u.Parent = parent
    return u
end

local function stroke(parent, a, b, t)
    local s = Instance.new("UIStroke")
    s.Thickness = t or 1.5
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    local g = Instance.new("UIGradient")
    g.Color    = ColorSequence.new({ ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b) })
    g.Rotation = 45
    g.Parent   = s
    s.Parent   = parent
    return s
end

local function frame(p)
    local f = Instance.new("Frame")
    f.BackgroundColor3 = p.bg   or C.panel
    f.BorderSizePixel  = 0
    f.Size             = p.sz   or UDim2.new(1,0,1,0)
    f.Position         = p.pos  or UDim2.new(0,0,0,0)
    f.ZIndex           = p.z    or 5
    f.Parent           = p.par
    if p.r then corner(p.r, f) end
    return f
end

local function label(p)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text        = p.text  or ""
    l.TextColor3  = p.color or C.text
    l.Font        = p.font  or Enum.Font.GothamBold
    l.TextSize    = p.ts    or 13
    l.TextXAlignment = p.ax or Enum.TextXAlignment.Left
    l.TextYAlignment = p.ay or Enum.TextYAlignment.Center
    l.TextWrapped = p.wrap  or false
    l.Size        = p.sz    or UDim2.new(1,0,1,0)
    l.Position    = p.pos   or UDim2.new(0,0,0,0)
    l.ZIndex      = p.z     or 6
    l.Parent      = p.par
    return l
end

local function gradLabel(lbl, ca, cb)
    local g = Instance.new("UIGradient")
    g.Color    = ColorSequence.new({ ColorSequenceKeypoint.new(0,ca), ColorSequenceKeypoint.new(1,cb) })
    g.Rotation = 0
    g.Parent   = lbl
end

local function btn(p)
    local b = Instance.new("TextButton")
    b.BackgroundColor3  = p.bg   or C.accent1
    b.TextColor3        = p.tc   or C.text
    b.Font              = Enum.Font.GothamBold
    b.TextSize          = p.ts   or 13
    b.Text              = p.text or "Btn"
    b.BorderSizePixel   = 0
    b.AutoButtonColor   = false
    b.Size              = p.sz   or UDim2.new(1,0,0,38)
    b.Position          = p.pos  or UDim2.new(0,0,0,0)
    b.ZIndex            = p.z    or 6
    b.Parent            = p.par
    if p.r  then corner(p.r, b) end
    if p.g1 then
        local gr = Instance.new("UIGradient")
        gr.Color    = ColorSequence.new({ ColorSequenceKeypoint.new(0,p.g1), ColorSequenceKeypoint.new(1,p.g2) })
        gr.Rotation = 90
        gr.Parent   = b
    end
    local origSz = p.sz or UDim2.new(1,0,0,38)
    b.MouseEnter:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.13), {
            BackgroundTransparency = 0.18,
            Size = UDim2.new(origSz.X.Scale, origSz.X.Offset+2, origSz.Y.Scale, origSz.Y.Offset+2)
        }):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.13), {
            BackgroundTransparency = 0,
            Size = origSz
        }):Play()
    end)
    b.MouseButton1Down:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.07), {
            BackgroundTransparency = 0.35,
            Size = UDim2.new(origSz.X.Scale, origSz.X.Offset-2, origSz.Y.Scale, origSz.Y.Offset-2)
        }):Play()
    end)
    b.MouseButton1Up:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.1), {
            BackgroundTransparency = 0, Size = origSz
        }):Play()
    end)
    return b
end

-- ════════════════════════════════════════════════
--  MAIN WINDOW
-- ════════════════════════════════════════════════
local W, H = 382, 585

local Main = frame({
    bg  = C.bg,
    sz  = UDim2.new(0, W, 0, H),
    pos = UDim2.new(0.5, -W/2, 0.5, -H/2),
    r   = 18,
    z   = 5,
    par = ScreenGui,
})
-- background gradient
do
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   Color3.fromRGB(12, 9, 26)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(9,  9, 18)),
        ColorSequenceKeypoint.new(1,   Color3.fromRGB(9, 13, 26)),
    })
    g.Rotation = 135
    g.Parent   = Main
end
local mainStroke = stroke(Main, C.accent1, C.accent2, 1.8)

-- ── Title bar ─────────────────────────────────
local TBar = frame({ bg=C.panel, sz=UDim2.new(1,0,0,54), r=18, z=6, par=Main })
-- flatten bottom corners
local TBarFix = frame({ bg=C.panel, sz=UDim2.new(1,0,0,18), pos=UDim2.new(0,0,1,-18), z=6, par=TBar })
do
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(28,14,58)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(10,18,48)),
    })
    g.Rotation = 90
    g.Parent   = TBar
end

-- icon
local ico = label({ text="⚡", sz=UDim2.new(0,36,0,36), pos=UDim2.new(0,12,0.5,-18), ts=22, ax=Enum.TextXAlignment.Center, z=7, par=TBar })

-- title
local titLbl = label({ text="FLING  SCRIPT", sz=UDim2.new(0,195,0,36), pos=UDim2.new(0,52,0.5,-18), ts=17, ax=Enum.TextXAlignment.Left, z=7, par=TBar })
gradLabel(titLbl, Color3.fromRGB(210,145,255), Color3.fromRGB(100,210,255))

local verLbl = label({ text="v3.0", sz=UDim2.new(0,44,0,18), pos=UDim2.new(1,-56,0.5,-9), ts=11, ax=Enum.TextXAlignment.Center, color=C.sub, font=Enum.Font.Gotham, z=7, par=TBar })

-- close button
local closeBtn = Instance.new("TextButton")
closeBtn.Size             = UDim2.new(0,28,0,28)
closeBtn.Position         = UDim2.new(1,-38,0.5,-14)
closeBtn.BackgroundColor3 = Color3.fromRGB(200,50,70)
closeBtn.TextColor3       = Color3.new(1,1,1)
closeBtn.Font             = Enum.Font.GothamBold
closeBtn.TextSize         = 13
closeBtn.Text             = "✕"
closeBtn.BorderSizePixel  = 0
closeBtn.AutoButtonColor  = false
closeBtn.ZIndex           = 8
closeBtn.Parent           = TBar
corner(8, closeBtn)
closeBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)

-- minimize button
local minBtn = Instance.new("TextButton")
minBtn.Size             = UDim2.new(0,28,0,28)
minBtn.Position         = UDim2.new(1,-70,0.5,-14)
minBtn.BackgroundColor3 = Color3.fromRGB(215,145,25)
minBtn.TextColor3       = Color3.new(1,1,1)
minBtn.Font             = Enum.Font.GothamBold
minBtn.TextSize         = 15
minBtn.Text             = "—"
minBtn.BorderSizePixel  = 0
minBtn.AutoButtonColor  = false
minBtn.ZIndex           = 8
minBtn.Parent           = TBar
corner(8, minBtn)

local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    TweenService:Create(Main, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
        Size = minimized and UDim2.new(0,W,0,54) or UDim2.new(0,W,0,H)
    }):Play()
end)

-- ── Drag ──────────────────────────────────────
do
    local dragging, ds, sp
    TBar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging, ds, sp = true, i.Position, Main.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
                      or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - ds
            Main.Position = UDim2.new(sp.X.Scale, sp.X.Offset+d.X, sp.Y.Scale, sp.Y.Offset+d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

-- ── Content scroll wrapper ────────────────────
local Content = Instance.new("ScrollingFrame")
Content.Size                   = UDim2.new(1, -20, 1, -62)
Content.Position               = UDim2.new(0, 10, 0, 58)
Content.BackgroundTransparency = 1
Content.BorderSizePixel        = 0
Content.ScrollBarThickness     = 0
Content.CanvasSize             = UDim2.new(0,0,0,0)
Content.AutomaticCanvasSize    = Enum.AutomaticSize.Y
Content.ZIndex                 = 5
Content.Parent                 = Main

local contentLayout = Instance.new("UIListLayout")
contentLayout.Padding       = UDim.new(0, 8)
contentLayout.SortOrder     = Enum.SortOrder.LayoutOrder
contentLayout.FillDirection = Enum.FillDirection.Vertical
contentLayout.Parent        = Content

-- ════════════════════════════════════════════════
--  STATUS BAR
-- ════════════════════════════════════════════════
local statCard = frame({ bg=C.card, sz=UDim2.new(1,0,0,36), r=9, z=5, par=Content })
statCard.LayoutOrder = 0
stroke(statCard, C.accent1, C.accent2, 1)

local statDot = frame({ bg=C.success, sz=UDim2.new(0,8,0,8), pos=UDim2.new(0,10,0.5,-4), r=99, z=6, par=statCard })

local statLbl = label({
    text  = "Idle — Ready",
    sz    = UDim2.new(1,-28,1,0),
    pos   = UDim2.new(0,24,0,0),
    color = C.sub,
    font  = Enum.Font.Gotham,
    ts    = 12,
    z     = 6,
    par   = statCard,
})

local function setStatus(msg, col)
    statLbl.Text = msg
    statDot.BackgroundColor3 = col or C.success
end

flingAllStatusUpdate = function(msg) setStatus(msg, C.danger) end

-- ════════════════════════════════════════════════
--  ANTI-FLING TOGGLE CARD
-- ════════════════════════════════════════════════
local shCard = frame({ bg=C.card, sz=UDim2.new(1,0,0,48), r=9, z=5, par=Content })
shCard.LayoutOrder = 1
stroke(shCard, C.success, C.accent2, 1)

label({ text="🛡", sz=UDim2.new(0,30,1,0), pos=UDim2.new(0,10,0,0), ts=18, ax=Enum.TextXAlignment.Center, z=6, par=shCard })
label({ text="Anti-Fling Shield", sz=UDim2.new(0,170,0,22), pos=UDim2.new(0,44,0,5), ts=13, z=6, par=shCard })
label({ text="Protect yourself from enemy flings", sz=UDim2.new(0,220,0,16), pos=UDim2.new(0,44,0,25), ts=10, color=C.sub, font=Enum.Font.Gotham, z=6, par=shCard })

local togBg = frame({ bg=Color3.fromRGB(38,38,58), sz=UDim2.new(0,48,0,24), pos=UDim2.new(1,-58,0.5,-12), r=99, z=6, par=shCard })
local togKnob = frame({ bg=Color3.fromRGB(150,150,170), sz=UDim2.new(0,20,0,20), pos=UDim2.new(0,2,0.5,-10), r=99, z=7, par=togBg })
local togBtn = Instance.new("TextButton")
togBtn.BackgroundTransparency = 1
togBtn.Size   = UDim2.new(1,0,1,0)
togBtn.Text   = ""
togBtn.ZIndex = 8
togBtn.Parent = togBg

togBtn.MouseButton1Click:Connect(function()
    antiFlingEnabled = not antiFlingEnabled
    if antiFlingEnabled then
        enableAntiFling()
        TweenService:Create(togBg,   TweenInfo.new(0.2), { BackgroundColor3 = C.success }):Play()
        TweenService:Create(togKnob, TweenInfo.new(0.2), { Position=UDim2.new(0,26,0.5,-10), BackgroundColor3=Color3.new(1,1,1) }):Play()
        setStatus("Shield ON — Protected", C.success)
    else
        disableAntiFling()
        TweenService:Create(togBg,   TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(38,38,58) }):Play()
        TweenService:Create(togKnob, TweenInfo.new(0.2), { Position=UDim2.new(0,2,0.5,-10), BackgroundColor3=Color3.fromRGB(150,150,170) }):Play()
        setStatus("Idle — Ready", C.success)
    end
end)

-- ════════════════════════════════════════════════
--  PLAYER LIST HEADER
-- ════════════════════════════════════════════════
local listHdr = frame({ bg=Color3.fromRGB(0,0,0), sz=UDim2.new(1,0,0,28), r=0, z=5, par=Content })
listHdr.BackgroundTransparency = 1
listHdr.LayoutOrder = 2

label({ text="👥  Players", sz=UDim2.new(0.6,0,1,0), ts=13, z=6, par=listHdr })
local selHint = label({ text="Select up to 3", sz=UDim2.new(0.4,-2,1,0), pos=UDim2.new(0.6,2,0,0), ts=10, color=C.sub, font=Enum.Font.Gotham, ax=Enum.TextXAlignment.Right, z=6, par=listHdr })

-- ── Scroll box ────────────────────────────────
local scrollOuter = frame({ bg=C.card, sz=UDim2.new(1,0,0,195), r=10, z=5, par=Content })
scrollOuter.LayoutOrder = 3
stroke(scrollOuter, C.border, C.border, 1)

local pScroll = Instance.new("ScrollingFrame")
pScroll.Size                   = UDim2.new(1,-4,1,-4)
pScroll.Position               = UDim2.new(0,2,0,2)
pScroll.BackgroundTransparency = 1
pScroll.BorderSizePixel        = 0
pScroll.ScrollBarThickness     = 4
pScroll.ScrollBarImageColor3   = C.accent1
pScroll.CanvasSize             = UDim2.new(0,0,0,0)
pScroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
pScroll.ZIndex                 = 6
pScroll.Parent                 = scrollOuter

local pLayout = Instance.new("UIListLayout")
pLayout.Padding     = UDim.new(0,4)
pLayout.SortOrder   = Enum.SortOrder.Name
pLayout.Parent      = pScroll

local pPad = Instance.new("UIPadding")
pPad.PaddingLeft = pPad.PaddingRight = pPad.PaddingTop = pPad.PaddingBottom = UDim.new(0,4)
pPad.Parent = pScroll

-- ── Player rows ───────────────────────────────
local rowMap = {}   -- [player] = { bg=Frame, check=Label }

local function updateRow(player)
    local r = rowMap[player]
    if not r then return end
    local isSel = selectedPlayers[player] == true
    TweenService:Create(r.bg, TweenInfo.new(0.13), {
        BackgroundColor3 = isSel and C.sel or C.panel
    }):Play()
    r.check.Text = isSel and "✓" or ""
    -- stroke
    local s = r.bg:FindFirstChildOfClass("UIStroke")
    if isSel then
        if not s then stroke(r.bg, C.accent1, C.accent2, 1.2) end
    else
        if s then s:Destroy() end
    end
end

local function addRow(player)
    if rowMap[player] then return end

    local row = frame({ bg=C.panel, sz=UDim2.new(1,0,0,42), r=8, z=7, par=pScroll })

    -- avatar
    local av = Instance.new("ImageLabel")
    av.Size             = UDim2.new(0,32,0,32)
    av.Position         = UDim2.new(0,5,0.5,-16)
    av.BackgroundColor3 = C.card
    av.BorderSizePixel  = 0
    av.ZIndex           = 8
    av.Parent           = row
    pcall(function()
        av.Image = "https://www.roblox.com/headshot-thumbnail/image?userId="..player.UserId.."&width=48&height=48&format=png"
    end)
    corner(7, av)

    local isSelf = player == LocalPlayer

    label({ text=(isSelf and "(You)  " or "")..player.Name, sz=UDim2.new(1,-82,0,20), pos=UDim2.new(0,42,0,5), ts=13, color=isSelf and C.sub or C.text, z=8, par=row })
    label({ text="@"..player.Name, sz=UDim2.new(1,-82,0,14), pos=UDim2.new(0,42,0,24), ts=10, color=C.sub, font=Enum.Font.Gotham, z=8, par=row })

    local chk = label({ text="", sz=UDim2.new(0,26,0,26), pos=UDim2.new(1,-32,0.5,-13), ts=15, color=C.accent2, ax=Enum.TextXAlignment.Center, z=8, par=row })

    rowMap[player] = { bg=row, check=chk }

    if not isSelf then
        local clickArea = Instance.new("TextButton")
        clickArea.BackgroundTransparency = 1
        clickArea.Size   = UDim2.new(1,0,1,0)
        clickArea.Text   = ""
        clickArea.ZIndex = 9
        clickArea.Parent = row

        clickArea.MouseButton1Click:Connect(function()
            if selectedPlayers[player] then
                selectedPlayers[player] = nil
            else
                local cnt = 0
                for _ in pairs(selectedPlayers) do cnt = cnt + 1 end
                if cnt >= 3 then
                    local first
                    for k in pairs(selectedPlayers) do first = k; break end
                    if first then selectedPlayers[first] = nil; updateRow(first) end
                end
                selectedPlayers[player] = true
            end
            updateRow(player)
            local n = 0
            for _ in pairs(selectedPlayers) do n = n + 1 end
            selHint.Text = n == 0 and "Select up to 3" or (n.." selected")
        end)
    end
end

local function removeRow(player)
    local r = rowMap[player]
    if r then r.bg:Destroy(); rowMap[player] = nil end
    selectedPlayers[player] = nil
end

local function refreshList()
    for p, r in pairs(rowMap) do r.bg:Destroy() end
    rowMap = {}
    selectedPlayers = {}
    selHint.Text = "Select up to 3"
    for _, p in ipairs(Players:GetPlayers()) do addRow(p) end
    setStatus("Refreshed — "..#Players:GetPlayers().." player(s)", C.accent2)
end

Players.PlayerAdded:Connect(function(p) task.wait(0.3); addRow(p) end)
Players.PlayerRemoving:Connect(removeRow)
refreshList()

-- ════════════════════════════════════════════════
--  ACTION BUTTONS (2 rows)
-- ════════════════════════════════════════════════

-- row 1: Refresh | Fling Selected
local row1 = frame({ bg=Color3.fromRGB(0,0,0), sz=UDim2.new(1,0,0,40), r=0, z=5, par=Content })
row1.BackgroundTransparency = 1
row1.LayoutOrder = 4

local refreshBtn = btn({
    text="🔄  Refresh", bg=C.card,
    g1=Color3.fromRGB(28,28,58), g2=Color3.fromRGB(18,18,40),
    sz=UDim2.new(0.48,0,1,0), pos=UDim2.new(0,0,0,0),
    r=10, ts=13, z=6, par=row1,
})
stroke(refreshBtn, C.border, C.accent1, 1)

local flingSelBtn = btn({
    text="⚡  Fling Selected",
    g1=Color3.fromRGB(140,60,255), g2=Color3.fromRGB(88,38,178),
    sz=UDim2.new(0.5,0,1,0), pos=UDim2.new(0.5,0,0,0),
    r=10, ts=13, z=6, par=row1,
})
stroke(flingSelBtn, C.accent1, C.accent2, 1.2)

-- row 2: Fling All | Stop
local row2 = frame({ bg=Color3.fromRGB(0,0,0), sz=UDim2.new(1,0,0,40), r=0, z=5, par=Content })
row2.BackgroundTransparency = 1
row2.LayoutOrder = 5

local flingAllBtn = btn({
    text="💀  Fling All",
    g1=Color3.fromRGB(255,60,90), g2=Color3.fromRGB(178,28,55),
    sz=UDim2.new(0.48,0,1,0), pos=UDim2.new(0,0,0,0),
    r=10, ts=13, z=6, par=row2,
})
stroke(flingAllBtn, C.danger, Color3.fromRGB(255,135,55), 1.2)

local stopBtn = btn({
    text="🛑  Stop",
    g1=Color3.fromRGB(255,195,45), g2=Color3.fromRGB(200,138,18),
    tc=Color3.fromRGB(20,10,0),
    sz=UDim2.new(0.5,0,1,0), pos=UDim2.new(0.5,0,0,0),
    r=10, ts=13, z=6, par=row2,
})
stroke(stopBtn, C.warning, Color3.fromRGB(255,118,18), 1.2)

-- ── Info footer ───────────────────────────────
local infoCard = frame({ bg=C.card, sz=UDim2.new(1,0,0,52), r=9, z=5, par=Content })
infoCard.LayoutOrder = 6
stroke(infoCard, C.border, C.border, 1)

local infoPad = Instance.new("UIPadding")
infoPad.PaddingLeft = infoPad.PaddingRight = infoPad.PaddingTop = infoPad.PaddingBottom = UDim.new(0,10)
infoPad.Parent = infoCard

label({
    text="⚡ Tap players to select (max 3) · Fling Selected to launch them\n💀 Fling All cycles everyone · 🛑 Stop returns you to where you were",
    sz=UDim2.new(1,0,1,0), ts=10, color=C.sub, font=Enum.Font.Gotham,
    wrap=true, ay=Enum.TextYAlignment.Center, z=6, par=infoCard,
})

-- ════════════════════════════════════════════════
--  CALLBACKS
-- ════════════════════════════════════════════════
refreshBtn.MouseButton1Click:Connect(refreshList)

flingSelBtn.MouseButton1Click:Connect(function()
    local targets = {}
    for p in pairs(selectedPlayers) do table.insert(targets, p) end
    if #targets == 0 then setStatus("No player selected!", C.warning); return end
    setStatus("Flinging "..#targets.." player(s)...", C.accent1)
    task.spawn(function()
        for _, p in ipairs(targets) do
            flingPlayer(p)
            task.wait(0.3)
        end
        setStatus("Done — Fling complete", C.success)
    end)
end)

flingAllBtn.MouseButton1Click:Connect(function()
    if flingAllActive then setStatus("Fling All already running!", C.warning); return end
    setStatus("Fling All — ACTIVE", C.danger)
    -- Pulse dot
    task.spawn(function()
        while flingAllActive do
            TweenService:Create(statDot, TweenInfo.new(0.4), { BackgroundTransparency=0.75 }):Play()
            task.wait(0.4)
            TweenService:Create(statDot, TweenInfo.new(0.4), { BackgroundTransparency=0   }):Play()
            task.wait(0.4)
        end
    end)
    startFlingAll()
end)

stopBtn.MouseButton1Click:Connect(function()
    stopFlingAll()
    restorePosition()
    setStatus("Stopped — Returned to position", C.success)
end)

-- ════════════════════════════════════════════════
--  OPEN ANIMATION
-- ════════════════════════════════════════════════
Main.Size                 = UDim2.new(0, W, 0, 0)
Main.BackgroundTransparency = 1
TweenService:Create(Main, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
    Size                  = UDim2.new(0, W, 0, H),
    BackgroundTransparency = 0,
}):Play()

-- ════════════════════════════════════════════════
--  RAINBOW BORDER ANIMATION
-- ════════════════════════════════════════════════
task.spawn(function()
    local hue = 0
    while ScreenGui and ScreenGui.Parent do
        hue = (hue + 0.0018) % 1
        local c1 = Color3.fromHSV(hue,           0.72, 1)
        local c2 = Color3.fromHSV((hue+0.28)%1,  0.72, 1)
        local g  = mainStroke:FindFirstChildOfClass("UIGradient")
        if g then
            g.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, c1),
                ColorSequenceKeypoint.new(1, c2),
            })
        end
        task.wait(0.04)
    end
end)

print("[FlingScript v3.0] ✅ Loaded — GUI ready!")
