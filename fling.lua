-- ╔══════════════════════════════════════════════════════════════╗
-- ║           FLING SCRIPT v3.2 — by m1koli4ik                  ║
-- ║      Premium GUI · Physics Overlap Fling · Anti-Fling Shield ║
-- ╚══════════════════════════════════════════════════════════════╝

-- ─────────────────────────────────────────────────────────────
--  HOW THE FLING WORKS (LocalScript limitation workaround):
--  You CANNOT apply forces to other players from a LocalScript.
--  Instead we:
--  1. Save our CFrame & zero our velocity on restore
--  2. Teleport OUR HRP directly inside the target's HRP
--  3. Apply a huge BodyVelocity to OURSELVES
--  4. The local physics engine resolves the overlap → target flies
--  5. Destroy BV, immediately teleport ourselves back home
-- ─────────────────────────────────────────────────────────────

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

-- Save position + velocity state before flinging
local function savePosition()
    local hrp = getHRP(LocalPlayer)
    if hrp then
        savedCFrame = hrp.CFrame
    end
end

-- Restore position AND zero out our own velocity so we don't keep flying
local function restorePosition()
    local hrp = getHRP(LocalPlayer)
    if hrp and savedCFrame then
        hrp.CFrame = savedCFrame
        -- Zero our velocity so residual physics doesn't carry us away
        pcall(function()
            hrp.AssemblyLinearVelocity  = Vector3.new(0, 0, 0)
            hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        end)
    end
end

-- ════════════════════════════════════════════════
--  FLING CORE
--  ⚠ We apply BodyVelocity to OUR OWN HRP.
--  Teleporting inside the target causes a physics
--  overlap → local engine pushes both chars apart
--  at the applied velocity → target flies far.
--  We immediately restore ourselves home.
-- ════════════════════════════════════════════════
local function flingPlayer(target)
    if not target or target == LocalPlayer then return end

    local myHRP    = getHRP(LocalPlayer)
    local myHum    = getHumanoid(LocalPlayer)
    local targHRP  = getHRP(target)

    if not myHRP or not targHRP then return end

    -- 1. Lock in our home position
    savePosition()

    -- 2. Freeze our own humanoid so nothing interferes
    local oldWalkSpeed = 16
    local oldJumpPower = 50
    if myHum then
        oldWalkSpeed           = myHum.WalkSpeed
        oldJumpPower           = myHum.JumpPower
        myHum.WalkSpeed        = 0
        myHum.JumpPower        = 0
        myHum.PlatformStand    = true
    end

    -- 3. Teleport OUR character directly inside the target (same CFrame = overlap)
    myHRP.CFrame = targHRP.CFrame

    -- tiny yield so the engine registers the new position before force is applied
    task.wait()

    -- 4. Pick a random horizontal direction for variety
    local sx  = math.random(0, 1) == 0 and 1 or -1
    local sz  = math.random(0, 1) == 0 and 1 or -1
    local vel = Vector3.new(
        sx * math.random(10000, 14000),
        math.random(5000,  8000),
        sz * math.random(10000, 14000)
    )

    -- Remove any leftover BodyMovers on ourselves
    for _, v in ipairs(myHRP:GetChildren()) do
        if v:IsA("BodyVelocity") or v:IsA("BodyForce")
        or v:IsA("BodyAngularVelocity") then
            v:Destroy()
        end
    end

    -- 5. Apply force to OURSELVES  → physics overlap pushes target
    local bv      = Instance.new("BodyVelocity")
    bv.Name       = "FLING_BV"
    bv.Velocity   = vel
    bv.MaxForce   = Vector3.new(1e9, 1e9, 1e9)
    bv.P          = 1e9
    bv.Parent     = myHRP

    -- Raw velocity set as well for good measure
    pcall(function() myHRP.AssemblyLinearVelocity = vel end)

    -- 6. After 1 frame the collision has been processed — clean up and go home
    task.wait()
    pcall(function() bv:Destroy() end)

    -- Restore humanoid
    if myHum then
        myHum.PlatformStand = false
        myHum.WalkSpeed     = oldWalkSpeed
        myHum.JumpPower     = oldJumpPower
    end

    -- Aggressively teleport back (3 frames) to fight any residual velocity
    for i = 1, 3 do
        restorePosition()
        task.wait()
    end
end

