-- ╔══════════════════════════════════════════════════════════════╗
-- ║           FLING SCRIPT v3.1 — by m1koli4ik                  ║
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
local selectedPlayers  = {}
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
--  FLING CORE  (Anti-Fling Bypass)
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

    -- Step 2: Force Physics state (bypasses most anti-fling locks)
    pcall(function() targetHum:ChangeState(Enum.HumanoidStateType.Physics) end)
    pcall(function() targetHum.PlatformStand = true end)

    -- Step 3: Destroy any existing body movers on target
    for _, v in ipairs(targetHRP:GetChildren()) do
        if v:IsA("BodyVelocity") or v:IsA("BodyForce")
        or v:IsA("BodyAngularVelocity") or v:IsA("VectorForce") then
            v:Destroy()
        end
    end

    -- Step 4: Build fling vector (extreme force, random horizontal direction)
    local sx = math.random(0, 1) == 0 and 1 or -1
    local sz = math.random(0, 1) == 0 and 1 or -1
    local flingVec = Vector3.new(
        sx * math.random(9000, 13000),
        math.random(5000, 8000),
        sz * math.random(9000, 13000)
    )

    -- Step 5: Inject BodyVelocity with max force
    local bvName = "FLING_" .. HttpService:GenerateGUID(false)
    local bv     = Instance.new("BodyVelocity")
    bv.Name     = bvName
    bv.Velocity = flingVec
    bv.MaxForce = Vector3.new(1e12, 1e12, 1e12)
    bv.P        = 1e9
    bv.Parent   = targetHRP

    -- Step 6: Per-frame velocity override for 0.2 s
    -- Re-injects if anti-fling destroys the mover
    local t0   = tick()
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
        -- Raw velocity override (beats velocity-reset anti-flings)
        pcall(function()
            targetHRP.AssemblyLinearVelocity = flingVec
        end)
        -- Re-inject mover if it was destroyed
        if not (bv and bv.Parent) then
            local bv2     = Instance.new("BodyVelocity")
            bv2.Name     = bvName
            bv2.Velocity = flingVec
            bv2.MaxForce = Vector3.new(1e12, 1e12, 1e12)
            bv2.P        = 1e9
            bv2.Parent   = targetHRP
            bv = bv2
        end
    end)

    -- Return home after brief delay
    task.delay(0.07, restorePosition)
end

-- ════════════════════════════════════════════════
--  FLING ALL
-- ════════════════════════════════════════════════
local flingAllStatusCb = nil  -- set by GUI

local function startFlingAll()
    if flingAllActive then return end
    flingAllActive = true
    task.spawn(function()
        while flingAllActive do
            for _, p in ipairs(Players:GetPlayers()) do
                if not flingAllActive then break end
                if p ~= LocalPlayer then
                    if flingAllStatusCb then
                        flingAllStatusCb("Flinging: " .. p.Name)
                    end
                    flingPlayer(p)
                    task.wait(0.4)
                end
            end
            task.wait(0.5)
        end
        if flingAllStatusCb then flingAllStatusCb("Idle — Ready") end
    end)
end

local function stopFlingAll()
    flingAllActive = false
end

