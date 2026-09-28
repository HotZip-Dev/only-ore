-- OnlyOres.lua
-- Records every ore spawn point you mine (saved in OnlyOresDB, i.e.
-- WTF/Account/<acct>/SavedVariables/OnlyOres.lua) and draws each one as a pin on
-- the world map. Hovering a pin shows which ores have appeared there and how
-- long ago you last mined it.
--
-- Data model (DB_VERSION 2): one entry per spawn POINT, not per ore type,
-- because Classic spawn points roll between ore types (Tin/Silver, Iron/Gold).
--   OnlyOresDB.nodes[mapID] = {
--     { x, y, types = { ["Tin Vein"] = visits, ... }, lastName,
--       first, last, visits, taps }, ...
--   }
-- A "visit" groups repeated taps on the same vein (Forever veins take 1-4 hits).

OnlyOres = OnlyOres or {}
local OO = OnlyOres

local DB_VERSION = 2
local MINING_SPELL_ID = 2575
local PIN_TEMPLATE = "OnlyOresPinTemplate"
local MERGE_DISTANCE = 0.005 -- map-fraction; roughly 15-20 yards on a typical zone map
local VISIT_WINDOW = 120     -- seconds; re-tapping the same vein within this is one visit
local DEFAULT_ICON = "Interface\\Icons\\Trade_Mining"

-- Node name -> ore item ID, used to pick the pin icon. Checked in order with a
-- plain substring match, so more specific names must come before the names they
-- contain ("Truesilver" before "Silver", "Dark Iron" before "Iron"). This also
-- covers variants like "Ooze Covered Silver Vein".
-- The color tints the minimap ring for that ore.
local ORE_ITEMS = {
    { "Truesilver",  7911,  { 0.75, 0.90, 1.00 } }, -- Truesilver Ore
    { "Dark Iron",   11370, { 0.70, 0.20, 0.15 } }, -- Dark Iron Ore
    { "Thorium",     10620, { 0.35, 0.90, 0.45 } }, -- Thorium Ore
    { "Mithril",     3858,  { 0.45, 0.80, 0.80 } }, -- Mithril Ore
    { "Gold",        2776,  { 1.00, 0.80, 0.10 } }, -- Gold Ore
    { "Iron",        2772,  { 0.65, 0.55, 0.50 } }, -- Iron Ore
    { "Silver",      2775,  { 0.90, 0.90, 0.95 } }, -- Silver Ore
    { "Tin",         2771,  { 0.60, 0.65, 0.70 } }, -- Tin Ore
    { "Copper",      2770,  { 0.95, 0.55, 0.25 } }, -- Copper Ore
    { "Incendicite", 3340,  { 1.00, 0.35, 0.20 } }, -- Incendicite Ore
    { "Bloodstone",  4278,  { 0.85, 0.15, 0.25 } }, -- Lesser Bloodstone Ore
    { "Indurium",    5833,  { 0.30, 0.70, 0.65 } }, -- Indurium Ore
    { "Obsidian",    22202, { 0.60, 0.40, 0.85 } }, -- Small Obsidian Shard
}
local DEFAULT_RING_COLOR = { 1, 1, 1 }

local function ColorForNode(nodeName)
    if nodeName then
        for _, entry in ipairs(ORE_ITEMS) do
            if string.find(nodeName, entry[1], 1, true) then return entry[3] end
        end
    end
    return DEFAULT_RING_COLOR
end

local pendingCasts = {} -- castGUID -> node name (from UNIT_SPELLCAST_SENT)
local iconCache = {}    -- node name -> icon

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100OnlyOres:|r " .. msg)
end

-- Addons can't write files directly, so debug output is appended to
-- OnlyOresDB.log, which the client writes to SavedVariables\OnlyOres.lua on
-- /reload or logout. Capped so the file doesn't grow forever.
local LOG_MAX = 1000

-- Always append to the saved log file, regardless of debug mode.
local function WriteLog(msg)
    if not (OnlyOresDB and OnlyOresDB.log) then return end
    local log = OnlyOresDB.log
    table.insert(log, date("%Y-%m-%d %H:%M:%S") .. "  " .. msg)
    while #log > LOG_MAX do table.remove(log, 1) end
end

-- Log to the saved file only (for noisy lines), when debug is on.
local function Trace(msg)
    if OnlyOresDB and OnlyOresDB.debug then WriteLog(msg) end
end