-- ════════════════════════════════════════════════
--  FLING ALL (cycles through all players)
-- ════════════════════════════════════════════════
local flingAllStatusCb = nil

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
                    task.wait(0.45)
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
--  ANTI-FLING SHIELD (protect ourselves)
-- ════════════════════════════════════════════════
local function enableAntiFling()
    if antiFlingConn then return end
    antiFlingConn = RunService.Heartbeat:Connect(function()
        local hrp = getHRP(LocalPlayer)
        local hum = getHumanoid(LocalPlayer)
        if not hrp or not hum then return end
        -- Destroy injected movers
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
--  GUI SETUP
-- ════════════════════════════════════════════════
local oldGui = LocalPlayer.PlayerGui:FindFirstChild("FlingGUI_v32")
if oldGui then oldGui:Destroy() end

local ScreenGui          = Instance.new("ScreenGui")
ScreenGui.Name           = "FlingGUI_v32"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
ScreenGui.Parent         = LocalPlayer.PlayerGui

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

-- ── Factories ─────────────────────────────────
local function mkCorner(r, p)
    local u = Instance.new("UICorner")
    u.CornerRadius = UDim.new(0, r)
    u.Parent = p
    return u
end

local function mkStroke(parent, colorA, colorB, thickness)
    local s = Instance.new("UIStroke")
    s.Thickness = thickness or 1.5
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    local g = Instance.new("UIGradient")
    g.Color    = ColorSequence.new({
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
    f.ZIndex           = z   or 5
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
    local origSz = sz or UDim2.new(1, 0, 0, 38)
    b.MouseEnter:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.13), {
            BackgroundTransparency = 0.18,
            Size = UDim2.new(origSz.X.Scale, origSz.X.Offset+2,
                             origSz.Y.Scale, origSz.Y.Offset+2),
        }):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.13), {
            BackgroundTransparency = 0, Size = origSz,
        }):Play()
    end)
    b.MouseButton1Down:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.07), {
            BackgroundTransparency = 0.35,
            Size = UDim2.new(origSz.X.Scale, origSz.X.Offset-2,
                             origSz.Y.Scale, origSz.Y.Offset-2),
        }):Play()
    end)
    b.MouseButton1Up:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.1), {
            BackgroundTransparency = 0, Size = origSz,
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
local mainStroke = mkStroke(Main, C.accent1, C.accent2, 1.8)

-- ── Title bar ─────────────────────────────────
local TBar = mkFrame(C.panel, UDim2.new(1,0,0,54), UDim2.new(0,0,0,0), 18, 6, Main)
mkFrame(C.panel, UDim2.new(1,0,0,18), UDim2.new(0,0,1,-18), 0, 6, TBar)
do
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(28,14,58)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(10,18,48)),
    })
    g.Rotation = 90
    g.Parent   = TBar
end

mkLabel("⚡",
    UDim2.new(0,36,0,36), UDim2.new(0,12,0.5,-18),
    22, C.text, Enum.Font.GothamBold,
    Enum.TextXAlignment.Center, Enum.TextYAlignment.Center,
    false, 7, TBar
)

local titLbl = mkLabel("FLING  SCRIPT",
    UDim2.new(0,200,0,36), UDim2.new(0,52,0.5,-18),
    17, C.text, Enum.Font.GothamBold,
    Enum.TextXAlignment.Left, Enum.TextYAlignment.Center,
    false, 7, TBar
)
do
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(210,145,255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(100,210,255)),
    })
    g.Parent = titLbl
end

mkLabel("v3.2",
    UDim2.new(0,44,0,18), UDim2.new(1,-56,0.5,-9),
    11, C.sub, Enum.Font.Gotham,
    Enum.TextXAlignment.Center, Enum.TextYAlignment.Center,
    false, 7, TBar
)

-- Close
do
    local b = Instance.new("TextButton")
    b.Size             = UDim2.new(0,28,0,28)
    b.Position         = UDim2.new(1,-38,0.5,-14)
    b.BackgroundColor3 = Color3.fromRGB(200,50,70)
    b.TextColor3       = Color3.new(1,1,1)
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

-- Minimise
local minimized = false
do
    local b = Instance.new("TextButton")
    b.Size             = UDim2.new(0,28,0,28)
    b.Position         = UDim2.new(1,-70,0.5,-14)
    b.BackgroundColor3 = Color3.fromRGB(215,145,25)
    b.TextColor3       = Color3.new(1,1,1)
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
        TweenService:Create(Main, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
            Size = minimized and UDim2.new(0,W,0,54) or UDim2.new(0,W,0,H)
        }):Play()
    end)