-- ════════════════════════════════════════════════
--  ANTI-FLING SHIELD
-- ════════════════════════════════════════════════
local function enableAntiFling()
    if antiFlingConn then return end
    antiFlingConn = RunService.Heartbeat:Connect(function()
        local hrp = getHRP(LocalPlayer)
        local hum = getHumanoid(LocalPlayer)
        if not hrp or not hum then return end
        -- Remove injected movers
        for _, v in ipairs(hrp:GetChildren()) do
            if v:IsA("BodyVelocity") or v:IsA("BodyForce")
            or v:IsA("BodyAngularVelocity") or v:IsA("VectorForce") then
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
    if antiFlingConn then
        antiFlingConn:Disconnect()
        antiFlingConn = nil
    end
end

-- ════════════════════════════════════════════════
--  GUI
-- ════════════════════════════════════════════════
local oldGui = LocalPlayer.PlayerGui:FindFirstChild("FlingGUI_v31")
if oldGui then oldGui:Destroy() end

local ScreenGui          = Instance.new("ScreenGui")
ScreenGui.Name           = "FlingGUI_v31"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
ScreenGui.Parent         = LocalPlayer.PlayerGui

-- Colour palette
local C = {
    bg      = Color3.fromRGB(9,   9,  18),
    panel   = Color3.fromRGB(16,  16, 30),
    card    = Color3.fromRGB(22,  22, 42),
    accent1 = Color3.fromRGB(120, 60, 255),
    accent2 = Color3.fromRGB(60, 180, 255),
    danger  = Color3.fromRGB(255,  60,  90),
    success = Color3.fromRGB(60,  230, 130),
    warning = Color3.fromRGB(255, 185,  40),
    text    = Color3.fromRGB(235, 235, 255),
    sub     = Color3.fromRGB(130, 130, 170),
    border  = Color3.fromRGB(45,  45,  80),
    sel     = Color3.fromRGB(55,  35, 115),
}

-- ── Factory helpers ───────────────────────────
local function mkCorner(r, parent)
    local u = Instance.new("UICorner")
    u.CornerRadius = UDim.new(0, r)
    u.Parent = parent
    return u
end

local function mkStroke(parent, colorA, colorB, thickness)
    local s = Instance.new("UIStroke")
    s.Thickness = thickness or 1.5
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, colorA),
        ColorSequenceKeypoint.new(1, colorB),
    })
    g.Rotation = 45
    g.Parent   = s
    s.Parent   = parent
    return s
end

local function mkFrame(bg, sz, pos, r, z, parent)
    local f = Instance.new("Frame")
    f.BackgroundColor3 = bg
    f.BorderSizePixel  = 0
    f.Size             = sz
    f.Position         = pos or UDim2.new(0, 0, 0, 0)
    f.ZIndex           = z  or 5
    f.Parent           = parent
    if r then mkCorner(r, f) end
    return f
end

local function mkLabel(text, sz, pos, ts, color, font, ax, ay, wrap, z, parent)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text           = text  or ""
    l.TextColor3     = color or C.text
    l.Font           = font  or Enum.Font.GothamBold
    l.TextSize       = ts    or 13
    l.TextXAlignment = ax    or Enum.TextXAlignment.Left
    l.TextYAlignment = ay    or Enum.TextYAlignment.Center
    l.TextWrapped    = wrap  or false
    l.Size           = sz    or UDim2.new(1, 0, 1, 0)
    l.Position       = pos   or UDim2.new(0, 0, 0, 0)
    l.ZIndex         = z     or 6
    l.Parent         = parent
    return l
end

local function mkBtn(text, bgColor, g1, g2, tc, sz, pos, r, ts, z, parent)
    local b = Instance.new("TextButton")
    b.BackgroundColor3 = bgColor or C.accent1
    b.TextColor3       = tc      or C.text
    b.Font             = Enum.Font.GothamBold
    b.TextSize         = ts      or 13
    b.Text             = text    or "Btn"
    b.BorderSizePixel  = 0
    b.AutoButtonColor  = false
    b.Size             = sz      or UDim2.new(1, 0, 0, 38)
    b.Position         = pos     or UDim2.new(0, 0, 0, 0)
    b.ZIndex           = z       or 6
    b.Parent           = parent
    if r then mkCorner(r, b) end
    if g1 and g2 then
        local gr = Instance.new("UIGradient")
        gr.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, g1),
            ColorSequenceKeypoint.new(1, g2),
        })
        gr.Rotation = 90
        gr.Parent   = b
    end
    -- Hover / press micro-animations
    local origSz = sz or UDim2.new(1, 0, 0, 38)
    b.MouseEnter:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.13), {
            BackgroundTransparency = 0.18,
            Size = UDim2.new(
                origSz.X.Scale, origSz.X.Offset + 2,
                origSz.Y.Scale, origSz.Y.Offset + 2
            ),
        }):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.13), {
            BackgroundTransparency = 0,
            Size = origSz,
        }):Play()
    end)
    b.MouseButton1Down:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.07), {
            BackgroundTransparency = 0.35,
            Size = UDim2.new(
                origSz.X.Scale, origSz.X.Offset - 2,
                origSz.Y.Scale, origSz.Y.Offset - 2
            ),
        }):Play()
    end)
    b.MouseButton1Up:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.1), {
            BackgroundTransparency = 0,
            Size = origSz,
        }):Play()
    end)
    return b
end