-- Log to the saved file and echo to chat.
local function Debug(msg)
    if not (OnlyOresDB and OnlyOresDB.debug) then return end
    Trace(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff888888OnlyOres debug:|r " .. msg)
end

local function FormatAgo(t)
    local d = math.max(0, time() - t)
    if d < 60 then return "just now" end
    local days = math.floor(d / 86400)
    local hours = math.floor((d % 86400) / 3600)
    local mins = math.floor((d % 3600) / 60)
    if days > 0 then return string.format("%dd %dh ago", days, hours) end
    if hours > 0 then return string.format("%dh %dm ago", hours, mins) end
    return string.format("%dm ago", mins)
end

local function GetSpellNameCompat(spellID)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellID) end
    if GetSpellInfo then return (GetSpellInfo(spellID)) end
end

local function IsMiningSpell(spellID)
    if spellID == MINING_SPELL_ID then return true end
    local name = GetSpellNameCompat(spellID)
    return name ~= nil and name == GetSpellNameCompat(MINING_SPELL_ID) -- other ranks, any locale
end

local function IconForNode(nodeName)
    if not nodeName then return DEFAULT_ICON end
    local cached = iconCache[nodeName]
    if cached then return cached end
    local icon
    for _, entry in ipairs(ORE_ITEMS) do
        if string.find(nodeName, entry[1], 1, true) then
            if C_Item and C_Item.GetItemIconByID then
                icon = C_Item.GetItemIconByID(entry[2])
            elseif GetItemIcon then
                icon = GetItemIcon(entry[2])
            end
            break
        end
    end
    icon = icon or DEFAULT_ICON
    iconCache[nodeName] = icon
    return icon
end

local function IsIgnored(nodeName)
    return nodeName and OnlyOresDB.ignore[string.lower(nodeName)] or false
end

local function RefreshMap()
    if OO.provider and WorldMapFrame and WorldMapFrame:IsShown() then
        OO.provider:RefreshAllData()
    end
end

---------------------------------------------------------------------------
-- Saved data setup / migration
---------------------------------------------------------------------------

local function MigrateDB()
    local db = OnlyOresDB
    if (db.version or 1) < 2 then
        -- v1 stored one entry per ore name: { name, x, y, first, last, count }
        for _, list in pairs(db.nodes) do
            for _, node in ipairs(list) do
                if node.name then
                    local n = node.count or 1
                    node.types = { [node.name] = n }
                    node.lastName = node.name
                    node.visits, node.taps = n, n
                    node.name, node.count = nil, nil
                end
            end
        end
    end
    db.version = DB_VERSION
end

local function InitDB()
    OnlyOresDB = OnlyOresDB or {}
    OnlyOresDB.nodes = OnlyOresDB.nodes or {}
    OnlyOresDB.ignore = OnlyOresDB.ignore or {}
    OnlyOresDB.log = OnlyOresDB.log or {}
    MigrateDB()
    Trace("---- session start ----")
end

---------------------------------------------------------------------------
-- Recording nodes
---------------------------------------------------------------------------

-- Nearest saved spawn point within MERGE_DISTANCE, regardless of ore type.
local function FindSpawnPoint(list, x, y)
    local best, bestDist = nil, MERGE_DISTANCE * MERGE_DISTANCE
    for _, node in ipairs(list) do
        local dx, dy = node.x - x, node.y - y
        local dist = dx * dx + dy * dy
        if dist <= bestDist then best, bestDist = node, dist end
    end
    return best
end

local function RecordNode(nodeName)
    if IsIgnored(nodeName) then
        Debug("ignored '" .. nodeName .. "'")
        return
    end

    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then Debug("no mapID; not recorded"); return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then Debug("no position on map " .. mapID .. " (instance?); not recorded"); return end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then Debug("zero position; not recorded"); return end

    local list = OnlyOresDB.nodes[mapID]
    if not list then list = {}; OnlyOresDB.nodes[mapID] = list end

    local now = time()
    local node = FindSpawnPoint(list, x, y)
    local coords = string.format("map %d (%.1f, %.1f)", mapID, x * 100, y * 100)

    if node then
        node.taps = (node.taps or 0) + 1
        if node.lastName == nodeName and (now - (node.last or 0)) <= VISIT_WINDOW then
            Debug(string.format("tap %d on same visit: %s at %s", node.taps, nodeName, coords))
        else
            node.visits = (node.visits or 0) + 1
            node.types[nodeName] = (node.types[nodeName] or 0) + 1
            node.lastName = nodeName
            Debug(string.format("new visit (#%d): %s at %s", node.visits, nodeName, coords))
        end
        node.last = now
    else
        table.insert(list, {
            x = x, y = y,
            types = { [nodeName] = 1 },
            lastName = nodeName,
            first = now, last = now,
            visits = 1, taps = 1,
        })
        Print("Recorded new spawn point: " .. nodeName)
        Debug("new spawn point at " .. coords)
    end
    RefreshMap()
