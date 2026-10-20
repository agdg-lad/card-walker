-- Card Walker SCORE ATTACK (LOVE2D, no external tools / assets)
--   Start with 4 cards including 1 joker. Draw through the deck once
--   (52 + 4 jokers = 56).
--   Suits ABCD (order A-B-C-D, WRAPS: D<>A adjacent). Ranks 1-13 WRAP (K<>A).
--   Walk iff ONE step orthogonally on the rank x suit map:
--     next/previous RANK in the SAME suit, or SAME rank in a next/previous SUIT.
--   Jokers are wild anywhere, both ways (a drawn joker replaces any
--     hand card; a joker in hand matches every draw). 4 jokers in the deck.
--   Notation is suit-first: "B7" = suit B, rank 7. Jokers show as "J1","J2".
--   Walk replaces the hand card (old card discarded), score +1.
--   Dead draws (no walk anywhere) auto-discard after a beat.
--   Deck ends -> game over, score = walks (max 52). The MAP is the board:
--   big ABCD x A..K grid center-stage, hand strip + deck sidebar.
--   Walk by clicking a BLACK hand card OR a BLACK map cell.
--   Seeds are 5-letter strings (steppers/random in menu); best per seed saved.

local SUITS = {"A", "B", "C", "D"} -- suit order for adjacency (wraps D<>A)
local SUIT_INDEX = {A = 1, B = 2, C = 3, D = 4}
local RANKS = {1,2,3,4,5,6,7,8,9,10,11,12,13}
local RANK_LABEL = {[1]="A",[11]="J",[12]="Q",[13]="K"}
local START_HAND = 4
local JOKERS = 4
local TOTAL_CARDS = 52 + JOKERS
local TOTAL_DRAWS = TOTAL_CARDS - START_HAND

-- PLAYDATE / CRUSTY 1-BIT (readable edition):
-- Native-res, no downscale, no fullscreen shader. Only two solid colors:
-- INK and PAPER. Grays are faked with hand-drawn checker dithers so text
-- stays razor sharp. Chunky square corners + thick borders = crust.
local VW, VH = 1024, 640
local DESIGN_W, DESIGN_H = VW, VH
local INK = {0.12, 0.11, 0.13} -- playdate-ish black
local PAPER = {0.90, 0.88, 0.78} -- playdate-ish paper
local FONT_BODY = nil
local FONT_BIG = nil

-- resizable view: scale UP only, snapped DOWN to half-steps
-- (1.0, 1.5, 2.0, ...) so vector text and 1px lines stay sharp.
-- Never below 1x: a smaller window center-crops instead of shrinking.
-- The leftover area is INK (black borders).
-- DEV ZOOM: ZoomOverride forces a fixed scale to preview big resolutions
-- (F1 = auto-fit, F2/F3/F4 = 1x/2x/3x, +/- = step). Harmless in prod.
local ZoomOverride = nil
local function getView()
    local ww, hh = love.graphics.getDimensions()
    local s
    if ZoomOverride then
        s = ZoomOverride
    else
        local raw = math.min(ww / DESIGN_W, hh / DESIGN_H)
        s = math.max(1.0, math.floor(raw * 2) / 2)
    end
    local ox = math.floor((ww - DESIGN_W * s) / 2)
    local oy = math.floor((hh - DESIGN_H * s) / 2)
    return s, ox, oy
end

local function toDesign(sx, sy)
    local s, ox, oy = getView()
    return (sx - ox) / s, (sy - oy) / s
end

local function C(v, a)
    local r = INK[1] + (PAPER[1] - INK[1]) * v
    local g = INK[2] + (PAPER[2] - INK[2]) * v
    local b = INK[3] + (PAPER[3] - INK[3]) * v
    if a then return r, g, b, a end
    return r, g, b
end

local function ink()
    return C(0.0)
end

local function paper()
    return C(1.0)
end

-- centered label inside a rect (cards and cells share one text style)
local function centered(str, x, y, w, h)
    local f = love.graphics.getFont()
    love.graphics.print(str, math.floor(x + (w - f:getWidth(str)) / 2),
        math.floor(y + (h - f:getHeight()) / 2))
end

-- blocky rect helpers: no rounded corners, integer-snapped
local function R(mode, x, y, w, h)
    love.graphics.rectangle(mode, math.floor(x), math.floor(y), math.floor(w), math.floor(h))
end

local function frameBox(x, y, w, h, lw)
    love.graphics.setLineWidth(lw or 2)
    R("line", x, y, w, h)
    love.graphics.setLineWidth(1)
end

-- dotted border for used/removed spots (X-marked, no card face)
local function dottedBox(x, y, w, h, dot, gap)
    dot, gap = dot or 2, gap or 6
    x, y = math.floor(x), math.floor(y)
    local ix = x
    while ix < x + w do
        R("fill", ix, y, dot, dot)
        R("fill", ix, y + h - dot, dot, dot)
        ix = ix + gap
    end
    local iy = y
    while iy < y + h do
        R("fill", x, iy, dot, dot)
        R("fill", x + w - dot, iy, dot, dot)
        iy = iy + gap
    end
end

-- (deck stripes retired: facedown cards are plain ink slabs now)

-- wave outline: wobbly rectangular selection for the DRAWN card/cell
local function waveBox(x, y, w, h, t, amp, waves)
    amp = amp or 3
    waves = waves or 3
    love.graphics.setLineWidth(2)
    local function edge(x0, y0, x1, y1, phase)
        local len = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0))
        if len < 1 then return end
        local nx, ny = -(y1 - y0) / len, (x1 - x0) / len
        local steps = math.max(8, math.floor(len / 6))
        local px, py = x0, y0
        for i = 1, steps do
            local k = i / steps
            local off = math.sin(k * math.pi * 2 * waves + t * 6 + phase) * amp
            local qx, qy = x0 + (x1 - x0) * k + nx * off, y0 + (y1 - y0) * k + ny * off
            love.graphics.line(px, py, qx, qy)
            px, py = qx, qy
        end
    end
    edge(x, y, x + w, y, 0)
    edge(x + w, y + h, x, y + h, math.pi)
    edge(x + w, y, x + w, y + h, math.pi / 2)
    edge(x, y + h, x, y, -math.pi / 2)
    love.graphics.setLineWidth(1)
end

-- manual checker dither: draws INK dots every `step` px inside rect.
-- density 2 = 50%, 3 = sparse, 4 = very sparse. Background must
-- already be PAPER. Text goes on top afterwards, stays sharp.
local function checker(x, y, w, h, step)
    step = step or 3
    x, y, w, h = math.floor(x), math.floor(y), math.floor(w), math.floor(h)
    for yy = y, y + h - 1, step do
        for xx = x + ((yy - y) % (step * 2) == 0 and 0 or math.floor(step / 2)), x + w - 1, step do
            love.graphics.rectangle("fill", xx, yy, 1, 1)
        end
    end
end

local function ditherFill(x, y, w, h, density)
    love.graphics.setColor(paper())
    R("fill", x, y, w, h)
    love.graphics.setColor(ink())
    checker(x, y, w, h, density or 3)
end

local function rankLabel(r)
    return RANK_LABEL[r] or tostring(r)
end

-- suit-first notation: "B7" = suit B, rank 7; jokers "JK1".."JK4"
local function cardName(c)
    if c.joker then return "JK" .. c.id end
    return c.suit .. rankLabel(c.rank)
end

local function cardKey(c)
    if c.joker then return "J" .. c.id end
    return c.rank .. "_" .. c.suit
end

local function suitColor(suit)
    -- 1-bit readable: all text is pure INK or PAPER. Suits are told
    -- apart by their letter, never by shade (shades dither badly).
    return ink()
end