-- ════════════════════════════════════════════════
--  MAIN WINDOW
-- ════════════════════════════════════════════════
local W, H = 384, 590

local Main = mkFrame(
    C.bg,
    UDim2.new(0, W, 0, H),
    UDim2.new(0.5, -W/2, 0.5, -H/2),
    18, 5, ScreenGui
)

do -- background gradient
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   Color3.fromRGB(12, 9,  26)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(9,  9,  18)),
        ColorSequenceKeypoint.new(1,   Color3.fromRGB(9,  13, 26)),
    })
    g.Rotation = 135
    g.Parent   = Main
end

local mainStroke = mkStroke(Main, C.accent1, C.accent2, 1.8)

-- ── Title bar ─────────────────────────────────
local TBar = mkFrame(C.panel, UDim2.new(1,0,0,54), UDim2.new(0,0,0,0), 18, 6, Main)

-- Flatten bottom corners of TBar
mkFrame(C.panel, UDim2.new(1,0,0,18), UDim2.new(0,0,1,-18), 0, 6, TBar)

do -- title bar gradient
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 14, 58)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 18, 48)),
    })
    g.Rotation = 90
    g.Parent   = TBar
end

-- Icon
mkLabel("⚡",
    UDim2.new(0,36,0,36), UDim2.new(0,12,0.5,-18),
    22, C.text, Enum.Font.GothamBold,
    Enum.TextXAlignment.Center, Enum.TextYAlignment.Center,
    false, 7, TBar
)

-- Title label + gradient
local titLbl = mkLabel("FLING  SCRIPT",
    UDim2.new(0,200,0,36), UDim2.new(0,52,0.5,-18),
    17, C.text, Enum.Font.GothamBold,
    Enum.TextXAlignment.Left, Enum.TextYAlignment.Center,
    false, 7, TBar
)
do
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   Color3.fromRGB(210, 145, 255)),
        ColorSequenceKeypoint.new(1,   Color3.fromRGB(100, 210, 255)),
    })
    g.Rotation = 0
    g.Parent   = titLbl
end

-- Version
mkLabel("v3.1",
    UDim2.new(0,44,0,18), UDim2.new(1,-56,0.5,-9),
    11, C.sub, Enum.Font.Gotham,
    Enum.TextXAlignment.Center, Enum.TextYAlignment.Center,
    false, 7, TBar
)

-- Close button
do
    local b = Instance.new("TextButton")
    b.Size             = UDim2.new(0, 28, 0, 28)
    b.Position         = UDim2.new(1, -38, 0.5, -14)
    b.BackgroundColor3 = Color3.fromRGB(200, 50, 70)
    b.TextColor3       = Color3.new(1, 1, 1)
    b.Font             = Enum.Font.GothamBold
    b.TextSize         = 13
    b.Text             = "✕"
    b.BorderSizePixel  = 0
    b.AutoButtonColor  = false
    b.ZIndex           = 8
    b.Parent           = TBar
    mkCorner(8, b)
    b.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)
end

-- Minimise button
local minimized = false
do
    local b = Instance.new("TextButton")
    b.Size             = UDim2.new(0, 28, 0, 28)
    b.Position         = UDim2.new(1, -70, 0.5, -14)
    b.BackgroundColor3 = Color3.fromRGB(215, 145, 25)
    b.TextColor3       = Color3.new(1, 1, 1)
    b.Font             = Enum.Font.GothamBold
    b.TextSize         = 15
    b.Text             = "—"
    b.BorderSizePixel  = 0
    b.AutoButtonColor  = false
    b.ZIndex           = 8
    b.Parent           = TBar
    mkCorner(8, b)
    b.MouseButton1Click:Connect(function()
        minimized = not minimized
        TweenService:Create(Main,
            TweenInfo.new(0.25, Enum.EasingStyle.Quad),
            { Size = minimized and UDim2.new(0,W,0,54) or UDim2.new(0,W,0,H) }
        ):Play()
    end)
end