end

-- Remove one ore type from every spawn point; drop points left with no types.
local function ForgetNodeType(nodeName)
    local key = string.lower(nodeName)
    local removed = 0
    for mapID, list in pairs(OnlyOresDB.nodes) do
        for i = #list, 1, -1 do
            local node = list[i]
            for name in pairs(node.types) do
                if string.lower(name) == key then
                    node.types[name] = nil
                    removed = removed + 1
                end
            end
            if not next(node.types) then
                table.remove(list, i)
            elseif not node.types[node.lastName] then
                -- last-seen type was removed; fall back to the most common remaining one
                local bestName, bestCount = nil, -1
                for name, count in pairs(node.types) do
                    if count > bestCount then bestName, bestCount = name, count end
                end
                node.lastName = bestName
            end
        end
    end
    return removed
end

---------------------------------------------------------------------------
-- Map pin
---------------------------------------------------------------------------

OnlyOresPinMixin = CreateFromMixins(MapCanvasPinMixin or {})

local function ShowTooltip(pin)
    local node = pin.node
    if not node then return end
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(node.lastName or "Ore spawn point", 1, 0.82, 0)
    GameTooltip:AddLine("Last mined: " .. FormatAgo(node.last), 1, 1, 1)
    GameTooltip:AddLine(string.format("Visits: %d (%d taps)", node.visits or 1, node.taps or 1), 0.7, 0.7, 0.7)

    -- More than one ore type seen here? List them, most frequent first.
    local names = {}
    for name in pairs(node.types) do table.insert(names, name) end
    if #names > 1 then
        table.sort(names, function(a, b) return node.types[a] > node.types[b] end)
        GameTooltip:AddLine("Seen here:", 0.7, 0.7, 0.7)
        for _, name in ipairs(names) do
            GameTooltip:AddLine(string.format("  %s x%d", name, node.types[name]), 0.9, 0.9, 0.9)
        end
    end

    GameTooltip:AddLine("Left-click: set waypoint", 0.5, 0.8, 0.5)
    GameTooltip:AddLine("Shift+Right-click: forget spawn point", 0.8, 0.4, 0.4)
    GameTooltip:Show()
end

-- MapCanvas owns this pin's mouse scripts: it asserts that OnEnter/OnLeave are
-- NOT set on the frame, then routes them to OnMouseEnter/OnMouseLeave, and
-- routes clicks to OnClick(button). It also calls OnLoad itself on first
-- acquire, so the XML template must not have an <OnLoad> script.
function OnlyOresPinMixin:OnLoad()
    -- Without a frame level type, pins get PIN_FRAME_LEVEL_DEFAULT, which the
    -- world map stacks BELOW its own layers, so the explored-area artwork
    -- (PIN_FRAME_LEVEL_MAP_EXPLORATION) hides them. AREA_POI sits above the map
    -- art but below quests and the player arrow.
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    if self.SetScalingLimits then self:SetScalingLimits(1, 1.0, 1.2) end

    -- keep "time since" live while the tooltip is open
    self:SetScript("OnUpdate", function(pin, dt)
        if not pin.hovering then return end
        pin.elapsed = (pin.elapsed or 0) + dt
        if pin.elapsed >= 1 then pin.elapsed = 0; ShowTooltip(pin) end
    end)
end

function OnlyOresPinMixin:OnMouseEnter()
    self.hovering, self.elapsed = true, 0
    ShowTooltip(self)
end

function OnlyOresPinMixin:OnMouseLeave()
    self.hovering = false
    GameTooltip:Hide()
end