end

-- Drag
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
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
                      or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - ds
            Main.Position = UDim2.new(sp.X.Scale, sp.X.Offset+d.X,
                                      sp.Y.Scale, sp.Y.Offset+d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

-- ── Scrollable content ────────────────────────
local Content = Instance.new("ScrollingFrame")
Content.Size                   = UDim2.new(1,-20,1,-62)
Content.Position               = UDim2.new(0,10,0,58)
Content.BackgroundTransparency = 1
Content.BorderSizePixel        = 0
Content.ScrollBarThickness     = 0
Content.CanvasSize             = UDim2.new(0,0,0,0)
Content.AutomaticCanvasSize    = Enum.AutomaticSize.Y
Content.ZIndex                 = 5
Content.Parent                 = Main

local cLayout = Instance.new("UIListLayout")
cLayout.Padding       = UDim.new(0, 8)
cLayout.SortOrder     = Enum.SortOrder.LayoutOrder
cLayout.FillDirection = Enum.FillDirection.Vertical
cLayout.Parent        = Content

-- ════════════════════════════════════════════════
--  STATUS BAR
-- ════════════════════════════════════════════════
local statCard = mkFrame(C.card, UDim2.new(1,0,0,36), UDim2.new(0,0,0,0), 9, 5, Content)
statCard.LayoutOrder = 0
mkStroke(statCard, C.accent1, C.accent2, 1)

local statDot = mkFrame(C.success,
    UDim2.new(0,8,0,8), UDim2.new(0,10,0.5,-4),
    99, 6, statCard
)
local statLbl = mkLabel("Idle — Ready",
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
--  ANTI-FLING SHIELD CARD
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

local togBg = mkFrame(Color3.fromRGB(38,38,58),
    UDim2.new(0,48,0,24), UDim2.new(1,-58,0.5,-12),
    99, 6, shCard
)
local togKnob = mkFrame(Color3.fromRGB(150,150,170),
    UDim2.new(0,20,0,20), UDim2.new(0,2,0.5,-10),
    99, 7, togBg
)
do
    local tb = Instance.new("TextButton")
    tb.BackgroundTransparency = 1
    tb.Size   = UDim2.new(1,0,1,0)
    tb.Text   = ""
    tb.ZIndex = 8
    tb.Parent = togBg
    tb.MouseButton1Click:Connect(function()
        antiFlingEnabled = not antiFlingEnabled
        if antiFlingEnabled then
            enableAntiFling()
            TweenService:Create(togBg,   TweenInfo.new(0.2), { BackgroundColor3 = C.success }):Play()
            TweenService:Create(togKnob, TweenInfo.new(0.2), {
                Position = UDim2.new(0,26,0.5,-10),
                BackgroundColor3 = Color3.new(1,1,1),
            }):Play()
            setStatus("Shield ON — You are protected", C.success)
        else
            disableAntiFling()
            TweenService:Create(togBg,   TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(38,38,58) }):Play()
            TweenService:Create(togKnob, TweenInfo.new(0.2), {
                Position = UDim2.new(0,2,0.5,-10),
                BackgroundColor3 = Color3.fromRGB(150,150,170),
            }):Play()
            setStatus("Idle — Ready", C.success)
        end
    end)
end

-- ════════════════════════════════════════════════
--  PLAYER LIST
-- ════════════════════════════════════════════════
local listHdr = mkFrame(Color3.fromRGB(0,0,0),
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

local scrollOuter = mkFrame(C.card, UDim2.new(1,0,0,195), UDim2.new(0,0,0,0), 10, 5, Content)
scrollOuter.LayoutOrder = 3
mkStroke(scrollOuter, C.border, C.border, 1)

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
pLayout.Padding   = UDim.new(0,4)
pLayout.SortOrder = Enum.SortOrder.Name
pLayout.Parent    = pScroll

local pPad = Instance.new("UIPadding")
pPad.PaddingLeft   = UDim.new(0,4)
pPad.PaddingRight  = UDim.new(0,4)
pPad.PaddingTop    = UDim.new(0,4)
pPad.PaddingBottom = UDim.new(0,4)
pPad.Parent        = pScroll

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

    local av = Instance.new("ImageLabel")
    av.Size             = UDim2.new(0,32,0,32)
    av.Position         = UDim2.new(0,5,0.5,-16)
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
        ca.Size   = UDim2.new(1,0,1,0)
        ca.Text   = ""
        ca.ZIndex = 9
        ca.Parent = row
        ca.MouseButton1Click:Connect(function()
            if selectedPlayers[player] then
                selectedPlayers[player] = nil
            else
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
    rowMap          = {}
    selectedPlayers = {}
    selHint.Text    = "Select up to 3"
    for _, p in ipairs(Players:GetPlayers()) do addRow(p) end
    setStatus("Refreshed — " .. #Players:GetPlayers() .. " player(s)", C.accent2)
end

Players.PlayerAdded:Connect(function(p) task.wait(0.3); addRow(p) end)
Players.PlayerRemoving:Connect(removeRow)
refreshList()

-- ════════════════════════════════════════════════
--  BUTTONS
-- ════════════════════════════════════════════════
local row1 = mkFrame(Color3.fromRGB(0,0,0),
    UDim2.new(1,0,0,40), UDim2.new(0,0,0,0), 0, 5, Content)
row1.BackgroundTransparency = 1
row1.LayoutOrder = 4

local refreshBtn = mkBtn("🔄  Refresh",
    C.card,
    Color3.fromRGB(28,28,58), Color3.fromRGB(18,18,40),
    C.text,
    UDim2.new(0.48,0,1,0), UDim2.new(0,0,0,0),
    10, 13, 6, row1
)
mkStroke(refreshBtn, C.border, C.accent1, 1)

local flingSelBtn = mkBtn("⚡  Fling Selected",
    C.accent1,
    Color3.fromRGB(140,60,255), Color3.fromRGB(88,38,178),
    C.text,
    UDim2.new(0.5,0,1,0), UDim2.new(0.5,0,0,0),
    10, 13, 6, row1
)
mkStroke(flingSelBtn, C.accent1, C.accent2, 1.2)

local row2 = mkFrame(Color3.fromRGB(0,0,0),
    UDim2.new(1,0,0,40), UDim2.new(0,0,0,0), 0, 5, Content)
row2.BackgroundTransparency = 1
row2.LayoutOrder = 5

local flingAllBtn = mkBtn("💀  Fling All",
    C.danger,
    Color3.fromRGB(255,60,90), Color3.fromRGB(178,28,55),
    C.text,
    UDim2.new(0.48,0,1,0), UDim2.new(0,0,0,0),
    10, 13, 6, row2
)
mkStroke(flingAllBtn, C.danger, Color3.fromRGB(255,135,55), 1.2)

local stopBtn = mkBtn("🛑  Stop",
    C.warning,
    Color3.fromRGB(255,195,45), Color3.fromRGB(200,138,18),
    Color3.fromRGB(20,10,0),
    UDim2.new(0.5,0,1,0), UDim2.new(0.5,0,0,0),
    10, 13, 6, row2
)
mkStroke(stopBtn, C.warning, Color3.fromRGB(255,118,18), 1.2)

-- Info footer
local infoCard = mkFrame(C.card, UDim2.new(1,0,0,52), UDim2.new(0,0,0,0), 9, 5, Content)
infoCard.LayoutOrder = 6
mkStroke(infoCard, C.border, C.border, 1)
local infoPad = Instance.new("UIPadding")
infoPad.PaddingLeft   = UDim.new(0,10)
infoPad.PaddingRight  = UDim.new(0,10)
infoPad.PaddingTop    = UDim.new(0,6)
infoPad.PaddingBottom = UDim.new(0,6)
infoPad.Parent        = infoCard
mkLabel(
    "⚡ Tap players to select (max 3)  ·  Fling Selected to launch\n"
 .. "💀 Fling All cycles all players  ·  🛑 Stop returns you home",
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
            task.wait(0.5)
        end
        setStatus("Done — Fling complete ✓", C.success)
    end)
end)

flingAllBtn.MouseButton1Click:Connect(function()
    if flingAllActive then
        setStatus("Fling All already running!", C.warning)
        return
    end
    setStatus("Fling All — ACTIVE", C.danger)
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
    setStatus("Stopped — Returned home ✓", C.success)
end)

-- ════════════════════════════════════════════════
--  OPEN ANIMATION
-- ════════════════════════════════════════════════
Main.Size                  = UDim2.new(0,W,0,0)
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

print("[FlingScript v3.2] Loaded ✅  — Physics overlap fling active")