-- ── Drag ──────────────────────────────────────
do
    local dragging, ds, sp
    TBar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            ds = i.Position
            sp = Main.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and
           (i.UserInputType == Enum.UserInputType.MouseMovement
         or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - ds
            Main.Position = UDim2.new(
                sp.X.Scale, sp.X.Offset + d.X,
                sp.Y.Scale, sp.Y.Offset + d.Y
            )
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

-- ── Scrollable content area ───────────────────
local Content = Instance.new("ScrollingFrame")
Content.Size                   = UDim2.new(1, -20, 1, -62)
Content.Position               = UDim2.new(0, 10, 0, 58)
Content.BackgroundTransparency = 1
Content.BorderSizePixel        = 0
Content.ScrollBarThickness     = 0
Content.CanvasSize             = UDim2.new(0, 0, 0, 0)
Content.AutomaticCanvasSize    = Enum.AutomaticSize.Y
Content.ZIndex                 = 5
Content.Parent                 = Main

local cLayout = Instance.new("UIListLayout")
cLayout.Padding       = UDim.new(0, 8)
cLayout.SortOrder     = Enum.SortOrder.LayoutOrder
cLayout.FillDirection = Enum.FillDirection.Vertical
cLayout.Parent        = Content

-- ════════════════════════════════════════════════
--  STATUS BAR  (LayoutOrder 0)
-- ════════════════════════════════════════════════
local statCard = mkFrame(C.card, UDim2.new(1,0,0,36), UDim2.new(0,0,0,0), 9, 5, Content)
statCard.LayoutOrder = 0
mkStroke(statCard, C.accent1, C.accent2, 1)

local statDot = mkFrame(
    C.success,
    UDim2.new(0, 8, 0, 8), UDim2.new(0, 10, 0.5, -4),
    99, 6, statCard
)

local statLbl = mkLabel(
    "Idle — Ready",
    UDim2.new(1,-28,1,0), UDim2.new(0,24,0,0),
    12, C.sub, Enum.Font.Gotham,
    Enum.TextXAlignment.Left, Enum.TextYAlignment.Center,
    false, 6, statCard
)

local function setStatus(msg, col)
    statLbl.Text = msg
    statDot.BackgroundColor3 = col or C.success
end

flingAllStatusCb = function(msg) setStatus(msg, C.danger) end

-- ════════════════════════════════════════════════
--  ANTI-FLING SHIELD CARD  (LayoutOrder 1)
-- ════════════════════════════════════════════════
local shCard = mkFrame(C.card, UDim2.new(1,0,0,48), UDim2.new(0,0,0,0), 9, 5, Content)
shCard.LayoutOrder = 1
mkStroke(shCard, C.success, C.accent2, 1)

mkLabel("🛡",
    UDim2.new(0,30,1,0), UDim2.new(0,10,0,0),
    18, C.text, Enum.Font.GothamBold,
    Enum.TextXAlignment.Center, Enum.TextYAlignment.Center,
    false, 6, shCard
)
mkLabel("Anti-Fling Shield",
    UDim2.new(0,175,0,22), UDim2.new(0,44,0,5),
    13, C.text, Enum.Font.GothamBold,
    Enum.TextXAlignment.Left, Enum.TextYAlignment.Center,
    false, 6, shCard
)
mkLabel("Protect yourself from enemy flings",
    UDim2.new(0,230,0,16), UDim2.new(0,44,0,25),
    10, C.sub, Enum.Font.Gotham,
    Enum.TextXAlignment.Left, Enum.TextYAlignment.Center,
    false, 6, shCard
)

local togBg = mkFrame(
    Color3.fromRGB(38,38,58),
    UDim2.new(0,48,0,24), UDim2.new(1,-58,0.5,-12),
    99, 6, shCard
)
local togKnob = mkFrame(
    Color3.fromRGB(150,150,170),
    UDim2.new(0,20,0,20), UDim2.new(0,2,0.5,-10),
    99, 7, togBg
)
do
    local tb = Instance.new("TextButton")
    tb.BackgroundTransparency = 1
    tb.Size   = UDim2.new(1, 0, 1, 0)
    tb.Text   = ""
    tb.ZIndex = 8
    tb.Parent = togBg
    tb.MouseButton1Click:Connect(function()
        antiFlingEnabled = not antiFlingEnabled
        if antiFlingEnabled then
            enableAntiFling()
            TweenService:Create(togBg,   TweenInfo.new(0.2), { BackgroundColor3 = C.success }):Play()
            TweenService:Create(togKnob, TweenInfo.new(0.2), {
                Position         = UDim2.new(0, 26, 0.5, -10),
                BackgroundColor3 = Color3.new(1, 1, 1),
            }):Play()
            setStatus("Shield ON — You are protected", C.success)
        else
            disableAntiFling()
            TweenService:Create(togBg,   TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(38,38,58) }):Play()
            TweenService:Create(togKnob, TweenInfo.new(0.2), {
                Position         = UDim2.new(0, 2, 0.5, -10),
                BackgroundColor3 = Color3.fromRGB(150,150,170),
            }):Play()
            setStatus("Idle — Ready", C.success)
        end
    end)