function OnlyOresPinMixin:OnClick(button)
    if not self.node then return end
    if button == "LeftButton" then
        if C_Map.SetUserWaypoint and UiMapPoint then
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(self.mapID, self.node.x, self.node.y))
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            end
            Print("Waypoint set to " .. (self.node.lastName or "spawn point"))
        end
    elseif button == "RightButton" and IsShiftKeyDown() then
        local list = OnlyOresDB.nodes[self.mapID]
        for i, n in ipairs(list or {}) do
            if n == self.node then table.remove(list, i); break end
        end
        GameTooltip:Hide()
        OO.provider:RefreshAllData()
    end
end

function OnlyOresPinMixin:OnReleased()
    self.hovering, self.node = false, nil
end

function OnlyOresPinMixin:OnAcquired(node, mapID)
    self.node, self.mapID = node, mapID
    self.Icon:SetTexture(IconForNode(node.lastName))
    self:SetPosition(node.x, node.y)
    Trace(string.format("pin %s at (%.3f, %.3f): shown=%s visible=%s level=%d scale=%.2f alpha=%.2f size=%.0fx%.0f",
        tostring(node.lastName), node.x, node.y, tostring(self:IsShown()), tostring(self:IsVisible()),
        self:GetFrameLevel(), self:GetEffectiveScale(), self:GetEffectiveAlpha(), self:GetSize()))
end

---------------------------------------------------------------------------
-- Data provider
---------------------------------------------------------------------------

local Provider = CreateFromMixins(MapCanvasDataProviderMixin or {})

function Provider:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
end