-- walk rule: orthogonal neighbours on the rank x suit map (both axes wrap),
-- plus jokers which walk anywhere, both ways.
--   same suit + rank +-1 (A1>A2 ok, AK>AA wraps ok, A3>A1 wrong), or
--   same rank + suit +-1 (B1>A1 ok, D1>A1 wraps ok, A1>C1 wrong, B1>A2 wrong).
local function isWalkable(a, b)
    if a.joker or b.joker then return true end
    if a.suit == b.suit then
        local d = math.abs(a.rank - b.rank)
        return math.min(d, 13 - d) == 1
    elseif a.rank == b.rank then
        local d = math.abs(SUIT_INDEX[a.suit] - SUIT_INDEX[b.suit])
        return math.min(d, 4 - d) == 1
    end
    return false
end

local function newDeck()
    local d = {}
    for _, s in ipairs(SUITS) do
        for _, r in ipairs(RANKS) do
            d[#d + 1] = {rank = r, suit = s}
        end
    end
    for i = 1, JOKERS do
        d[#d + 1] = {joker = true, id = i}
    end
    return d
end

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = love.math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
end

local G = {
    deck = {}, hand = {}, discards = 0, dead = {},
    drawn = nil,          -- card awaiting decision
    walkable = {},        -- hand indices walkable from drawn
    state = "need_draw",  -- need_draw | prompt | over
    score = 0,
    best = 0,             -- best for the current seed (persisted per seed)
    seed = 1,
    screen = "menu",      -- "menu" | "game" (seed picked before a run)
    menuSeed = 1,
    shuffles = 0,
    msg = "",
    log = {},
    view = nil,
    trails = {},          -- per hand-slot walk chains (kept for stats)
    seen = {},            -- cardKey -> true for every card ever held (walked over)
}

-- per-seed bests, persisted with love.filesystem (built-in, no save = memory only)
local Scores = {}

local function loadScores()
    Scores = {}
    if not (love.filesystem and love.filesystem.getInfo) then return end
    local info = love.filesystem.getInfo("scores.txt")
    if not info then return end
    local data = love.filesystem.read("scores.txt")
    if not data then return end
    for seed, sc in data:gmatch("(%S+)%s+(%d+)") do
        Scores[seed] = tonumber(sc)
    end
end

local function saveScores()
    if not (love.filesystem and love.filesystem.write) then return end
    local out = {}
    for seed, sc in pairs(Scores) do out[#out + 1] = seed .. " " .. sc end
    love.filesystem.write("scores.txt", table.concat(out, "\n") .. "\n")
end

-- string seeds: 5 slots cycling A-Z0-9, hashed to a love RNG number
local SEED_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

local function seedChars(seed)
    local d = {}
    for i = 1, 5 do d[i] = seed:sub(i, i) end
    return d
end

local function seedFromChars(d)
    return table.concat(d)
end

local function hashSeed(seed)
    local h = 7
    for i = 1, #seed do
        h = (h * 37 + seed:byte(i)) % 2147483647
    end
    return h
end

local function randomSeedString()
    local d = {}
    for i = 1, 8 do
        local k = math.random(1, #SEED_CHARS)
        d[i] = SEED_CHARS:sub(k, k)
    end
    return table.concat(d)
end

local function seedLabel(seed)
    return seed
end

local function say(m)
    G.msg = m
    G.log[#G.log + 1] = m
    if #G.log > 4 then table.remove(G.log, 1) end
end

-- responsive base layout in DESIGN coords (1024x640); love.draw scales it
-- to whatever window size via getView(). Hit-boxes share these coords.
-- Top strip: HAND (4) | TABLE + DECK. Bottom: centralized score strip.
-- Body: map grid 13 ranks x 4 suits, jokers as a right column.
-- DY nudges the whole content block vertically (+58 leaves room for the
-- top score bar while keeping the content visually centered).
local DY = 58
local L = {
    hand = {x = 240, y = 28 + DY, w = 80, h = 104, gap = 8, perRow = 4},
    drawn = {x = 600, y = 28 + DY, w = 100, h = 116},
    deck = {x = 708, y = 28 + DY, w = 100, h = 116},
    labelY = 8 + DY,
    board = {x0 = 76, y0 = 200 + DY, cw = 54, ch = 64, gapx = 6, gapy = 10},
    joker = {x = 898, y0 = 200 + DY, w = 54, h = 64, gapy = 10},
    ghost = {w = 64, h = 88},
}

local function handPos(i)
    local h = L.hand
    local row = math.floor((i - 1) / h.perRow)
    local col = (i - 1) % h.perRow
    return h.x + col * (h.w + h.gap), h.y + row * (h.h + h.gap)
end

local function mapCellPos(rank, suit)
    local b = L.board
    local ci = rank -- rank columns run A..K left to right
    local ri = SUIT_INDEX[suit] -- suit rows run A..D top to bottom
    return b.x0 + (ci - 1) * (b.cw + b.gapx), b.y0 + (ri - 1) * (b.ch + b.gapy)
end

local function portalPos(id)
    local j = L.joker
    return j.x, j.y0 + (id - 1) * (j.h + j.gapy)
end

local function boardPosOf(card)
    if card.joker then
        local x, y = portalPos(card.id)
        return x, y, L.joker.w, L.joker.h
    end
    local x, y = mapCellPos(card.rank, card.suit)
    return x, y, L.board.cw, L.board.ch
end

-- hand slot holding the card with this map key (nil when absent)
local function slotOfKey(key)
    for i, h in ipairs(G.hand) do
        if cardKey(h) == key then return i end
    end
    return nil
end

local function center(r)
    return r.x + r.w / 2, r.y + r.h / 2
end

-- juice: flying card ghosts, particles, floating texts, deck shake (pure tables)
-- Gfx.autoT counts down to an automatic discard when the drawn card walks nowhere.
local Gfx = {fly = {}, parts = {}, texts = {}, shake = 0, autoT = 0}

-- sfx: punch on actions (pitched), win/lose on game end.
-- Guarded so a missing asset or headless env stays silent, never fatal.
local Sfx = {}

local function loadSfx()
    if not (love.audio and love.audio.newSource) then return end
    local function static(path)
        local ok, src = pcall(love.audio.newSource, path, "static")
        return ok and src or nil
    end
    Sfx.punch = static("assets/sfx/punch.wav")
    Sfx.win = static("assets/sfx/win.wav")
    Sfx.lose = static("assets/sfx/lose.wav")
end

local function playSfx(src)
    if src then src:play() end
end

local function playPunch(pitch)
    if Sfx.punch then
        Sfx.punch:setPitch(pitch or 1)
        Sfx.punch:play()
    end
end

-- ripple shockwaves: a latent full-screen dither revealed in expanding
-- bands. Spawned on game actions (walk/draw/discard/deal/game-over),
-- ticked in love.update, drawn as a stencil-masked band under the UI.
local ripples = {}
local ditherCanvas = nil
local fadeCanvas = nil -- edge fade: dither ramping into the black bars

local function spawnRipple(x, y, opts)
    opts = opts or {}
    -- organic feel: every ring rolls its own center, size, speed and width
    ripples[#ripples + 1] = {
        x = x + (math.random() - 0.5) * 16,
        y = y + (math.random() - 0.5) * 16,
        r = 6 + math.random() * 6,
        maxR = (opts.maxR or 260) * (0.85 + math.random() * 0.4),
        w = (opts.w or 16) * (0.8 + math.random() * 0.5),
        speed = (opts.speed or 70) * (0.8 + math.random() * 0.4),
        vx = opts.vx or 0, -- drift support (no game trigger uses it now)
        vy = opts.vy or 0,
    }
    while #ripples > 12 do table.remove(ripples, 1) end
end

local function easeOut(t)
    return 1 - (1 - t) * (1 - t) * (1 - t)
end

local function spawnFly(card, x0, y0, x1, y1, dur, opts)
    opts = opts or {}
    Gfx.fly[#Gfx.fly + 1] = {card = card, x0 = x0, y0 = y0, x1 = x1, y1 = y1,
        t = 0, dur = dur or 0.28, ring = opts.ring, faceDown = opts.faceDown}
end

local function burst(x, y, n, col, speed, life, size, grav)
    for i = 1, n do
        local a = math.random() * math.pi * 2
        local sp = speed * (0.4 + math.random() * 0.8)
        Gfx.parts[#Gfx.parts + 1] = {x = x, y = y,
            vx = math.cos(a) * sp, vy = math.sin(a) * sp - speed * 0.35,
            life = life, maxlife = life, size = size * (0.6 + math.random() * 0.8),
            col = col, grav = grav or 220}
    end
end

local function addText(x, y, str, col)
    Gfx.texts[#Gfx.texts + 1] = {x = x, y = y, str = str, t = 0, life = 1.0, col = col}
end

local function flyPos(f)
    local k = easeOut(math.min(1, f.t / f.dur))
    return f.x0 + (f.x1 - f.x0) * k, f.y0 + (f.y1 - f.y0) * k
end

local function doShuffle(reason)
    if #G.deck > 1 then shuffle(G.deck) end
    G.shuffles = G.shuffles + 1
    Gfx.shake = 0.35
end

local function walkableFrom(card)
    local out = {}
    for i, h in ipairs(G.hand) do
        if isWalkable(h, card) then out[#out + 1] = i end
    end
    return out
end

local function seenCount()
    local n = 0
    for _ in pairs(G.seen) do n = n + 1 end
    return n
end

-- ceiling: every remaining draw can score at most +1.
local function maxScore()
    return G.score + #G.deck + (G.drawn and 1 or 0)
end

-- score attack: game ends when the deck is fully drawn and resolved.
-- No losing, just a final score.
local function finishIfDeckDone()
    if G.state == "over" then return true end
    if #G.deck == 0 and G.drawn == nil and G.state == "need_draw" then
        G.state = "over"
        local newBest = G.score > G.best
        if newBest then
            G.best = G.score
            Scores[G.seed] = G.score
            saveScores()
        end
        playSfx(newBest and Sfx.win or Sfx.lose)
        say("Deck done. SCORE " .. G.score .. "/" .. TOTAL_DRAWS .. "  (best " .. G.best .. "). New game: click New.")
        spawnRipple(DESIGN_W / 2, DESIGN_H / 2, {maxR = 800, speed = 80, w = 24})
        for i = 1, 130 do
            local cols = {{1, 0.35, 0.35}, {0.3, 0.8, 1}, {0.35, 1, 0.5}, {1, 0.85, 0.3}, {0.8, 0.5, 1}}
            burst(60 + math.random() * 680, 40 + math.random() * 120, 1,
                cols[1 + (i % #cols)], 160, 1.6 + math.random(), 4, 160)
        end
        return true
    end
    return false
end

local function copyCard(c)
    if c.joker then return {joker = true, id = c.id} end
    return {rank = c.rank, suit = c.suit}
end

local function markSeen(c)
    G.seen[cardKey(c)] = true
end

local UI -- forward: layout/hit/hover state, table assigned below
local function initGame(seed)
    -- same string seed = same shuffles. nil seed = roll a fresh one.
    seed = seed or randomSeedString()
    local keepBest = Scores[seed] or 0
    love.math.setRandomSeed(hashSeed(seed))
    G.seed = seed
    G.screen = "game"
    G.deck, G.hand, G.discards, G.dead = newDeck(), {}, 0, {}
    G.drawn, G.walkable = nil, {}
    G.state = "need_draw"
    G.score = 0
    G.best = keepBest
    G.shuffles = 0
    G.view = nil
    Gfx.autoT, Gfx.shake = 0, 0
    Gfx.fly, Gfx.parts, Gfx.texts = {}, {}, {}
    G.trails, G.seen = {}, {}
    UI.pop = {} -- reset hover tween scales for the fresh run
    G.log = {}
    doShuffle("initial")
    for i = 1, START_HAND do
        G.hand[i] = table.remove(G.deck, 1)
    end
    -- guarantee the starting hand holds a joker
    local hasJoker = false
    for _, c in ipairs(G.hand) do if c.joker then hasJoker = true break end end
    if not hasJoker then
        local ji = nil
        for i, c in ipairs(G.deck) do if c.joker then ji = i break end end
        if ji then
            local slot = love.math.random(1, START_HAND)
            G.hand[slot], G.deck[ji] = G.deck[ji], G.hand[slot]
        end
    end
    for i = 1, START_HAND do
        G.trails[i] = {copyCard(G.hand[i])}
        markSeen(G.hand[i])
    end
    doShuffle("after deal")
    local sx, sy = center(L.deck)
    burst(sx, sy, 10, {0.5, 0.7, 1}, 110, 0.5, 3, 160)
    ripples = {}
    spawnRipple(sx, sy, {maxR = 220})
    say("Score attack: click a BLACK card to walk. Dead cards auto-discard.")
    Gfx.autoT = 0.6 -- opening draw plays itself: drawing is the only action
end

-- player action: draw top of deck
local function actionDraw()
    if G.state ~= "need_draw" then return end
    if #G.deck == 0 then finishIfDeckDone() return end
    Gfx.autoT = 0
    G.drawn = table.remove(G.deck, 1)
    G.walkable = walkableFrom(G.drawn)
    G.state = "prompt"
    local x0, y0 = center(L.deck)
    local x1, y1 = center(L.drawn)
    spawnFly({rank = 1, suit = "A"}, x0 - L.ghost.w / 2, y0 - L.ghost.h / 2,
        x1 - L.ghost.w / 2, y1 - L.ghost.h / 2, 0.28, {faceDown = true})
    burst(x0, y0, 8, {0.5, 0.6, 0.9}, 90, 0.4, 3, 160)
    spawnRipple(x0, y0, {maxR = 160})
    playPunch(1 - math.random() * 0.5) -- draw: same down-pitch as discard
    if #G.walkable > 0 then
        say("Drawn " .. cardName(G.drawn) .. ": WALK a black card, or click deck to discard.")
    else
        say("Drawn " .. cardName(G.drawn) .. ": no walk anywhere — auto-discarding…")
        Gfx.autoT = 0.55
    end
end

-- player action: walk (replace hand[i] with drawn), score +1
local function actionWalk(i)
    if G.state ~= "prompt" or G.drawn == nil then return false end
    local ok = false
    for _, w in ipairs(G.walkable) do if w == i then ok = true break end end
    if not ok then
        say("That hand card is not next/prev rank or same suit.")
        return false
    end
    local old = G.hand[i]
    local newCard = G.drawn
    Gfx.autoT = 0
    do -- ripple where the old card leaves its cell (card removed from cell)
        local ox, oy, ow, oh = boardPosOf(old)
        spawnRipple(ox + ow / 2, oy + oh / 2, {maxR = 170, speed = 60})
    end
    G.hand[i] = newCard
    G.trails[i] = G.trails[i] or {}
    G.trails[i][#G.trails[i] + 1] = copyCard(newCard)
    markSeen(newCard)
    G.score = G.score + 1
    playPunch(1 + math.random()) -- score: random pitch up to an octave up
    say("Walk " .. cardName(old) .. " -> " .. cardName(newCard) .. "  (+" .. 1 .. ", score " .. G.score .. ").")
    local dx, dy = center(L.drawn)
    local hx, hy = handPos(i)
    spawnFly(copyCard(newCard), dx - L.ghost.w / 2, dy - L.ghost.h / 2,
        hx + L.hand.w / 2 - L.ghost.w / 2, hy + L.hand.h / 2 - L.ghost.h / 2, 0.25, {ring = true})
    burst(hx + L.hand.w / 2, hy + L.hand.h / 2, 16, {0.2, 0.9, 0.35}, 150, 0.55, 4, 200)
    spawnRipple(hx + L.hand.w / 2, hy + L.hand.h / 2, {})
    addText(hx + L.hand.w / 2, hy - 6, "+1", {0.3, 1, 0.45})
    local bx, by, bw, bh = boardPosOf(newCard)
    burst(bx + bw / 2, by + bh / 2, 12, {0.25, 0.95, 0.4}, 130, 0.5, 4, 180)
    spawnRipple(bx + bw / 2, by + bh / 2, {maxR = 170, speed = 60})
    G.drawn = nil
    G.walkable = {}
    doShuffle("after walk")
    G.state = "need_draw"
    finishIfDeckDone()
    if G.state == "need_draw" and #G.deck > 0 then Gfx.autoT = 0.5 end
    return true
end

-- player action: discard the drawn card (dead, just vanishes).
-- auto=true when the game auto-discards a card that walks nowhere.
local function actionToPile(auto)
    if G.state ~= "prompt" or G.drawn == nil then return false end
    Gfx.autoT = 0
    G.discards = G.discards + 1
    playPunch(1 - math.random() * 0.5) -- discard: random pitch down an octave
    G.dead[cardKey(G.drawn)] = true -- feature kept: dead cell marked X (no pile/trash visuals)
    if auto then
        say("Auto-discarded " .. cardName(G.drawn) .. " (no walk). " .. #G.deck .. " left.")
    else
        say("Discarded " .. cardName(G.drawn) .. ". " .. #G.deck .. " left.")
    end
    local dx, dy = center(L.drawn)
    addText(dx, dy - 10, auto and "auto" or "miss", {0.7, 0.7, 0.75})
    burst(dx, dy, 8, {0.55, 0.55, 0.6}, 90, 0.45, 3, 200)
    spawnRipple(dx, dy, {maxR = 200})
    local bx, by, bw, bh = boardPosOf(G.drawn)
    burst(bx + bw / 2, by + bh / 2, 7, {0.6, 0.25, 0.25}, 80, 0.4, 3, 180)
    spawnRipple(bx + bw / 2, by + bh / 2, {maxR = 150, speed = 60})
    G.drawn = nil
    G.walkable = {}
    G.state = "need_draw"
    finishIfDeckDone()
    if G.state == "need_draw" and #G.deck > 0 then Gfx.autoT = 0.5 end
    return true
end

-- headless-test hook (no effect in LOVE): exposes logic to plain lua
if _G.__walker == nil then
    _G.__walker = {}
end
_G.__walker.G = G
_G.__walker.isWalkable = isWalkable
_G.__walker.initGame = initGame
_G.__walker.actionDraw = actionDraw
_G.__walker.actionWalk = actionWalk
_G.__walker.actionToPile = actionToPile
_G.__walker.TOTAL_DRAWS = TOTAL_DRAWS
_G.__walker.TOTAL_CARDS = TOTAL_CARDS
_G.__walker.Gfx = Gfx
_G.__walker.mapCellPos = mapCellPos
_G.__walker.maxScore = maxScore
_G.__walker.portalPos = portalPos
_G.__walker.slotOfKey = slotOfKey
_G.__walker.handPos = handPos

-- layout
UI = {
    buttons = {},
    handRects = {},
    deckRect = nil,
    drawnRect = nil,
    mouse = {x = -1, y = -1},
    pop = {}, -- hover tween scales per key (1 rest .. 2 hovered)
}

local function hovered(r)
    local m = UI.mouse
    return r and m.x >= r.x and m.x <= r.x + r.w and m.y >= r.y and m.y <= r.y + r.h
end

local function drawCardBox(x, y, w, h, card, opts)
    opts = opts or {}
    x, y = math.floor(x), math.floor(y)
    if card == nil then
        ditherFill(x, y, w, h, 4)
        love.graphics.setColor(ink())
        frameBox(x, y, w, h, 2)
        love.graphics.line(x + 6, y + h - 6, x + w - 6, y + 6)
        love.graphics.line(x + 6, y + 6, x + w - 6, y + h - 6)
        if opts.label then
            love.graphics.setColor(ink())
            love.graphics.print(opts.label, x + 8, y + h / 2 - 6)
        end
        return
    end
    if opts.faceDown then
        -- facedown: solid ink slab with paper "?", nothing else
        love.graphics.setColor(ink())
        R("fill", x, y, w, h)
        love.graphics.setColor(paper())
        if FONT_BIG then love.graphics.setFont(FONT_BIG) end
        centered("?", x, y, w, h)
        if FONT_BODY then love.graphics.setFont(FONT_BODY) end
        love.graphics.setColor(paper())
        frameBox(x, y, w, h, 2)
        return
    end
    local hl = opts.highlight
    local black = hl or opts.black -- hand cards are always black
    if black then
        love.graphics.setColor(ink())
    else
        love.graphics.setColor(paper())
    end
    R("fill", x, y, w, h)
    love.graphics.setColor(ink())
    frameBox(x, y, w, h, hl and 3 or 2)
    -- one centered label, drawn with the card at whatever tween scale
    if black then love.graphics.setColor(paper())
    else love.graphics.setColor(ink()) end
    if FONT_BIG then love.graphics.setFont(FONT_BIG) end
    centered(cardName(card), x, y, w, h)
    if FONT_BODY then love.graphics.setFont(FONT_BODY) end
    love.graphics.setColor(paper())
end

-- drawZone retired: deck count lives in the deck hint line now.

local function button(id, x, y, w, h, label, enabled, invert)
    UI.buttons[id] = {x = x, y = y, w = w, h = h, enabled = enabled}
    local hov = enabled and hovered(UI.buttons[id])
    x, y = math.floor(x), math.floor(y)
    -- invert=true: black bg + white fg at rest, flips on hover
    local blackBg = enabled and (hov == (not invert))
    if blackBg then
        love.graphics.setColor(ink())
    elseif enabled then
        love.graphics.setColor(paper())
    else
        ditherFill(x, y, w, h, 3)
        love.graphics.setColor(ink())
        frameBox(x, y, w, h, 2)
        love.graphics.print(label, x + 10, y + h / 2 - 6)
        return
    end
    R("fill", x, y, w, h)
    love.graphics.setColor(ink())
    frameBox(x, y, w, h, 2)
    if blackBg then
        love.graphics.setColor(paper())
    else
        love.graphics.setColor(ink())
    end
    love.graphics.print(label, x + 10, y + h / 2 - 6)
end

local function inside(b, mx, my)
    return b and b.enabled and mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h
end

-- THE BOARD: big ABCD x A..K grid + joker row. Black cells (and black
-- jokers) are clickable to walk. Sets UI.boardRects for clicks and UI.tip.
local function drawBoard()
    local b = L.board
    local x0, y0, cw, chh = b.x0, b.y0, b.cw, b.ch
    UI.boardRects = {}
    UI.hoverCell = nil
    local suits = SUITS
    local ranks = {1,2,3,4,5,6,7,8,9,10,11,12,13}
    local t = love.timer.getTime()
    -- rank headers across the top: A 2 3 ... J Q K
    for ci, r in ipairs(ranks) do
        local x = x0 + (ci - 1) * (cw + b.gapx)
        love.graphics.setColor(ink())
        love.graphics.print(rankLabel(r), x + cw / 2 - 8, y0 - 22)
    end
    -- suit labels left of the rows: same 6px visual gap as rank headers
    for ri, s in ipairs(suits) do
        local y = y0 + (ri - 1) * (chh + b.gapy)
        if FONT_BODY then love.graphics.setFont(FONT_BODY) end
        local f = love.graphics.getFont()
        love.graphics.setColor(ink())
        love.graphics.print(s, x0 - 6 - f:getWidth(s), y + chh / 2 - 8)
    end
    local inHand = {}
    for _, h in ipairs(G.hand) do inHand[cardKey(h)] = true end
    local walkSet = {}
    for _, w in ipairs(G.walkable) do walkSet[cardKey(G.hand[w])] = true end
    -- single map cell painter (hover pop scales it in place via transform).
    -- rect is the ungrown hit-box used for hover tests.
    local function drawMapCell(x, y, w, h, s, key, name, rect)
        local green = inHand[key]
        local canWalk = green and G.state == "prompt" and walkSet[key]
        if green then
            -- ON HAND: always black (walkable or not), centered label
            love.graphics.setColor(ink())
            R("fill", x, y, w, h)
            love.graphics.setColor(paper())
            centered(name, x, y, w, h)
            if canWalk then
                -- walkable cue: blinking corner square (ants removed)
                if math.floor(t * 2) % 2 == 0 then
                    love.graphics.setColor(paper())
                    R("fill", x + w - 12, y + 4, 8, 8)
                    love.graphics.setColor(ink())
                    R("line", x + w - 12, y + 4, 8, 8)
                end
            end
            if G.state == "prompt" and walkSet[key] and hovered(rect) then
                love.graphics.setColor(paper())
                frameBox(x - 2, y - 2, w + 4, h + 4, 2)
            end
        elseif G.seen[key] then
            -- walked over: dotted border, suit/rank still shown, centered
            love.graphics.setColor(ink())
            dottedBox(x, y, w, h)
            centered(name, x, y, w, h)
        elseif G.dead[key] then
            -- removed: no card face, dotted border, X only
            love.graphics.setColor(ink())
            dottedBox(x, y, w, h)
            love.graphics.line(x + 10, y + 6, x + w - 10, y + h - 6)
            love.graphics.line(x + w - 10, y + 6, x + 10, y + h - 6)
        else
            -- in deck: solid paper, 1px border, centered ink label
            love.graphics.setColor(paper())
            R("fill", x, y, w, h)
            love.graphics.setColor(ink())
            love.graphics.setLineWidth(1)
            love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
            centered(name, x, y, w, h)
        end
    end
    -- tweened hover pop: cells with z > 1 skip the grid pass and draw once
    -- afterwards, each at its own current scale (smooth 1..2 both ways).
    -- Shared with the joker row below; wave markers track the same scales.
    local deferred = {}
    for ri, s in ipairs(suits) do
        local y = y0 + (ri - 1) * (chh + b.gapy)
        for ci, r in ipairs(ranks) do
            local x = x0 + (ci - 1) * (cw + b.gapx)
            local key = r .. "_" .. s
            local name = s .. rankLabel(r)
            local rect = {x = x, y = y, w = cw, h = chh, key = key}
            UI.boardRects[#UI.boardRects + 1] = rect
            local z = UI.pop[key] or 1
            if z > 1.01 then
                deferred[#deferred + 1] = {x = x, y = y, w = cw, h = chh, s = s, key = key, name = name, rect = rect, z = z}
            else
                drawMapCell(x, y, cw, chh, s, key, name, rect)
            end
            if hovered(rect) then UI.hoverCell = {key = key, name = name, map = true, s = s, rect = rect} end
        end
    end
    -- drawn card marker on its cell: wave outline, tracking hover scale
    if G.drawn and not G.drawn.joker then
        local x, y = mapCellPos(G.drawn.rank, G.drawn.suit)
        local dz = UI.pop[cardKey(G.drawn)] or 1
        love.graphics.setColor(ink())
        if dz > 1.01 then
            love.graphics.push()
            love.graphics.translate(x + cw / 2, y + chh / 2)
            love.graphics.scale(dz, dz)
            love.graphics.translate(-(x + cw / 2), -(y + chh / 2))
        end
        waveBox(x - 2, y - 2, cw + 4, chh + 4, t)
        if dz > 1.01 then love.graphics.pop() end
    end
    -- joker row: drawn exactly like normal cells (black in hand, X when
    -- used/removed, open paper in deck). Jokers are just another cell.
    love.graphics.setColor(ink())
    love.graphics.print("JK", L.joker.x + 19, b.y0 - 22)
    UI.portalRects = {}
    for i = 1, JOKERS do
        local k = "J" .. i
        local jn = "JK" .. i
        local x, y = portalPos(i)
        local rect = {x = x, y = y, w = L.joker.w, h = L.joker.h, key = k}
        UI.portalRects[#UI.portalRects + 1] = rect
        local z = UI.pop[k] or 1
        if z > 1.01 then
            deferred[#deferred + 1] = {x = x, y = y, w = L.joker.w, h = L.joker.h, s = nil, key = k, name = jn, rect = rect, z = z}
        else
            drawMapCell(x, y, L.joker.w, L.joker.h, nil, k, jn, rect)
        end
        if hovered(rect) then UI.hoverCell = {key = k, name = jn, rect = rect, pi = i} end
    end
    -- drawn joker marker on its cell: wave outline, tracking hover scale
    if G.drawn and G.drawn.joker then
        local jx, jy = portalPos(G.drawn.id)
        local dz = UI.pop[cardKey(G.drawn)] or 1
        love.graphics.setColor(ink())
        if dz > 1.01 then
            love.graphics.push()
            love.graphics.translate(jx + L.joker.w / 2, jy + L.joker.h / 2)
            love.graphics.scale(dz, dz)
            love.graphics.translate(-(jx + L.joker.w / 2), -(jy + L.joker.h / 2))
        end
        waveBox(jx - 2, jy - 2, L.joker.w + 4, L.joker.h + 4, t)
        if dz > 1.01 then love.graphics.pop() end
    end
    -- deferred tweened cells draw once, each at its own scale, text and all
    for _, d in ipairs(deferred) do
        love.graphics.push()
        love.graphics.translate(d.x + d.w / 2, d.y + d.h / 2)
        love.graphics.scale(d.z, d.z)
        love.graphics.translate(-(d.x + d.w / 2), -(d.y + d.h / 2))
        drawMapCell(d.x, d.y, d.w, d.h, d.s, d.key, d.name, d.rect)
        love.graphics.pop()
    end
    love.graphics.setColor(paper())
end

-- floating contextual tooltip near the cursor.
--   open map cell ......... "Card still on deck"
--   hand card / in-hand cell  "Card on hand" (+ "Click to walk" if walkable)
--   deck zone / drawn card  "Click to discard"
local function walkTip(slot)
    local lines = {"Card on hand"}
    for _, w in ipairs(G.walkable) do
        if w == slot then lines[#lines + 1] = "Click to walk" break end
    end
    return lines
end

local function drawTooltip()
    if G.state == "over" then return end
    local mx, my = UI.mouse.x, UI.mouse.y
    if mx < 0 or my < 0 or mx > DESIGN_W or my > DESIGN_H then return end
    local lines = nil
    for i, r in ipairs(UI.handRects) do
        if hovered(r) then
            lines = walkTip(i)
            break
        end
    end
    if not lines and UI.deckRect and hovered(UI.deckRect) then
        lines = {"Click to discard"}
    end
    if not lines and G.drawn then
        local dx, dy = L.drawn.x - 4, L.drawn.y - 8
        if mx >= dx and mx <= dx + L.drawn.w + 8
            and my >= dy and my <= dy + L.drawn.h + 8 then
            lines = {"Click to discard"}
        end
    end
    if not lines then
        local openTip = function(key)
            return not slotOfKey(key) and not G.seen[key] and not G.dead[key]
        end
        for _, r in ipairs(UI.boardRects or {}) do
            if hovered(r) then
                local slot = slotOfKey(r.key)
                if slot then lines = walkTip(slot)
                elseif G.drawn and cardKey(G.drawn) == r.key then lines = {"Card on table"}
                elseif G.seen[r.key] then lines = {"Scored card"}
                elseif G.dead[r.key] then lines = {"Dead card"}
                elseif openTip(r.key) then lines = {"Card still on deck"} end
                break
            end
        end
        if not lines then
            for _, r in ipairs(UI.portalRects or {}) do
                if hovered(r) then
                    local slot = slotOfKey(r.key)
                    if slot then lines = walkTip(slot)
                    elseif G.drawn and cardKey(G.drawn) == r.key then lines = {"Card on table"}
                    elseif G.seen[r.key] then lines = {"Scored card"}
                    elseif G.dead[r.key] then lines = {"Dead card"}
                    elseif openTip(r.key) then lines = {"Card still on deck"} end
                    break
                end
            end
        end
    end
    if not lines then return end
    if FONT_BODY then love.graphics.setFont(FONT_BODY) end
    local f = love.graphics.getFont()
    local wmax = 0
    for _, s in ipairs(lines) do wmax = math.max(wmax, f:getWidth(s)) end
    local bw, bh = wmax + 16, #lines * 17 + 12
    local bx, by = mx + 14, my + 14
    if bx + bw > DESIGN_W then bx = mx - 14 - bw end
    if by + bh > DESIGN_H then by = my - 14 - bh end
    love.graphics.setColor(ink())
    R("fill", bx, by, bw, bh)
    love.graphics.setColor(paper())
    for i, s in ipairs(lines) do
        love.graphics.print(s, bx + 8, by + 6 + (i - 1) * 17)
    end
end

-- wrapLines retired with the INFO panel.

-- drawTip retired with the INFO panel; see drawTooltip() above.

function love.load()
    math.randomseed(os.time())
    love.graphics.setDefaultFilter("nearest", "nearest", 1)
    love.graphics.setLineStyle("rough")
    -- runescape pixel font, sized on exact multiples of its 16px base so
    -- glyphs stay crisp (16 rest, 32 hover); pcall fallback keeps the
    -- game alive if the asset is missing (e.g. stripped .love builds).
    local okB, fB = pcall(love.graphics.newFont, "assets/runescape_uf.ttf", 16)
    FONT_BODY = (okB and fB) or love.graphics.newFont(16)
    local okH, fH = pcall(love.graphics.newFont, "assets/runescape_uf.ttf", 32)
    FONT_BIG = (okH and fH) or love.graphics.newFont(32)
    love.graphics.setFont(FONT_BODY)
    loadSfx()
    -- latent dither sheet: invisible until a ripple band reveals it
    ditherCanvas = love.graphics.newCanvas(DESIGN_W, DESIGN_H)
    ditherCanvas:setFilter("nearest", "nearest")
    love.graphics.setCanvas(ditherCanvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(INK[1], INK[2], INK[3])
    for yy = 0, DESIGN_H - 1, 4 do
        local xoff = ((yy / 4) % 2 == 0) and 0 or 2
        for xx = xoff, DESIGN_W - 1, 4 do
            love.graphics.rectangle("fill", xx, yy, 2, 2)
        end
    end
    love.graphics.setCanvas()
    -- corner/edge fade: ink dots denser toward the border so the paper
    -- melts into the black letterbox bars (baked once, drawn every frame)
    fadeCanvas = love.graphics.newCanvas(DESIGN_W, DESIGN_H)
    fadeCanvas:setFilter("nearest", "nearest")
    love.graphics.setCanvas(fadeCanvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(INK[1], INK[2], INK[3])
    local FD = 28
    for yy = 0, DESIGN_H - 1, 2 do
        for xx = 0, DESIGN_W - 1, 2 do
            local e = math.min(xx, yy, DESIGN_W - 1 - xx, DESIGN_H - 1 - yy)
            if e < FD then
                local t = 1 - e / FD
                local h = ((xx * 73 + yy * 149) % 101) / 101
                if h < t then
                    love.graphics.rectangle("fill", xx, yy, 2, 2)
                end
            end
        end
    end
    love.graphics.setCanvas()
    loadScores()
    love.graphics.setBackgroundColor(PAPER[1], PAPER[2], PAPER[3])
    G.menuSeed = randomSeedString()
    G.seedFocused = false
    G.screen = "menu" -- pick a seed first; no run starts by itself
end

-- menu: click the box and type a seed (A-Z0-9, 16 chars max). Rects for clicks.
local SEED_MAXLEN = 16

local function drawMenu()
    UI.menuBtns = {}
    local t = love.timer.getTime()
    -- two columns split by a vertical rule
    love.graphics.setColor(ink())
    R("fill", 511, 100, 3, 440)
    -- left column: game name + tutorial
    if FONT_BIG then love.graphics.setFont(FONT_BIG) end
    love.graphics.print("CARD", 90, 120)
    love.graphics.print("WALKER", 90, 152)
    if FONT_BODY then love.graphics.setFont(FONT_BODY) end
    love.graphics.print("=========", 90, 188)
    local how = {
        "Walk across the map:",
        "same suit, rank +-1,",
        "same rank, suit +-1,",
        "edges wrap around.",
        "JK walks anywhere.",
        "",
        "BLACK card is yours.",
        "Click it, or its cell,",
        "to walk the table card.",
        "Click DECK to draw.",
        "Dead draws discard.",
        "X = done.",
    }
    for i, line in ipairs(how) do
        love.graphics.print(line, 90, 214 + (i - 1) * 22)
    end
    -- right column: highscore, seed row, start
    local best = Scores[G.menuSeed]
    if G.menuSeed == "" then
        love.graphics.print("type a seed first", 560, 130)
    else
        love.graphics.print("highscore[" .. seedLabel(G.menuSeed) .. "] = " .. (best or "--"), 560, 130)
    end
    UI.menuField = {x = 560, y = 170, w = 230, h = 56}
    local fhov = hovered(UI.menuField)
    love.graphics.setColor(paper())
    R("fill", UI.menuField.x, UI.menuField.y, UI.menuField.w, UI.menuField.h)
    love.graphics.setColor(ink())
    frameBox(UI.menuField.x, UI.menuField.y, UI.menuField.w, UI.menuField.h, G.seedFocused and 3 or 2)
    if G.seedFocused and math.floor(t * 2) % 2 == 0 then
        love.graphics.setColor(ink())
        if FONT_BODY then love.graphics.setFont(FONT_BODY) end
        local tw = love.graphics.getFont():getWidth(G.menuSeed)
        R("fill", UI.menuField.x + 16 + tw + 2, UI.menuField.y + 13, 12, 30)
    elseif fhov then
        love.graphics.setColor(ink())
        love.graphics.print(">", UI.menuField.x + 4, UI.menuField.y + 18)
    end
    love.graphics.setColor(ink())
    local shown = G.menuSeed
    love.graphics.print(shown ~= "" and shown or "click, type seed", UI.menuField.x + 16, UI.menuField.y + 18)
    love.graphics.print(#G.menuSeed .. "/" .. SEED_MAXLEN, UI.menuField.x, UI.menuField.y + UI.menuField.h + 6)
    local function menuBtn(id, x, y, w, h, label, hot)
        UI.menuBtns[id] = {x = x, y = y, w = w, h = h}
        local hov = hovered(UI.menuBtns[id])
        if hov then love.graphics.setColor(ink())
        else love.graphics.setColor(paper()) end
        R("fill", x, y, w, h)
        love.graphics.setColor(ink())
        frameBox(x, y, w, h, hot and 3 or 2)
        if hov then love.graphics.setColor(paper())
        else love.graphics.setColor(ink()) end
        love.graphics.print(label, x + 20, y + h / 2 - 6)
    end
    menuBtn("random", 798, 170, 132, 56, "Random")
    menuBtn("start", 560, 252, 370, 56, "START RUN", true)
    love.graphics.setColor(ink())
    love.graphics.print("same seed, same shuffles", 560, 322)
end

-- hover tween scales: 1 = rest, 2 = hovered, eased every frame in update.
-- Board cells keyed "rank_suit", jokers "J#", hand slots "h#".
local POP_KEYS = {}
do
    for _, s in ipairs(SUITS) do
        for _, r in ipairs(RANKS) do POP_KEYS[#POP_KEYS + 1] = r .. "_" .. s end
    end
    for i = 1, JOKERS do POP_KEYS[#POP_KEYS + 1] = "J" .. i end
    for i = 1, START_HAND do POP_KEYS[#POP_KEYS + 1] = "h" .. i end
end

-- design-coords key under the mouse right now (nil when none / not in game)
local function hoverPopKey()
    if G.screen ~= "game" then return nil end
    local mx, my = UI.mouse.x, UI.mouse.y
    local function inside(x, y, w, h)
        return mx >= x and mx <= x + w and my >= y and my <= y + h
    end
    for i = 1, #G.hand do
        local x, y = handPos(i)
        if inside(x, y, L.hand.w, L.hand.h) then return "h" .. i end
    end
    for _, s in ipairs(SUITS) do
        for _, r in ipairs(RANKS) do
            local key = r .. "_" .. s
            -- walked (seen) and dead (X) cells never scale, but cards
            -- currently on hand always do (held keys are seen too)
            if not G.dead[key] and (slotOfKey(key) or not G.seen[key]) then
                local x, y = mapCellPos(r, s)
                if inside(x, y, L.board.cw, L.board.ch) then return key end
            end
        end
    end
    for i = 1, JOKERS do
        local key = "J" .. i
        if not G.dead[key] and (slotOfKey(key) or not G.seen[key]) then
            local x, y = portalPos(i)
            if inside(x, y, L.joker.w, L.joker.h) then return key end
        end
    end
    return nil
end

function love.update(dt)
    do
        local sx, sy = love.mouse.getPosition()
        UI.mouse.x, UI.mouse.y = toDesign(sx, sy)
    end
    if dt > 0.05 then dt = 0.05 end
    -- ripple shockwaves expand here (ticks on every screen)
    for i = #ripples, 1, -1 do
        local rp = ripples[i]
        rp.r = rp.r + rp.speed * dt
        if rp.r >= rp.maxR then
            table.remove(ripples, i)
        else
            -- centers drift; ambient waves bounce off edges and corners
            rp.x = rp.x + rp.vx * dt
            rp.y = rp.y + rp.vy * dt
            if rp.x < 0 then rp.x = 0 rp.vx = -rp.vx
            elseif rp.x > DESIGN_W then rp.x = DESIGN_W rp.vx = -rp.vx end
            if rp.y < 0 then rp.y = 0 rp.vy = -rp.vy
            elseif rp.y > DESIGN_H then rp.y = DESIGN_H rp.vy = -rp.vy end
        end
    end
    -- hover tween: ease every poppable scale toward 2 (hovered) or 1 (rest)
    do
        local hk = hoverPopKey()
        for _, k in ipairs(POP_KEYS) do
            local z = UI.pop[k] or 1
            local target = (hk == k) and 2 or 1
            if z ~= target then
                local step = dt * 12
                if math.abs(target - z) <= step then z = target
                else z = z + ((target > z) and step or -step) end
                UI.pop[k] = z
            end
        end
    end
    if G.screen ~= "game" then return end -- menu: nothing ticks
    -- autoplay: discard dead draws, and draw whenever drawing is the only action
    if Gfx.autoT > 0 and G.state ~= "over" then
        Gfx.autoT = Gfx.autoT - dt
        if Gfx.autoT <= 0 then
            if G.state == "prompt" and #G.walkable == 0 then actionToPile(true) end
            if G.state == "need_draw" and #G.deck > 0 then actionDraw() end
        end
    end
    if Gfx.shake > 0 then Gfx.shake = Gfx.shake - dt end
    for i = #Gfx.fly, 1, -1 do
        local f = Gfx.fly[i]
        f.t = f.t + dt
        if f.ring then
            local x, y = flyPos(f)
            Gfx.parts[#Gfx.parts + 1] = {x = x + L.ghost.w / 2, y = y + L.ghost.h / 2,
                vx = (math.random() - 0.5) * 40, vy = -30 - math.random() * 40,
                life = 0.4, maxlife = 0.4, size = 3, col = {0.3, 1, 0.45}, grav = 60}
        end
        if f.t >= f.dur then table.remove(Gfx.fly, i) end
    end
    for i = #Gfx.parts, 1, -1 do
        local p = Gfx.parts[i]
        p.life = p.life - dt
        if p.life <= 0 then table.remove(Gfx.parts, i)
        else
            p.vy = p.vy + p.grav * dt
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
        end
    end
    for i = #Gfx.texts, 1, -1 do
        local t = Gfx.texts[i]
        t.t = t.t + dt
        if t.t >= t.life then table.remove(Gfx.texts, i) end
    end
end

function love.draw()
    -- responsive: scale DESIGN to window, letterboxed. All art/hit-boxes
    -- stay in DESIGN coords; input is converted back via toDesign().
    if FONT_BODY then love.graphics.setFont(FONT_BODY) end
    local ww, hh = love.graphics.getDimensions()
    local s, ox, oy = getView()
    love.graphics.setColor(ink())
    love.graphics.clear(INK[1], INK[2], INK[3])
    love.graphics.push()
    love.graphics.translate(ox, oy)
    love.graphics.scale(s, s)
    love.graphics.setColor(paper())
    R("fill", 0, 0, DESIGN_W, DESIGN_H)
    -- edge fade over the paper (under everything): melts into the bars
    if fadeCanvas then
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(fadeCanvas, 0, 0)
    end
    if G.screen == "menu" then
        drawMenu()
    else
        drawScene()
    end
    love.graphics.pop()
end

function drawScene()
    local mx = maxScore()
    -- ripple shockwaves: latent dither revealed in expanding bands (under UI)
    for _, rp in ipairs(ripples) do
        local a = math.max(0, 1 - rp.r / rp.maxR)
        if a > 0 and ditherCanvas then
            love.graphics.stencil(function()
                love.graphics.circle("fill", rp.x, rp.y, rp.r)
            end, "replace", 1, true)
            love.graphics.stencil(function()
                love.graphics.circle("fill", rp.x, rp.y, math.max(0, rp.r - rp.w))
            end, "replace", 0, true)
            love.graphics.setStencilTest("greater", 0)
            love.graphics.setColor(1, 1, 1, a)
            love.graphics.draw(ditherCanvas, 0, 0)
            love.graphics.setStencilTest()
        end
    end
    -- top strip labels
    love.graphics.setColor(ink())
    love.graphics.print("HAND", L.hand.x, L.labelY)
    love.graphics.print("TABLE", L.drawn.x, L.labelY)
    love.graphics.print("DECK " .. #G.deck, L.deck.x, L.labelY)
    -- THE BOARD
    drawBoard()

    -- top strip: DRAWN + DECK draw/discard control (count folded into hint)
    UI.deckRect = {x = L.deck.x, y = L.deck.y, w = L.deck.w, h = L.deck.h}
    local ddx = 0
    if Gfx.shake > 0 then ddx = math.floor(math.sin(Gfx.shake * 40) * 7 * Gfx.shake) end
    local deckLive = (G.state == "need_draw" and #G.deck > 0) or G.state == "prompt"
    if deckLive and hovered(UI.deckRect) then
        love.graphics.setColor(ink())
        frameBox(L.deck.x - 4, L.deck.y - 4, L.deck.w + 8, L.deck.h + 8, 2)
    end
    drawCardBox(L.deck.x + ddx, L.deck.y, L.deck.w, L.deck.h, #G.deck > 0 and {rank = 1, suit = "A"} or nil,
        {faceDown = #G.deck > 0, label = "empty"})
    -- deck count + action live in the DECK label/tooltip now
    -- DRAWN card bobs + wavy outline (wave animation)
    local dwY = 0
    if G.drawn then dwY = math.floor(math.sin(love.timer.getTime() * 5) * 4) end
    drawCardBox(L.drawn.x, L.drawn.y + dwY, L.drawn.w, L.drawn.h, G.drawn, {label = "--"})
    UI.drawnRect = {x = L.drawn.x, y = L.drawn.y + dwY, w = L.drawn.w, h = L.drawn.h}
    if G.drawn then
        love.graphics.setColor(ink())
        waveBox(L.drawn.x - 3, L.drawn.y + dwY - 3, L.drawn.w + 6, L.drawn.h + 6, love.timer.getTime())
    end

    -- hand row (top strip): all hand cards black; tweened cards with
    -- z > 1 draw once afterwards at their own scale (smooth 1..2)
    UI.handRects = {}
    local hlSet = {}
    for _, w in ipairs(G.walkable) do hlSet[w] = true end
    local hdef = {}
    for i, c in ipairs(G.hand) do
        local x, y = handPos(i)
        local r = {x = x, y = y, w = L.hand.w, h = L.hand.h}
        UI.handRects[i] = r
        local z = UI.pop["h" .. i] or 1
        if z > 1.01 then
            hdef[#hdef + 1] = {i = i, c = c, x = x, y = y, z = z}
        else
            drawCardBox(x, y, L.hand.w, L.hand.h, c, {highlight = hlSet[i], black = true})
        end
    end
    for _, hd in ipairs(hdef) do
        local lift = 8 * (hd.z - 1)
        love.graphics.push()
        love.graphics.translate(hd.x + L.hand.w / 2, hd.y + L.hand.h / 2 - lift)
        love.graphics.scale(hd.z, hd.z)
        love.graphics.translate(-(hd.x + L.hand.w / 2), -(hd.y + L.hand.h / 2))
        drawCardBox(hd.x, hd.y, L.hand.w, L.hand.h, hd.c, {highlight = hlSet[hd.i], black = true})
        love.graphics.pop()
    end

    -- top bar: full-width black strip, score line left, text buttons right
    love.graphics.setColor(ink())
    R("fill", 0, 0, DESIGN_W, 44)
    love.graphics.setColor(paper())
    local barLine = "SEED " .. seedLabel(G.seed) .. " --- SCORE " .. G.score .. "/" .. mx .. " --- HIGHSCORE " .. G.best
    if G.best > 0 and mx <= G.best and G.state ~= "over" then
        barLine = barLine .. " --- LOCKED"
    elseif ZoomOverride then
        barLine = barLine .. " --- ZOOM " .. ZoomOverride .. "x"
    end
    love.graphics.print(barLine, 24, 14)
    button("retry", 824, 7, 90, 30, "RESTART", true, true)
    button("tomenu", 922, 7, 90, 30, "HOME", true, true)

    if G.state == "over" then
        -- overlay: sparse checker so game behind shows through, dialog solid
        love.graphics.setColor(paper())
        R("fill", 0, 0, DESIGN_W, DESIGN_H)
        love.graphics.setColor(ink())
        checker(0, 0, DESIGN_W, DESIGN_H, 3)
        love.graphics.setColor(paper())
        R("fill", 332, 230, 360, 120)
        love.graphics.setColor(ink())
        frameBox(332, 230, 360, 120, 3)
        love.graphics.print("SEED " .. seedLabel(G.seed) .. " DONE", 352, 246)
        love.graphics.print("SCORE " .. G.score .. "/" .. TOTAL_DRAWS, 352, 266)
        love.graphics.print("Best " .. G.best .. " | seen " .. seenCount() .. "/" .. TOTAL_CARDS, 352, 286)
        UI.overRetry = {x = 352, y = 310, w = 150, h = 44}
        UI.overMenu = {x = 522, y = 310, w = 150, h = 44}
        for _, b in ipairs({{UI.overRetry, "RESTART seed"}, {UI.overMenu, "HOME"}}) do
            local r, label = b[1], b[2]
            local hov = hovered(r)
            if hov then love.graphics.setColor(ink())
            else love.graphics.setColor(paper()) end
            R("fill", r.x, r.y, r.w, r.h)
            love.graphics.setColor(ink())
            frameBox(r.x, r.y, r.w, r.h, 2)
            if hov then love.graphics.setColor(paper())
            else love.graphics.setColor(ink()) end
            love.graphics.print(label, r.x + 24, r.y + 15)
        end
    end

    -- juice on top: flying cards, square particles, floating scores (ink only)
    for _, f in ipairs(Gfx.fly) do
        local x, y = flyPos(f)
        drawCardBox(x, y, L.ghost.w, L.ghost.h, f.card, {faceDown = f.faceDown, highlight = f.ring})
    end
    for _, p in ipairs(Gfx.parts) do
        love.graphics.setColor(ink())
        local s = math.max(3, math.floor(p.size))
        R("fill", p.x - s / 2, p.y - s / 2, s, s)
    end
    for _, t in ipairs(Gfx.texts) do
        local k = t.t / t.life
        love.graphics.setColor(paper())
        love.graphics.print(t.str, t.x - 8 + 1, t.y - 44 * k + 1)
        love.graphics.setColor(ink())
        love.graphics.print(t.str, t.x - 8, t.y - 44 * k)
    end
    -- floating tooltip on top of everything
    drawTooltip()
    love.graphics.setColor(paper())
end

function love.mousereleased(mx, my, btn)
    if btn ~= 1 then return end
    mx, my = toDesign(mx, my)
    local function hit(r) return r and mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h end
    if G.screen == "menu" then
        if hit(UI.menuField) then
            G.seedFocused = true
            return
        end
        if UI.menuBtns then
            if hit(UI.menuBtns.random) then
                G.menuSeed = randomSeedString()
                return
            end
            if hit(UI.menuBtns.start) and #G.menuSeed > 0 then
                initGame(G.menuSeed) -- enters game screen itself
                return
            end
        end
        return
    end
    if G.state == "over" then
        if hit(UI.overRetry) then initGame(G.seed) end
        if hit(UI.overMenu) then G.screen = "menu" G.menuSeed = G.seed end
        return
    end
    -- mouse only: deck draws when idle; deck OR drawn card discards
    -- while a card awaits decision
    if hit(UI.deckRect) or (G.state == "prompt" and hit(UI.drawnRect)) then
        if G.state == "prompt" then actionToPile()
        elseif #G.deck > 0 then actionDraw() end
        return
    end
    if inside(UI.buttons.retry, mx, my) then initGame(G.seed) return end
    if inside(UI.buttons.tomenu, mx, my) then G.screen = "menu" G.menuSeed = G.seed return end
    if G.state == "prompt" then
        -- walk by hand slot…
        for i, r in ipairs(UI.handRects) do
            if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
                actionWalk(i)
                return
            end
        end
        -- …or by BLACK map cell / black joker (same slot underneath)
        local function walkKey(key)
            local slot = slotOfKey(key)
            if slot then actionWalk(slot) return true end
            return false
        end
        for _, r in ipairs(UI.boardRects or {}) do
            if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
                if walkKey(r.key) then return end
            end
        end
        for _, r in ipairs(UI.portalRects or {}) do
            if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
                if walkKey(r.key) then return end
            end
        end
    end
end

function love.keypressed(key)
    -- DEV ZOOM preview (any screen, even while typing a seed): F1 auto,
    -- F2/F3/F4 force 1x/2x/3x, -/= step down/up, 0 resets to auto.
    if key == "f1" or key == "0" then ZoomOverride = nil
    elseif key == "f2" then ZoomOverride = 1.0
    elseif key == "f3" then ZoomOverride = 2.0
    elseif key == "f4" then ZoomOverride = 3.0
    elseif key == "-" or key == "kp-" then
        local s = select(1, getView())
        ZoomOverride = math.max(1.0, s - 0.5)
    elseif key == "=" or key == "+" or key == "kp+" then
        local s = select(1, getView())
        ZoomOverride = math.min(4.0, s + 0.5)
    end
    -- typing belongs to the menu seed box only; gameplay stays mouse-only.
    if G.screen == "menu" and G.seedFocused then
        if key == "backspace" then
            G.menuSeed = G.menuSeed:sub(1, -2)
        elseif key == "return" or key == "kpenter" then
            if #G.menuSeed > 0 then initGame(G.menuSeed) end
        elseif key == "escape" then
            G.seedFocused = false
        end
    end
end

function love.textinput(t)
    if G.screen ~= "menu" or not G.seedFocused then return end
    t = t:upper()
    if #G.menuSeed < SEED_MAXLEN and t:match("^[A-Z0-9]$") then
        G.menuSeed = G.menuSeed .. t
    end
end