end

-- ════════════════════════════════════════════════
--  PLAYER LIST HEADER  (LayoutOrder 2)
-- ════════════════════════════════════════════════
local listHdr = mkFrame(
    Color3.fromRGB(0,0,0),
    UDim2.new(1,0,0,28), UDim2.new(0,0,0,0),
    0, 5, Content
)
listHdr.BackgroundTransparency = 1
listHdr.LayoutOrder = 2

mkLabel("👥  Players",
    UDim2.new(0.6,0,1,0), UDim2.new(0,0,0,0),
    13, C.text, Enum.Font.GothamBold,
    Enum.TextXAlignment.Left, Enum.TextYAlignment.Center,
    false, 6, listHdr
)
local selHint = mkLabel("Select up to 3",
    UDim2.new(0.4,-2,1,0), UDim2.new(0.6,2,0,0),
    10, C.sub, Enum.Font.Gotham,
    Enum.TextXAlignment.Right, Enum.TextYAlignment.Center,
    false, 6, listHdr
)

-- ── Scroll box  (LayoutOrder 3) ───────────────
local scrollOuter = mkFrame(C.card, UDim2.new(1,0,0,195), UDim2.new(0,0,0,0), 10, 5, Content)
scrollOuter.LayoutOrder = 3
mkStroke(scrollOuter, C.border, C.border, 1)

local pScroll = Instance.new("ScrollingFrame")
pScroll.Size                   = UDim2.new(1, -4, 1, -4)
pScroll.Position               = UDim2.new(0, 2, 0, 2)
pScroll.BackgroundTransparency = 1
pScroll.BorderSizePixel        = 0
pScroll.ScrollBarThickness     = 4
pScroll.ScrollBarImageColor3   = C.accent1
pScroll.CanvasSize             = UDim2.new(0, 0, 0, 0)
pScroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
pScroll.ZIndex                 = 6
pScroll.Parent                 = scrollOuter

local pLayout = Instance.new("UIListLayout")
pLayout.Padding     = UDim.new(0, 4)
pLayout.SortOrder   = Enum.SortOrder.Name
pLayout.Parent      = pScroll

-- NOTE: Lua 5.1 does NOT support chained assignment (a = b = c)
-- Each property must be set individually.
local pPad = Instance.new("UIPadding")
pPad.PaddingLeft   = UDim.new(0, 4)
pPad.PaddingRight  = UDim.new(0, 4)
pPad.PaddingTop    = UDim.new(0, 4)
pPad.PaddingBottom = UDim.new(0, 4)
pPad.Parent        = pScroll

-- ── Player row builder ────────────────────────
local rowMap = {}

local function updateRow(player)
    local r = rowMap[player]
    if not r then return end
    local isSel = selectedPlayers[player] == true
    TweenService:Create(r.bg, TweenInfo.new(0.13), {
        BackgroundColor3 = isSel and C.sel or C.panel,
    }):Play()
    r.check.Text = isSel and "✓" or ""
    local s = r.bg:FindFirstChildOfClass("UIStroke")
    if isSel then
        if not s then mkStroke(r.bg, C.accent1, C.accent2, 1.2) end
    else
        if s then s:Destroy() end
    end
end