function Provider:RefreshAllData()
    self:RemoveAllData()
    local mapID = self:GetMap():GetMapID()
    local list = mapID and OnlyOresDB.nodes[mapID]
    Trace(string.format("RefreshAllData: map %s, %d saved points, hidden=%s",
        tostring(mapID), list and #list or 0, tostring(OnlyOresDB.hidden)))
    if OnlyOresDB.hidden or not list then return end
    for _, node in ipairs(list) do
        -- Errors inside the map's provider loop can be swallowed, so catch and log them.
        local ok, err = pcall(self:GetMap().AcquirePin, self:GetMap(), PIN_TEMPLATE, node, mapID)
        if not ok then Debug("AcquirePin failed: " .. tostring(err)) end
    end
end

function Provider:OnMapChanged()
    self:RefreshAllData()
end

local function RegisterProvider()
    if OO.provider then return end
    if not WorldMapFrame then Trace("RegisterProvider: WorldMapFrame missing"); return end
    OO.provider = Provider
    WorldMapFrame:AddDataProvider(Provider)
    WorldMapFrame:HookScript("OnShow", function(map)
        Trace(string.format("world map shown: map %s, provider registered=%s",
            tostring(map:GetMapID()), tostring(map.dataProviders and map.dataProviders[Provider] or false)))
    end)
    Trace("RegisterProvider: added to WorldMapFrame")
end

-- /onlyores status: immediate chat diagnostics for "why are there no pins?"
local function PrintStatus()
    -- Chat can't be copied, so every status line also goes to the log file.
    local Print = function(msg) Print(msg); WriteLog("[status] " .. msg) end
    Print("---- status ----")
    Print("WorldMapFrame exists: " .. tostring(WorldMapFrame ~= nil))
    Print("Provider registered: " .. tostring(OO.provider ~= nil and WorldMapFrame
        and WorldMapFrame.dataProviders and WorldMapFrame.dataProviders[Provider] or false))
    local playerMap = C_Map.GetBestMapForUnit("player")
    Print(string.format("You are on map %s; %d points saved there.",
        tostring(playerMap), playerMap and OnlyOresDB.nodes[playerMap] and #OnlyOresDB.nodes[playerMap] or 0))
    if WorldMapFrame and WorldMapFrame:IsShown() then
        local shownMap = WorldMapFrame:GetMapID()
        Print("World map is open on map " .. tostring(shownMap) .. "; forcing a refresh...")
        Provider:RefreshAllData()
        local count = 0
        local ok = pcall(function()
            for pin in WorldMapFrame:EnumeratePinsByTemplate(PIN_TEMPLATE) do
                count = count + 1
                if count == 1 then
                    Print(string.format("First pin: shown=%s visible=%s level=%d alpha=%.2f scale=%.2f",
                        tostring(pin:IsShown()), tostring(pin:IsVisible()), pin:GetFrameLevel(),
                        pin:GetEffectiveAlpha(), pin:GetEffectiveScale()))
                    local icon = pin.Icon
                    Print(string.format("Icon: exists=%s texture=%s shown=%s size=%.0fx%.0f layer=%s",
                        tostring(icon ~= nil), tostring(icon and icon:GetTexture()),
                        tostring(icon and icon:IsShown()), icon and icon:GetWidth() or 0,
                        icon and icon:GetHeight() or 0, tostring(icon and icon:GetDrawLayer())))
                    Print("IconForNode(Copper Vein) = " .. tostring(IconForNode("Copper Vein")))
                    local canvas = WorldMapFrame:GetCanvas()
                    local cx, cy = pin:GetCenter()
                    Print(string.format("Pin center=(%s, %s) parentIsCanvas=%s",
                        tostring(cx), tostring(cy), tostring(pin:GetParent() == canvas)))
                    local sc = WorldMapFrame.ScrollContainer
                    if sc then
                        local l, b, w, h = sc:GetRect()
                        local s = pin:GetEffectiveScale() / sc:GetEffectiveScale()
                        Print(string.format("Map viewport rect: left=%.0f bottom=%.0f w=%.0f h=%.0f (pin center in same units: %.0f, %.0f)",
                            l or 0, b or 0, w or 0, h or 0, (cx or 0) * s, (cy or 0) * s))
                    end
                end
            end
        end)
        Print(ok and ("Active OnlyOres pins on the map: " .. count) or "Couldn't enumerate pins.")
    else
        Print("Open the world map (M) and run /onlyores status again for pin details.")
    end
    Print("Pins hidden setting: " .. tostring(OnlyOresDB.hidden))
end

---------------------------------------------------------------------------
-- Minimap pins
---------------------------------------------------------------------------
-- The minimap has no pin framework like the world map, so we place icons
-- ourselves: convert player + node positions to world yards, scale by how many
-- yards the minimap currently shows, rotate if "Rotate Minimap" is on, and
-- clamp out-of-range nodes to the edge (like party member arrows).

local MINIMAP_UPDATE_INTERVAL = 0.05 -- seconds (~20 fps)
local MINIMAP_EDGE_COUNT = 3         -- only the N nearest out-of-range nodes get edge icons
local MINIMAP_RING_SIZE = 20 -- hollow ring, big enough for a Find Minerals dot to show inside
local MINIMAP_EDGE_SIZE = 11
local RING_TEXTURE = "Interface\\AddOns\\OnlyOres\\Ring" -- white ring w/ dark outline; tinted per ore

-- Minimap DIAMETER in yards per zoom level (0-5). Same values HereBeDragons
-- uses; the client doesn't expose them.
local MINIMAP_YARDS = {
    indoor  = { [0] = 300, 240, 180, 120, 80, 50 },
    outdoor = { [0] = 466 + 2/3, 400, 333 + 1/3, 266 + 2/3, 200, 133 + 1/3 },
}

-- World position cache: node table -> { instanceID, north, west }. Nodes never
-- move, so compute once. Weak keys so forgotten nodes get collected.
local worldPosCache = setmetatable({}, { __mode = "k" })

-- C_Map world vectors: x grows NORTH, y grows WEST (so map (0,0) = top-left
-- has the largest x and y).
local function WorldPos(mapID, x, y)
    local instanceID, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    if not pos then return nil end
    local north, west = pos:GetXY()
    return instanceID, north, west
end

local function NodeWorldPos(mapID, node)
    local cached = worldPosCache[node]
    if not cached then
        local instanceID, north, west = WorldPos(mapID, node.x, node.y)
        cached = { instanceID = instanceID or -1, north = north or 0, west = west or 0 }
        worldPosCache[node] = cached
    end
    return cached
end

local minimapPins = {}
local minimapRow = {} -- scratch list reused every update

local function ShowMinimapTooltip(pin)
    local node = pin.node
    if not node then return end
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(node.lastName or "Ore spawn point", 1, 0.82, 0)
    GameTooltip:AddLine(string.format("%d yards away", pin.distance or 0), 1, 1, 1)
    GameTooltip:AddLine("Last mined: " .. FormatAgo(node.last), 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function GetMinimapPin(i)
    local pin = minimapPins[i]
    if pin then return pin end
    pin = CreateFrame("Frame", nil, Minimap)
    pin:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    pin.Icon = pin:CreateTexture(nil, "ARTWORK")   -- ore icon, used on the edge
    pin.Icon:SetAllPoints()
    pin.Ring = pin:CreateTexture(nil, "ARTWORK")   -- hollow ring, used in range so the
    pin.Ring:SetAllPoints()                        -- minimap's own tracking dot stays visible
    pin.Ring:SetTexture(RING_TEXTURE)
    pin.Distance = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pin.Distance:SetPoint("TOP", pin, "BOTTOM", 0, -1)
    pin.Distance:SetShadowOffset(1, -1)
    pin:EnableMouse(true)
    pin:SetScript("OnEnter", ShowMinimapTooltip)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    minimapPins[i] = pin
    return pin
end

local function HideMinimapPins(fromIndex)
    for i = fromIndex or 1, #minimapPins do minimapPins[i]:Hide() end
end

local function UpdateMinimapPins()
    if OnlyOresDB.hidden or OnlyOresDB.minimapHidden then HideMinimapPins(); return end

    local playerMap = C_Map.GetBestMapForUnit("player")
    local pos = playerMap and C_Map.GetPlayerMapPosition(playerMap, "player")
    if not pos then HideMinimapPins(); return end -- instances etc.
    local px, py = pos:GetXY()
    local instanceID, pNorth, pWest = WorldPos(playerMap, px, py)
    if not instanceID then HideMinimapPins(); return end

    -- Yards -> minimap pixels
    local zoom = Minimap:GetZoom()
    local diameter = (IsIndoors() and MINIMAP_YARDS.indoor or MINIMAP_YARDS.outdoor)[zoom] or 466
    local radiusPx = Minimap:GetWidth() / 2
    local pxPerYard = radiusPx / (diameter / 2)
    local square = GetMinimapShape and GetMinimapShape() == "SQUARE"

    local rotate = GetCVar("rotateMinimap") == "1"
    local facing = rotate and (GetPlayerFacing() or 0) or 0
    local cosF, sinF = math.cos(facing), math.sin(facing)

    -- Collect every node on this continent with its screen offset + distance.
    wipe(minimapRow)
    for mapID, list in pairs(OnlyOresDB.nodes) do
        for _, node in ipairs(list) do
            local w = NodeWorldPos(mapID, node)
            if w.instanceID == instanceID then
                local east = pWest - w.west  -- west grows westward, so flip for east
                local north = w.north - pNorth
                local dist = math.sqrt(east * east + north * north)
                -- Rotate so the player's facing points up (facing is CCW from north).
                local sx = east * cosF + north * sinF
                local sy = -east * sinF + north * cosF
                table.insert(minimapRow, { node = node, dist = dist, sx = sx * pxPerYard, sy = sy * pxPerYard })
            end
        end
    end
    table.sort(minimapRow, function(a, b) return a.dist < b.dist end)

    local used, edgeShown = 0, 0
    local edgeLimit = radiusPx - MINIMAP_EDGE_SIZE / 2 - 2
    for _, row in ipairs(minimapRow) do
        local sx, sy = row.sx, row.sy
        local reach = square and math.max(math.abs(sx), math.abs(sy)) or math.sqrt(sx * sx + sy * sy)
        local onEdge = reach > edgeLimit
        if not onEdge or edgeShown < MINIMAP_EDGE_COUNT then
            used = used + 1
            local pin = GetMinimapPin(used)
            pin.node, pin.distance = row.node, row.dist
            if onEdge then
                edgeShown = edgeShown + 1
                local k = edgeLimit / reach -- pull back onto the rim, same direction
                sx, sy = sx * k, sy * k
                pin:SetSize(MINIMAP_EDGE_SIZE, MINIMAP_EDGE_SIZE)
                pin:SetAlpha(0.75)
                pin.Icon:SetTexture(IconForNode(row.node.lastName))
                pin.Icon:Show()
                pin.Ring:Hide()
                pin.Distance:SetFormattedText("%dy", row.dist)
                pin.Distance:Show()
            else
                pin:SetSize(MINIMAP_RING_SIZE, MINIMAP_RING_SIZE)
                pin:SetAlpha(1)
                local c = ColorForNode(row.node.lastName)
                pin.Ring:SetVertexColor(c[1], c[2], c[3])
                pin.Ring:Show()
                pin.Icon:Hide()
                pin.Distance:Hide()
            end
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", Minimap, "CENTER", sx, sy)
            pin:Show()
            if pin:IsMouseOver() and GameTooltip:IsOwned(pin) then ShowMinimapTooltip(pin) end
        end
    end
    HideMinimapPins(used + 1)
end

local minimapTicker
local function StartMinimapPins()
    if minimapTicker or not Minimap then return end
    minimapTicker = C_Timer.NewTicker(MINIMAP_UPDATE_INTERVAL, function()
        local ok, err = pcall(UpdateMinimapPins)
        if not ok then
            HideMinimapPins()
            minimapTicker:Cancel(); minimapTicker = nil
            Print("Minimap pins stopped after an error (see /onlyores debug log): " .. tostring(err))
            WriteLog("minimap error: " .. tostring(err))
        end
    end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")

f:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "OnlyOres" then
            InitDB()
        elseif name == "Blizzard_WorldMap" then
            RegisterProvider()
        end
    elseif event == "PLAYER_LOGIN" then
        RegisterProvider()
        StartMinimapPins()
    elseif event == "UNIT_SPELLCAST_SENT" then
        local _, target, castGUID, spellID = ...
        local mining = IsMiningSpell(spellID)
        -- In debug mode, log every cast (to file; mining ones also to chat) so
        -- we can spot unexpected gathering spells.
        local line = string.format("cast sent: spell %s (%s) target '%s'%s",
            tostring(spellID), tostring(GetSpellNameCompat(spellID)), tostring(target),
            mining and " [mining]" or "")
        if mining then Debug(line) else Trace(line) end
        if mining and target and target ~= "" then
            pendingCasts[castGUID] = target
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, castGUID, spellID = ...
        local nodeName = pendingCasts[castGUID]
        if nodeName then
            pendingCasts[castGUID] = nil
            RecordNode(nodeName)
        end
    else -- FAILED / INTERRUPTED
        local _, castGUID = ...
        if pendingCasts[castGUID] then Debug("mining cast " .. event) end
        pendingCasts[castGUID] = nil
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function PrintIgnoreList()
    local names = {}
    for name in pairs(OnlyOresDB.ignore) do table.insert(names, name) end
    table.sort(names)
    if #names == 0 then
        Print("Ignore list is empty.")
    else
        Print("Ignoring: " .. table.concat(names, ", "))
    end
end

SLASH_ONLYORES1 = "/onlyores"
SlashCmdList["ONLYORES"] = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = string.match(msg, "^(%S*)%s*(.-)$")
    cmd = string.lower(cmd or "")

    if cmd == "hide" or cmd == "show" or cmd == "toggle" then
        if cmd == "toggle" then OnlyOresDB.hidden = not OnlyOresDB.hidden
        else OnlyOresDB.hidden = (cmd == "hide") end
        Print(OnlyOresDB.hidden and "Pins hidden." or "Pins shown.")
        RefreshMap()
    elseif cmd == "debug" then
        OnlyOresDB.debug = not OnlyOresDB.debug
        Print(OnlyOresDB.debug and "Debug ON: every cast will be logged to chat." or "Debug OFF.")
    elseif cmd == "status" then
        PrintStatus()
    elseif cmd == "minimap" then
        OnlyOresDB.minimapHidden = not OnlyOresDB.minimapHidden
        Print(OnlyOresDB.minimapHidden and "Minimap pins hidden." or "Minimap pins shown.")
        StartMinimapPins() -- restarts the updater if an error stopped it
    elseif cmd == "log" and string.lower(rest) == "clear" then
        OnlyOresDB.log = {}
        Print("Debug log cleared.")
    elseif cmd == "ignore" then
        if rest == "" then PrintIgnoreList(); return end
        OnlyOresDB.ignore[string.lower(rest)] = true
        local removed = ForgetNodeType(rest)
        Print(string.format("Now ignoring '%s' (removed it from %d spawn points).", rest, removed))
        RefreshMap()
    elseif cmd == "unignore" then
        OnlyOresDB.ignore[string.lower(rest)] = nil
        Print(string.format("No longer ignoring '%s'.", rest))
    elseif cmd == "clear" and string.lower(rest) == "confirm" then
        OnlyOresDB.nodes = {}
        Print("All saved nodes cleared.")
        RefreshMap()
    elseif cmd == "clear" then
        Print("This deletes every saved node. Type /onlyores clear confirm to proceed.")
    else
        local total = 0
        for _, list in pairs(OnlyOresDB.nodes) do total = total + #list end
        Print(string.format("%d spawn points saved.%s", total, OnlyOresDB.debug and " (debug on)" or ""))
        Print("Commands: show | hide | toggle | minimap | status | debug | log clear | ignore [name] | unignore <name> | clear")
    end
end