local function addRow(player)
    if rowMap[player] then return end

    local row = mkFrame(C.panel, UDim2.new(1,0,0,42), UDim2.new(0,0,0,0), 8, 7, pScroll)

    -- Avatar
    local av = Instance.new("ImageLabel")
    av.Size             = UDim2.new(0, 32, 0, 32)
    av.Position         = UDim2.new(0, 5, 0.5, -16)
    av.BackgroundColor3 = C.card
    av.BorderSizePixel  = 0
    av.ZIndex           = 8
    av.Parent           = row
    mkCorner(7, av)
    pcall(function()
        av.Image = "https://www.roblox.com/headshot-thumbnail/image?userId="
            .. player.UserId .. "&width=48&height=48&format=png"
    end)

    local isSelf = player == LocalPlayer

    mkLabel(
        (isSelf and "(You)  " or "") .. player.Name,
        UDim2.new(1,-82,0,20), UDim2.new(0,42,0,5),
        13, isSelf and C.sub or C.text, Enum.Font.GothamBold,
        Enum.TextXAlignment.Left, Enum.TextYAlignment.Center,
        false, 8, row
    )
    mkLabel(
        "@" .. player.Name,
        UDim2.new(1,-82,0,14), UDim2.new(0,42,0,24),
        10, C.sub, Enum.Font.Gotham,
        Enum.TextXAlignment.Left, Enum.TextYAlignment.Center,
        false, 8, row
    )

    local chk = mkLabel("",
        UDim2.new(0,26,0,26), UDim2.new(1,-32,0.5,-13),
        15, C.accent2, Enum.Font.GothamBold,
        Enum.TextXAlignment.Center, Enum.TextYAlignment.Center,
        false, 8, row
    )

    rowMap[player] = { bg = row, check = chk }

    if not isSelf then
        local ca = Instance.new("TextButton")
        ca.BackgroundTransparency = 1
        ca.Size   = UDim2.new(1, 0, 1, 0)
        ca.Text   = ""
        ca.ZIndex = 9
        ca.Parent = row
        ca.MouseButton1Click:Connect(function()
            if selectedPlayers[player] then
                selectedPlayers[player] = nil
            else
                -- Max 3 selected
                local cnt = 0
                for _ in pairs(selectedPlayers) do cnt = cnt + 1 end
                if cnt >= 3 then
                    local first
                    for k in pairs(selectedPlayers) do first = k; break end
                    if first then
                        selectedPlayers[first] = nil
                        updateRow(first)
                    end
                end
                selectedPlayers[player] = true
            end
            updateRow(player)
            local n = 0
            for _ in pairs(selectedPlayers) do n = n + 1 end
            selHint.Text = n == 0 and "Select up to 3" or (n .. " selected")
        end)
    end
end

local function removeRow(player)
    local r = rowMap[player]
    if r then r.bg:Destroy(); rowMap[player] = nil end
    selectedPlayers[player] = nil
end

local function refreshList()
    for _, r in pairs(rowMap) do r.bg:Destroy() end
    rowMap            = {}
    selectedPlayers   = {}
    selHint.Text      = "Select up to 3"
    for _, p in ipairs(Players:GetPlayers()) do addRow(p) end
    setStatus("Refreshed — " .. #Players:GetPlayers() .. " player(s)", C.accent2)
end

Players.PlayerAdded:Connect(function(p)
    task.wait(0.3)
    addRow(p)
end)
Players.PlayerRemoving:Connect(removeRow)

refreshList()

-- ════════════════════════════════════════════════
--  BUTTON ROW 1: Refresh | Fling Selected  (LayoutOrder 4)
-- ════════════════════════════════════════════════
local row1 = mkFrame(
    Color3.fromRGB(0,0,0),
    UDim2.new(1,0,0,40), UDim2.new(0,0,0,0),
    0, 5, Content
)
row1.BackgroundTransparency = 1
row1.LayoutOrder = 4

local refreshBtn = mkBtn(
    "🔄  Refresh",
    C.card,
    Color3.fromRGB(28,28,58), Color3.fromRGB(18,18,40),
    C.text,
    UDim2.new(0.48,0,1,0), UDim2.new(0,0,0,0),
    10, 13, 6, row1
)
mkStroke(refreshBtn, C.border, C.accent1, 1)

local flingSelBtn = mkBtn(
    "⚡  Fling Selected",
    C.accent1,
    Color3.fromRGB(140,60,255), Color3.fromRGB(88,38,178),
    C.text,
    UDim2.new(0.5,0,1,0), UDim2.new(0.5,0,0,0),
    10, 13, 6, row1
)
mkStroke(flingSelBtn, C.accent1, C.accent2, 1.2)

-- ════════════════════════════════════════════════
--  BUTTON ROW 2: Fling All | Stop  (LayoutOrder 5)
-- ════════════════════════════════════════════════
local row2 = mkFrame(
    Color3.fromRGB(0,0,0),
    UDim2.new(1,0,0,40), UDim2.new(0,0,0,0),
    0, 5, Content
)
row2.BackgroundTransparency = 1
row2.LayoutOrder = 5

local flingAllBtn = mkBtn(
    "💀  Fling All",
    C.danger,
    Color3.fromRGB(255,60,90), Color3.fromRGB(178,28,55),
    C.text,
    UDim2.new(0.48,0,1,0), UDim2.new(0,0,0,0),
    10, 13, 6, row2
)
mkStroke(flingAllBtn, C.danger, Color3.fromRGB(255,135,55), 1.2)

local stopBtn = mkBtn(
    "🛑  Stop",
    C.warning,
    Color3.fromRGB(255,195,45), Color3.fromRGB(200,138,18),
    Color3.fromRGB(20,10,0),
    UDim2.new(0.5,0,1,0), UDim2.new(0.5,0,0,0),
    10, 13, 6, row2
)
mkStroke(stopBtn, C.warning, Color3.fromRGB(255,118,18), 1.2)

-- ════════════════════════════════════════════════
--  INFO FOOTER  (LayoutOrder 6)
-- ════════════════════════════════════════════════
local infoCard = mkFrame(C.card, UDim2.new(1,0,0,52), UDim2.new(0,0,0,0), 9, 5, Content)
infoCard.LayoutOrder = 6
mkStroke(infoCard, C.border, C.border, 1)

local infoPad = Instance.new("UIPadding")
infoPad.PaddingLeft   = UDim.new(0, 10)
infoPad.PaddingRight  = UDim.new(0, 10)
infoPad.PaddingTop    = UDim.new(0, 6)
infoPad.PaddingBottom = UDim.new(0, 6)
infoPad.Parent        = infoCard

mkLabel(
    "⚡ Tap players to select (max 3)  ·  Fling Selected to launch\n"
 .. "💀 Fling All cycles everyone  ·  🛑 Stop returns you home",
    UDim2.new(1,0,1,0), UDim2.new(0,0,0,0),
    10, C.sub, Enum.Font.Gotham,
    Enum.TextXAlignment.Left, Enum.TextYAlignment.Center,
    true, 6, infoCard
)

-- ════════════════════════════════════════════════
--  CALLBACKS
-- ════════════════════════════════════════════════
refreshBtn.MouseButton1Click:Connect(refreshList)

flingSelBtn.MouseButton1Click:Connect(function()
    local targets = {}
    for p in pairs(selectedPlayers) do table.insert(targets, p) end
    if #targets == 0 then
        setStatus("No player selected!", C.warning)
        return
    end
    setStatus("Flinging " .. #targets .. " player(s)...", C.accent1)
    task.spawn(function()
        for _, p in ipairs(targets) do
            flingPlayer(p)
            task.wait(0.3)
        end
        setStatus("Done — Fling complete", C.success)
    end)
end)

flingAllBtn.MouseButton1Click:Connect(function()
    if flingAllActive then
        setStatus("Fling All already running!", C.warning)
        return
    end
    setStatus("Fling All — ACTIVE", C.danger)
    -- Pulse the status dot
    task.spawn(function()
        while flingAllActive do
            TweenService:Create(statDot, TweenInfo.new(0.4), { BackgroundTransparency = 0.75 }):Play()
            task.wait(0.4)
            TweenService:Create(statDot, TweenInfo.new(0.4), { BackgroundTransparency = 0   }):Play()
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
Main.Size                  = UDim2.new(0, W, 0, 0)
Main.BackgroundTransparency = 1
TweenService:Create(Main,
    TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
    { Size = UDim2.new(0,W,0,H), BackgroundTransparency = 0 }
):Play()

-- ════════════════════════════════════════════════
--  RAINBOW BORDER LOOP
-- ════════════════════════════════════════════════
task.spawn(function()
    local hue = 0
    while ScreenGui and ScreenGui.Parent do
        hue = (hue + 0.0018) % 1
        local c1 = Color3.fromHSV(hue,            0.72, 1)
        local c2 = Color3.fromHSV((hue + 0.28)%1, 0.72, 1)
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

print("[FlingScript v3.1] Loaded successfully ✅")
