local _, MySlot = ...

local L = MySlot.L

local crc32 = MySlot.crc32
local base64 = MySlot.base64

local pblua = MySlot.luapb
local _MySlot = pblua.load_proto_ast(MySlot.ast)


local MYSLOT_AUTHOR = "Boshi Lian <farmer1992@gmail.com>"

local MYSLOT_VER = 42

-- TWW Beta Compat code (fix and cleanup below later)
-- TWW Beta Compat code (fix and cleanup below later)
local PickupSpell = C_Spell and C_Spell.PickupSpell or _G.PickupSpell
local PickupItem = C_Item and C_Item.PickupItem or _G.PickupItem
local GetSpellInfo = C_Spell and C_Spell.GetSpellName or _G.GetSpellInfo
local GetSpellLink = C_Spell and C_Spell.GetSpellLink or _G.GetSpellLink
local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) and C_AddOns.GetAddOnMetadata or _G.GetAddOnMetadata
local GetNumMacros = _G.GetNumMacros
local GetMacroInfo = _G.GetMacroInfo
local GetNumMacroIcons = _G.GetNumMacroIcons
local GetMacroIconInfo = _G.GetMacroIconInfo
local CreateMacro = _G.CreateMacro
local PickupMacro = _G.PickupMacro
local GetBinding = _G.GetBinding
local GetNumBindings = _G.GetNumBindings
local GetSpellTabInfo = _G.GetSpellTabInfo
local GetNumSpellTabs = _G.GetNumSpellTabs

-- 3.3.5a Bitwise Fallback (only for macro logic)
local bit_band = (bit and bit.band) or function(a, b)
    if a == 0 or b == 0 then return 0 end
    if a == b or a == 3 then return b end
    if b == 3 then return a end
    return 0
end
local bit_bor = (bit and bit.bor) or function(a, b)
    if a == 0 then return b end
    if b == 0 then return a end
    if a == 3 or b == 3 or a ~= b then return 3 end
    return a
end

-- 3.3.5a Shim for PickupSpellBookItem
local function PickupSpellBookItem(index, bookType)
    if C_SpellBook and C_SpellBook.PickupSpellBookItem then
        C_SpellBook.PickupSpellBookItem(index, bookType == "spell" and Enum.SpellBookSpellBank.Player or Enum.SpellBookSpellBank.Pet)
    elseif _G.PickupSpellBookItem then
        _G.PickupSpellBookItem(index, bookType)
    elseif _G.PickupSpell then
        _G.PickupSpell(index, bookType)
    end
end

-- 3.3.5a Compat
local GetNumEquipmentSets = C_EquipmentSet and C_EquipmentSet.GetNumEquipmentSets or _G.GetNumEquipmentSets
local GetEquipmentSetInfo = C_EquipmentSet and C_EquipmentSet.GetEquipmentSetInfo or _G.GetEquipmentSetInfo

local MAX_ACCOUNT_MACROS = _G.MAX_ACCOUNT_MACROS or 36
local MAX_CHARACTER_MACROS = _G.MAX_CHARACTER_MACROS or 18
-- 3.3.5a Compat End
-- TWW Beta Compat End

-- local MYSLOT_IS_DEBUG = true
local MYSLOT_LINE_SEP = IsWindowsClient() and "\r\n" or "\n"
local MYSLOT_MAX_ACTIONBAR = (GetNumSpellTabs or GetSpellTabInfo) and 120 or 180

-- {{{ SLOT TYPE
local MYSLOT_SPELL = _MySlot.Slot.SlotType.SPELL
local MYSLOT_COMPANION = _MySlot.Slot.SlotType.COMPANION
local MYSLOT_ITEM = _MySlot.Slot.SlotType.ITEM
local MYSLOT_MACRO = _MySlot.Slot.SlotType.MACRO
local MYSLOT_FLYOUT = _MySlot.Slot.SlotType.FLYOUT
local MYSLOT_EQUIPMENTSET = _MySlot.Slot.SlotType.EQUIPMENTSET
local MYSLOT_EMPTY = _MySlot.Slot.SlotType.EMPTY
local MYSLOT_SUMMONPET = _MySlot.Slot.SlotType.SUMMONPET
local MYSLOT_SUMMONMOUNT = _MySlot.Slot.SlotType.SUMMONMOUNT
local MYSLOT_NOTFOUND = "notfound"

MySlot.SLOT_TYPE = {
    ["spell"] = MYSLOT_SPELL,
    ["companion"] = MYSLOT_COMPANION,
    ["macro"] = MYSLOT_MACRO,
    ["item"] = MYSLOT_ITEM,
    ["flyout"] = MYSLOT_FLYOUT,
    ["petaction"] = MYSLOT_EMPTY,
    ["futurespell"] = MYSLOT_EMPTY,
    ["equipmentset"] = MYSLOT_EQUIPMENTSET,
    ["summonpet"] = MYSLOT_SUMMONPET,
    ["summonmount"] = MYSLOT_SUMMONMOUNT,
    [MYSLOT_NOTFOUND] = MYSLOT_EMPTY,
}
-- }}}

local MYSLOT_BIND_CUSTOM_FLAG = 0xFFFF

-- {{{ MergeTable
-- return item count merge into target
local function MergeTable(target, source)
    if source then
        assert(type(target) == 'table' and type(source) == 'table')
        for _, b in ipairs(source) do
            assert(b < 256)
            target[#target + 1] = b
        end
        return #source
    else
        return 0
    end
end
-- }}}

-- fix unpack stackoverflow
local function StringToTable(s)
    if type(s) ~= 'string' then
        return {}
    end
    local r = {}
    for i = 1, string.len(s) do
        r[#r + 1] = string.byte(s, i)
    end
    return r
end

local function TableToString(s)
    if type(s) ~= 'table' then
        return ''
    end
    local t = {}
    for _, c in pairs(s) do
        t[#t + 1] = string.char(c)
    end
    return table.concat(t)
end

local function CreateSpellOverrideMap()
    local spellOverride = {}

    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        -- 11.0 only
        for skillLineIndex = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex)
            for i = 1, skillLineInfo.numSpellBookItems do
                local spellIndex = skillLineInfo.itemIndexOffset + i
                local spellType, id, spellId = C_SpellBook.GetSpellBookItemType(spellIndex, Enum.SpellBookSpellBank.Player)
                if spellId then
                    local newid = C_Spell.GetOverrideSpell(spellId)
                    if newid ~= spellId then
                        spellOverride[newid] = spellId
                    end
                elseif spellType == Enum.SpellBookItemType.Flyout then
                    local _, _, numSlots, isKnown = GetFlyoutInfo(id);
                    if isKnown and (numSlots > 0) then
                        for k = 1, numSlots do
                            local spellID, overrideSpellID = GetFlyoutSlotInfo(id, k)
                            spellOverride[overrideSpellID] = spellID
                        end
                    end
                end
            end
        end
    end

    if GetNumSpecGroups and MAX_TALENT_TIERS and NUM_TALENT_COLUMNS then
        local isInspect = false
        for specIndex = 1, GetNumSpecGroups(isInspect) do
            for tier = 1, MAX_TALENT_TIERS do
                for column = 1, NUM_TALENT_COLUMNS do
                    local spellId = select(6, GetTalentInfo(tier, column, specIndex))
                    if spellId and C_Spell and C_Spell.GetOverrideSpell then
                        local newid = C_Spell.GetOverrideSpell(spellId)
                        if newid ~= spellId then
                            spellOverride[newid] = spellId
                        end
                    end
                end
            end
        end
    end

    if C_SpecializationInfo and C_SpecializationInfo.GetPvpTalentSlotInfo and C_Spell and C_Spell.GetOverrideSpell then
        for pvpTalentSlot = 1, 3 do
            local slotInfo = C_SpecializationInfo.GetPvpTalentSlotInfo(pvpTalentSlot)
            if slotInfo ~= nil then
                for i, pvpTalentID in ipairs(slotInfo.availableTalentIDs) do
                    local spellId = select(6, GetPvpTalentInfoByID(pvpTalentID))
                    if spellId then
                        local newid = C_Spell.GetOverrideSpell(spellId)
                        if newid ~= spellId then
                            spellOverride[newid] = spellId
                        end
                    end
                end
            end
        end
    end

    return spellOverride
end

function MySlot:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|CFFFF0000<|r|CFFFFD100Myslot|r|CFFFF0000>|r" .. (msg or "nil"))
end

-- {{{ GetMacroInfo
function MySlot:GetMacroInfo(macroId)
    -- {macroId ,icon high 8, icon low 8 , namelen, ..., bodylen, ...}

    local name, iconTexture, body  = GetMacroInfo(macroId)

    if not name then
        return nil
    end

    if type(iconTexture) == 'number' then
        iconTexture = tostring(iconTexture)
    end
    iconTexture = gsub(strupper(iconTexture or "INV_Misc_QuestionMark"), "INTERFACE\\ICONS\\", "")

    local msg = _MySlot.Macro()
    msg.id = macroId
    msg.icon = iconTexture
    msg.name = name
    msg.body = body

    return msg
end

-- }}}

-- {{{ GetActionInfo
function MySlot:GetActionInfo(slotId)
    local slotType, index, subType = GetActionInfo(slotId)
    if MySlot.SLOT_TYPE[slotType] == MYSLOT_EQUIPMENTSET then
        -- i starts from 0 https://github.com/tg123/myslot/issues/10 weird blz
        if GetNumEquipmentSets then
            for i = 0, GetNumEquipmentSets() do
                if GetEquipmentSetInfo(i) == index then
                    index = i
                    break
                end
            end
        end
    elseif not MySlot.SLOT_TYPE[slotType] then
        if slotType then
            self:Print(L["[WARN] Ignore unsupported Slot Type [ %s ] , contact %s please"]:format(slotType, MYSLOT_AUTHOR))
        end
        return nil
    elseif slotType == "macro" and subType then
        PickupAction(slotId)
        _, index = GetCursorInfo()
        PlaceAction(slotId)
    elseif not index then
        return nil
    end

    local msg = _MySlot.Slot()
    msg.id = slotId
    msg.type = MySlot.SLOT_TYPE[slotType]
    if type(index) == 'string' then
        msg.strindex = index
        msg.index = 0
    elseif slotType == "companion" then
        if GetCompanionInfo then
            local _, _, spellId = GetCompanionInfo(subType, index)
            msg.index = spellId or index
        else
            msg.index = index
        end
        msg.strindex = subType -- MOUNT or CRITTER
    elseif slotType == "spell" then
        local spellId = 0
        if _G.GetActionSpellID then
            spellId = _G.GetActionSpellID(slotId)
        end
        if (not spellId or spellId == 0) and GetSpellLink then
            local link = GetSpellLink(index, "spell")
            -- Link format: |Hspell:49896|h... or |Hspell:49896:rank|h...
            spellId = link and tonumber(string.match(link, "spell:(%d+)"))
        end
        msg.index = (spellId and spellId ~= 0) and spellId or index
    else
        msg.index = index
    end
    return msg
end

-- }}}

function MySlot:GetPetActionInfo(slotId)
    local name, _, isToken, _, _, _, spellID = GetPetActionInfo(slotId)

    local msg = _MySlot.Slot()
    msg.id = slotId
    msg.type = MYSLOT_SPELL

    if isToken then
        msg.strindex = name
        msg.index = 0
    elseif name then
        -- 3.3.5a pet spells often don't have IDs in GetPetActionInfo
        local link = GetSpellLink(name)
        local spellId = link and tonumber(string.match(link, "spell:(%d+)"))
        msg.strindex = name
        msg.index = spellId or (type(spellID) == "number" and spellID) or 0
    elseif not name then
        msg.index = 0
        msg.type = MYSLOT_EMPTY
    else
        return nil
    end

    return msg
end

-- {{{ GetBindingInfo
-- {{{ Serialzie Key
local function KeyToByte(key, command)
    if not key then return nil end

    local mods = {}
    local finalKey = key
    
    -- Extract all modifiers (SHIFT-, CTRL-, ALT-, META-)
    while true do
        local mStart, mEnd, mod = string.find(finalKey, "^([^-]+)%-")
        if mod then
            table.insert(mods, mod:upper())
            finalKey = string.sub(finalKey, mEnd + 1)
        else
            break
        end
    end

    table.sort(mods)
    local modStr = table.concat(mods, "-")
    if modStr == "" then modStr = "NONE" end

    if not MySlot.MOD_KEYS[modStr] then
        -- Try to reconstruct if sorted version missing, but protocol usually prefers sorted
        MySlot:Print(L["[WARN] Ignore unsupported Key Binding [ %s ] , contact %s please"]:format(modStr, MYSLOT_AUTHOR))
        return nil
    end

    local msg = _MySlot.Key()
    if MySlot.KEYS[finalKey] then
        msg.key = MySlot.KEYS[finalKey]
    else
        msg.key = MySlot.KEYS["KEYCODE"]
        msg.keycode = finalKey
    end
    msg.mod = MySlot.MOD_KEYS[modStr]

    return msg
end
-- }}}

function MySlot:GetBindingInfo(index)
    -- might more than 1
    local _command, key1, key2
    if C_KeyBindings then
        _command, _, key1, key2 = GetBinding(index)
    else
        _command, key1, key2 = GetBinding(index)
    end

    if not _command then
        return
    end

    local command = MySlot.BINDS[_command]

    local msg = _MySlot.Bind()

    if not command then
        msg.command = _command
        command = MYSLOT_BIND_CUSTOM_FLAG
    end

    msg.id = command

    msg.key1 = KeyToByte(key1)
    msg.key2 = KeyToByte(key2)

    if msg.key1 or msg.key2 then
        return msg
    else
        return nil
    end
end

-- }}}

local function GetTalentTreeString()
    -- maybe classic
    if GetTalentTabInfo then

        -- wlk
        if GetTalentTabInfo(1) and tonumber(select(3, GetTalentTabInfo(1)), 10) then
            local t1 = select(3, GetTalentTabInfo(1)) or 0
            local t2 = select(3, GetTalentTabInfo(2)) or 0
            local t3 = select(3, GetTalentTabInfo(3)) or 0
            return t1 .. "/" .. t2 .. "/" .. t3
        end

        -- other
        if tonumber(select(5, GetTalentTabInfo(1)), 10) then
            return select(5, GetTalentTabInfo(1)) ..  "/" .. select(5, GetTalentTabInfo(2)) .. "/" .. select(5, GetTalentTabInfo(3))
        end
    end

    -- 11.0
    if PlayerSpellsFrame_LoadUI then
        PlayerSpellsFrame_LoadUI()

        -- no talent yet
        if not PlayerSpellsFrame.TalentsFrame:GetConfigID() then
            return nil
        end

        PlayerSpellsFrame.TalentsFrame:UpdateTreeInfo()
        if PlayerSpellsFrame.TalentsFrame:GetLoadoutExportString() then
            return PlayerSpellsFrame.TalentsFrame:GetLoadoutExportString()
        end
    end

    return nil
end

function MySlot:Export(opt)
    -- ver nop nop nop crc32 crc32 crc32 crc32

    local msg = _MySlot.Charactor()

    msg.ver = MYSLOT_VER
    msg.name = UnitName("player")

    msg.macro = {}

    local numAccount, numCharacter = 0, 0
    if GetNumMacros then
        numAccount, numCharacter = GetNumMacros()
    end

    if not opt.ignoreMacros["ACCOUNT"] then
        for i = 1, MAX_ACCOUNT_MACROS do
            local name = GetMacroInfo(i)
            if name then
                local m = self:GetMacroInfo(i)
                if m then
                    msg.macro[#msg.macro + 1] = m
                end
            end
        end
    end

    if not opt.ignoreMacros["CHARACTOR"] then
        -- In 3.3.5a character macros start after account macros (usually at index 37)
        for i = MAX_ACCOUNT_MACROS + 1, MAX_ACCOUNT_MACROS + MAX_CHARACTER_MACROS do
            local name = GetMacroInfo(i)
            if name then
                local m = self:GetMacroInfo(i)
                if m then
                    msg.macro[#msg.macro + 1] = m
                end
            end
        end
    end

    msg.slot = {}
    -- TODO move to GetActionInfo
    local spellOverride = CreateSpellOverrideMap()

    for i = 1, MYSLOT_MAX_ACTIONBAR do
        if not opt.ignoreActionBars[math.ceil(i / 12)] then
            local m = self:GetActionInfo(i)
            if m then
                if m.type == 'SPELL' then
                    if spellOverride[m.index] then
                        m.index = spellOverride[m.index]
                    end
                end
                msg.slot[#msg.slot + 1] = m
            end
        end

    end

    msg.bind = {}
    if not opt.ignoreBinding then
        for i = 1, GetNumBindings() do
            local m = self:GetBindingInfo(i)
            if m then
                msg.bind[#msg.bind + 1] = m
            end
        end
    end

    msg.petslot = {}
    if not opt.ignorePetActionBar and (PetHasActionBar and PetHasActionBar()) then
        for i = 1, NUM_PET_ACTION_SLOTS, 1 do
            local m = self:GetPetActionInfo(i)
            if m then
                msg.petslot[#msg.petslot + 1] = m
            end
        end
    end

    local ct = msg:Serialize()
    local t = { MYSLOT_VER, 86, 04, 22, 0, 0, 0, 0 }
    MergeTable(t, StringToTable(ct))

    -- {{{ CRC32
    -- crc
    local crc = crc32.enc(t)
    t[5] = bit.rshift(crc, 24)
    t[6] = bit.band(bit.rshift(crc, 16), 255)
    t[7] = bit.band(bit.rshift(crc, 8), 255)
    t[8] = bit.band(crc, 255)
    -- }}}

    -- {{{ OUTPUT
    local talent = GetTalentTreeString()

    local s = ""
    s = "# --------------------" .. MYSLOT_LINE_SEP .. s
    s = "# " .. L["Feedback"] .. "  farmer1992@gmail.com" .. MYSLOT_LINE_SEP .. s
    s = "# " .. MYSLOT_LINE_SEP .. s
    s = "# " .. (LEVEL or "Level") .. ": " .. UnitLevel("player") .. MYSLOT_LINE_SEP .. s
    if talent then
        s = "# " .. (TALENTS or "Talents") .. ": " .. talent .. MYSLOT_LINE_SEP .. s
    end
    if GetSpecialization and GetSpecializationInfo then
        s = "# " ..
        (SPECIALIZATION or "Specialization") ..
        ": " ..
        (GetSpecialization() and select(2, GetSpecializationInfo(GetSpecialization())) or (NONE_CAPS or "None")) ..
        MYSLOT_LINE_SEP .. s
    end
    s = "# " .. (CLASS or "Class") .. ": " .. UnitClass("player") .. MYSLOT_LINE_SEP .. s
    s = "# " .. (PLAYER or "Player") .. ": " .. UnitName("player") .. MYSLOT_LINE_SEP .. s
    s = "# " .. L["Time"] .. ": " .. date() .. MYSLOT_LINE_SEP .. s

    if GetAddOnMetadata then
        s = "# Addon Version: " .. GetAddOnMetadata("Myslot", "Version") .. MYSLOT_LINE_SEP .. s
    end

    s = "# Wow Version: " .. GetBuildInfo() .. MYSLOT_LINE_SEP .. s
    s = "# Myslot (https://myslot.net " .. L["<- share your profile here"]  ..")" .. MYSLOT_LINE_SEP .. s

    local d = base64.enc(t)
    local LINE_LEN = 60
    for i = 1, d:len(), LINE_LEN do
        s = s .. d:sub(i, i + LINE_LEN - 1) .. MYSLOT_LINE_SEP
    end
    s = strtrim(s)
    s = s .. MYSLOT_LINE_SEP .. "# --------------------"
    s = s .. MYSLOT_LINE_SEP .. "# END OF MYSLOT"

    return s
    -- }}}
end

function MySlot:Import(text, opt)
    if InCombatLockdown() then
        MySlot:Print(L["Import is not allowed when you are in combat"])
        return
    end

    local s = text or ""
    s = string.gsub(s, "(@.[^\n]*\n*)", "")
    s = string.gsub(s, "(#.[^\n]*\n*)", "")
    s = string.gsub(s, "\n", "")
    s = string.gsub(s, "\r", "")
    s = base64.dec(s)

    if #s < 8 then
        MySlot:Print(L["Bad importing text [TEXT]"])
        return
    end

    local force = opt.force

    local ver = s[1]
    local crc = s[5] * 2 ^ 24 + s[6] * 2 ^ 16 + s[7] * 2 ^ 8 + s[8]
    s[5], s[6], s[7], s[8] = 0, 0, 0, 0

    if (crc ~= bit.band(crc32.enc(s), 2 ^ 32 - 1)) then
        MySlot:Print(L["Bad importing text [CRC32]"])
        if force then
            MySlot:Print(L["Skip bad CRC32"] .. " " .. L["Try force importing"])
        else
            return
        end
    end

    local ct = {}
    for i = 9, #s do
        ct[#ct + 1] = s[i]
    end
    ct = TableToString(ct)

    local msg = _MySlot.Charactor():Parse(ct)
    return msg
end

local function UnifyCRLF(text)
    text = string.gsub(text, "\r", "")
    return strtrim(text)
end

-- Find macro by index/name/body
function MySlot:FindMacro(macroInfo)
    if not macroInfo then
        return
    end
    -- cache local macro index
    -- {{{
    local localMacro = {}
    for i = 1, MAX_ACCOUNT_MACROS + MAX_CHARACTER_MACROS do
        local name, _, body = GetMacroInfo(i)
        if name then
            body = UnifyCRLF(body)
            localMacro[name .. "_" .. body] = i
            localMacro[body] = i
        end
    end
    -- }}}


    local name = macroInfo["name"]
    local body = macroInfo["body"]
    body = UnifyCRLF(body)

    -- Return index if found or nil
    return localMacro[name .. "_" .. body] or localMacro[body]
end

-- {{{ FindOrCreateMacro
function MySlot:FindOrCreateMacro(macroInfo)
    if not macroInfo then
        return
    end

    local localIndex = MySlot:FindMacro(macroInfo)
    if localIndex then
        return localIndex
    else
        local id = macroInfo["oldid"]
        local name = macroInfo["name"]
        local icon = macroInfo["icon"]
        local body = macroInfo["body"]
        body = UnifyCRLF(body)

        local numglobal, numperchar = GetNumMacros()
        local perchar = id > MAX_ACCOUNT_MACROS and 2 or 1

        --[[
            perchar    G = 01 P = 10
            testallow  allow 01 | allow 10 = 00 , 01 , 10 , 11
            perchar & testallow = 01 , 10 , 00
            perchar = testallow when not allow
        ]]
        local testallow = bit_bor(numglobal < MAX_ACCOUNT_MACROS and 1 or 0, numperchar < MAX_CHARACTER_MACROS and 2 or 0)
        perchar = bit_band(perchar, testallow)
        perchar = perchar == 0 and testallow or perchar

        if perchar ~= 0 then
            -- fix icon using #showtooltip

            if strsub(body, 0, 12) == '#showtooltip' then
                icon = 'INV_Misc_QuestionMark'
            end
            local iconIndex = 1
            if tonumber(icon) then
                iconIndex = tonumber(icon)
            else
                local iconUpper = tostring(icon or "INV_Misc_QuestionMark"):upper()
                for i = 1, GetNumMacroIcons() do
                    local texture = GetMacroIconInfo(i)
                    if texture and texture:upper():find(iconUpper, 1, true) then
                        iconIndex = i
                        break
                    end
                end
            end

            local newid = CreateMacro(name, iconIndex, body, perchar >= 2 and 1 or nil)
            if newid then
                return newid
            end
        end

        self:Print(L["Macro %s was ignored, check if there is enough space to create"]:format(name))
        return nil
    end
end
-- }}}


local function CreateFlyoutSpellbookMap()
    local flyouts = {}

    if SPELLS_PER_PAGE then
        for i = 1, GetNumSpellTabs() do
            local tab, tabTex, offset, numSpells, isGuild, offSpecID = GetSpellTabInfo(i)
            offSpecID = (offSpecID ~= 0)
            if not offSpecID then
                offset = offset + 1
                local tabEnd = offset + numSpells
                for j = offset, tabEnd - 1 do
                    local spellType, spellId = GetSpellBookItemInfo(j, BOOKTYPE_SPELL)
                    if spellType == "FLYOUT" then
                        local slot = j + (SPELLS_PER_PAGE * (SPELLBOOK_PAGENUMBERS[i] - 1))
                        flyouts[spellId] = { slot, BOOKTYPE_SPELL }
                    end
                end
            end
        end
    end

    if BOOKTYPE_PROFESSION then
        if GetProfessions then
            for _, p in pairs({ GetProfessions() }) do
                local _, _, _, _, numSpells, spelloffset = GetProfessionInfo(p)
                for i = 1, numSpells do
                    local slot = i + spelloffset
                    local spellType, spellId = GetSpellBookItemInfo(slot, BOOKTYPE_PROFESSION)
                    if spellType == "FLYOUT" then
                        flyouts[spellId] = { slot, BOOKTYPE_PROFESSION }
                    end
                end
            end
        end
    end

    -- 11.0 only
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        for skillLineIndex = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex)
            for i = 1, skillLineInfo.numSpellBookItems do
                local spellIndex = skillLineInfo.itemIndexOffset + i
                local spellTypeEnum, spellId = C_SpellBook.GetSpellBookItemType(spellIndex, Enum.SpellBookSpellBank.Player);
                if spellId and spellTypeEnum == Enum.SpellBookItemType.Flyout then
                    flyouts[spellId] = { spellIndex, Enum.SpellBookSpellBank.Player }
                end
            end
        end
    end

    return flyouts
end

function MySlot:RecoverData(msg, opt)
    -- {{{ Cache Spells
    --cache spells
    local spellOverride = CreateSpellOverrideMap()
    local flyouts = CreateFlyoutSpellbookMap()
    -- }}}


    -- {{{ cache mounts
    local mounts = {}
    if C_MountJournal then
        for i = 1, C_MountJournal.GetNumMounts() do
            local _, _, _, _, _, _, _, _, _, _, isCollected, mountId = C_MountJournal.GetDisplayedMountInfo(i)
            if isCollected then
                mounts[mountId] = i
            end
        end
    elseif GetNumCompanions then
        -- 3.3.5a fallback
        for i = 1, GetNumCompanions("MOUNT") do
             local _, _, spellId = GetCompanionInfo("MOUNT", i)
             mounts[spellId] = i
        end
    end
    -- }}}

    -- {{{ cache critters
    local critters = {}
    if GetNumCompanions then
        for i = 1, GetNumCompanions("CRITTER") do
             local _, _, spellId = GetCompanionInfo("CRITTER", i)
             critters[spellId] = i
        end
    end
    -- }}}

    -- {{{ cache spellbook for 3.3.5a
    local spellbookMap = {}
    if GetNumSpellTabs then
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, numSpells = GetSpellTabInfo(tab)
            for i = 1, numSpells do
                local index = offset + i
                local link = GetSpellLink(index, "spell")
                local spellId = link and tonumber(string.match(link, "spell:(%d+)"))
                if spellId then
                    spellbookMap[spellId] = index
                end
            end
        end
    end

    local petbookMap = {}
    if HasPetSpells and type(HasPetSpells) == "function" then
        local numPetSpells = HasPetSpells()
        if numPetSpells and numPetSpells > 0 then
            for i = 1, numPetSpells do
                local link = GetSpellLink(i, "pet")
                local spellId = link and tonumber(string.match(link, "spell:(%d+)"))
                if spellId then
                    petbookMap[spellId] = i
                end
            end
        end
    end
    -- }}}

    if msg.name then
        DEFAULT_CHAT_FRAME:AddMessage("|CFFFF0000<|r|CFFFFD100Myslot|r|CFFFF0000>|r" .. L["Importing profile from %s"]:format(msg.name))
    end

    local slotBucket = {}

    -- {{{ Macro
    local macro = {}

    for _, s in pairs(msg.slot or {}) do
        local slotId = s.id
        local slotType = _MySlot.Slot.SlotType[s.type]
        local index = s.index

        if slotType == MYSLOT_MACRO then
            if macro[index] then
                table.insert(macro[index], slotId)
            else
                macro[index] = {slotId}
            end
        end
    end

    for _, m in pairs(msg.macro or {}) do
        local macroId = m.id
        local icon = m.icon

        local name = m.name
        local body = m.body

        local info = {
            ["oldid"] = macroId,
            ["name"] = name,
            ["icon"] = icon,
            ["body"] = body,
        }

        local newid = nil

        if (not opt.actionOpt.ignoreMacros["ACCOUNT"] and macroId <= MAX_ACCOUNT_MACROS)
        or (not opt.actionOpt.ignoreMacros["CHARACTOR"] and macroId > MAX_ACCOUNT_MACROS)
        then
            newid = self:FindOrCreateMacro(info)
        end

        if not newid then
            newid = self:FindMacro(info)
        end

        if newid then
            for _, slotId in pairs(macro[macroId] or {}) do
                if not opt.actionOpt.ignoreActionBars[math.ceil(slotId / 12)] then
                    PickupMacro(newid)
                    PlaceAction(slotId)
                end
            end
        else
            MySlot:Print(L["Ignore unknown macro [id=%s]"]:format(macroId))
        end
    end
    -- Support for 3.3.5a UI Refresh
    if _G.MacroFrame_Update and _G.MacroFrame and _G.MacroFrame:IsShown() then
        _G.MacroFrame_Update()
    end
    -- }}} Macro


    for _, s in pairs(msg.slot or {}) do
        local slotId = s.id
        local slotType = _MySlot.Slot.SlotType[s.type]
        local index = s.index
        local strindex = s.strindex

        local curType, curIndex = GetActionInfo(slotId)
        curType = MySlot.SLOT_TYPE[curType or MYSLOT_NOTFOUND]
        slotBucket[slotId] = true

        if not pcall(function()

                if opt.actionOpt.ignoreActionBars[math.ceil(slotId / 12)] then
                    return
                end

                if curIndex ~= index or curType ~= slotType then
                    if slotType == MYSLOT_SPELL then
                        local picked = false
                        if index > 0 then
                            if spellbookMap[index] then
                                PickupSpellBookItem(spellbookMap[index], "spell")
                                picked = true
                            elseif petbookMap[index] then
                                PickupSpellBookItem(petbookMap[index], "pet")
                                picked = true
                            elseif mounts[index] then
                                PickupCompanion("MOUNT", mounts[index])
                                picked = true
                            elseif critters[index] then
                                PickupCompanion("CRITTER", critters[index])
                                picked = true
                            end
                        end

                        if not picked and not GetCursorInfo() and index > 0 then
                            -- Fallback to name/direct ID only if map failed
                            -- In 3.3.5a, PickupSpell(id) treats id as index. 
                            -- If index > 10000, it's definitely a SpellID, so we get the name first.
                            local spellName = GetSpellInfo(index)
                            if spellName then
                                PickupSpell(spellName)
                            end
                        end

                        -- try if override
                        if not GetCursorInfo() then
                            if spellOverride[index] then
                                if spellbookMap[spellOverride[index]] then
                                    PickupSpellBookItem(spellbookMap[spellOverride[index]], "spell")
                                else
                                    PickupSpell(spellOverride[index])
                                end
                            end
                        end

                        -- this fallback should not happen, only to workaround some old export
                        if not GetCursorInfo() then
                            local spellName = GetSpellInfo(index)
                            if spellName then
                                PickupSpell(spellName)
                            end
                        end

                        -- another fallback option - try to get base spell
                        if not GetCursorInfo() and FindBaseSpellByID then
                            local baseSpellId = FindBaseSpellByID(index)
                            if baseSpellId then
                                PickupSpell(baseSpellId)
                            end
                        end

                        if not GetCursorInfo() and index ~= 0 then
                            -- One last attempt by name for 3.3.5a
                            local spellName = GetSpellInfo(index)
                            if spellName then
                                PickupSpell(spellName)
                            end
                        end

                        if not GetCursorInfo() and index ~= 0 then
                            MySlot:Print(L["Ignore unlearned skill [id=%s], %s"]:format(index, GetSpellLink(index) or ""))
                        end
                    elseif slotType == MYSLOT_FLYOUT then
                        local flyout = flyouts[index]
                        if flyout then
                            PickupSpellBookItem(flyout[1], flyout[2])
                        end

                        if not GetCursorInfo() then
                            MySlot:Print(L["Ignore unlearned skill [flyoutid=%s], %s"]:format(index, GetFlyoutInfo(index) or ""))
                        end

                    elseif slotType == MYSLOT_COMPANION then
                        if GetNumCompanions and strindex then
                            -- 3.3.5a
                            local companionIndex = (strindex == "MOUNT") and mounts[index] or critters[index]
                            if companionIndex then
                                PickupCompanion(strindex, companionIndex)
                            end
                        else
                            PickupSpell(index)
                        end

                        if not GetCursorInfo() then
                            MySlot:Print(L["Ignore unattained companion [id=%s], %s"]:format(index, GetSpellLink(index) or ""))
                        end
                    elseif slotType == MYSLOT_ITEM then
                        PickupItem(index)

                        if not GetCursorInfo() then
                            MySlot:Print(L["Ignore missing item [id=%s]"]:format(index)) -- TODO add item link
                        end
                    elseif slotType == MYSLOT_SUMMONPET and strindex and strindex ~= curIndex then
                        if C_PetJournal and C_PetJournal.PickupPet then
                            C_PetJournal.PickupPet(strindex, false)
                            if not GetCursorInfo() then
                                C_PetJournal.PickupPet(strindex, true)
                            end
                        end
                        if not GetCursorInfo() then
                            MySlot:Print(L["Ignore unattained pet [id=%s]"]:format(strindex))
                        end
                    elseif slotType == MYSLOT_SUMMONMOUNT then
                        index = mounts[index]
                        if index and C_MountJournal and C_MountJournal.Pickup then
                            C_MountJournal.Pickup(index)
                        elseif C_MountJournal and C_MountJournal.Pickup then
                            C_MountJournal.Pickup(0)
                            MySlot:Print(L["Use random mount instead of an unattained mount"])
                        else
                            MySlot:Print(L["Ignore unattained mount [id=%s]"]:format(index or 0))
                        end
                    elseif slotType == MYSLOT_EMPTY then
                        PickupAction(slotId)
                    elseif slotType == MYSLOT_EQUIPMENTSET then
                        if C_EquipmentSet and C_EquipmentSet.PickupEquipmentSet then
                            C_EquipmentSet.PickupEquipmentSet(index)
                        elseif _G.PickupEquipmentSet then
                            _G.PickupEquipmentSet(index)
                        end
                    end

                    if GetCursorInfo() then
                        PlaceAction(slotId)
                    end
                    ClearCursor()
                end
            end) then
            MySlot:Print(L["[WARN] Ignore slot due to an unknown error DEBUG INFO = [S=%s T=%s I=%s] Please send Importing Text and DEBUG INFO to %s"]:format(slotId, slotType, index, MYSLOT_AUTHOR))
        end
    end

    for i = 1, MYSLOT_MAX_ACTIONBAR do
        if not opt.actionOpt.ignoreActionBars[math.ceil(i / 12)] and not slotBucket[i] then
            if GetActionInfo(i) then
                PickupAction(i)
                ClearCursor()
            end
        end
    end

    if not opt.actionOpt.ignoreBinding then

        for _, b in pairs(msg.bind or {}) do
            local command = b.command
            if b.id ~= MYSLOT_BIND_CUSTOM_FLAG then
                command = MySlot.R_BINDS[b.id]
            end

            if b.key1 then
                local mod, key = MySlot.R_MOD_KEYS[b.key1.mod], MySlot.R_KEYS[b.key1.key]
                if key == "KEYCODE" then
                    key = b.key1.keycode
                end
                key = (mod ~= "NONE" and (mod .. "-") or "") .. key
                local bindingContext = 1

                if C_KeyBindings and C_KeyBindings.GetBindingContextForAction then
                     bindingContext = C_KeyBindings.GetBindingContextForAction(command)
                     SetBinding(key, command, bindingContext)
                else
                     SetBinding(key, command)
                end
            end

            if b.key2 then
                local mod, key = MySlot.R_MOD_KEYS[b.key2.mod], MySlot.R_KEYS[b.key2.key]
                if key == "KEYCODE" then
                    key = b.key2.keycode
                end
                local fullKey = (mod ~= "NONE" and (mod .. "-") or "") .. key
                if C_KeyBindings and C_KeyBindings.GetBindingContextForAction then
                     local bindingContext = C_KeyBindings.GetBindingContextForAction(command)
                     SetBinding(fullKey, command, bindingContext)
                else
                     SetBinding(fullKey, command)
                end
            end
        end
        SaveBindings(GetCurrentBindingSet())
    end


    if not opt.actionOpt.ignorePetActionBar and (PetHasActionBar and PetHasActionBar()) then
        local pettoken = {}
        for i = 1, NUM_PET_ACTION_SLOTS, 1 do
            local name, _, isToken = GetPetActionInfo(i)
            if isToken then
                pettoken[name] = i
            end
        end

        for _, p in pairs(msg.petslot or {}) do
            local found = false
            if p.strindex then
                local slot = pettoken[p.strindex]
                if slot then
                    PickupPetAction(slot)
                    found = true
                elseif petbookMap then
                    -- Search in pet spellbook by name if ID/Token fails
                    for id, index in pairs(petbookMap) do
                        local name = GetSpellLink(index, "pet")
                        name = name and string.match(name, "%[(.+)%]")
                        if name == p.strindex then
                            PickupPetSpell(index)
                            found = true
                            break
                        end
                    end
                end
            elseif p.index and p.index ~= 0 then
                if petbookMap and petbookMap[p.index] then
                    PickupPetSpell(petbookMap[p.index])
                    found = true
                else
                    PickupPetSpell(p.index)
                    found = GetCursorInfo() == "spell"
                end
            elseif p.type == MYSLOT_EMPTY then
                PickupPetAction(p.id)
                found = true
            end

            if found then
                PickupPetAction(p.id)
            end
            ClearCursor()
        end
    end


    MySlot:Print(L["All slots were restored"])
end

function MySlot:Clear(what, opt)
    if what == "ACTION" then
        for i = 1, MYSLOT_MAX_ACTIONBAR do
            if opt[math.ceil(i / 12)] then
                PickupAction(i)
                ClearCursor()
            end
        end
    elseif what == "MACRO" then
        if opt["ACCOUNT"] then
            for i = MAX_ACCOUNT_MACROS, 1, -1   do
                DeleteMacro(i)
            end
        end

        if opt["CHARACTOR"] then
            for i = MAX_ACCOUNT_MACROS + MAX_CHARACTER_MACROS,  MAX_ACCOUNT_MACROS + 1, -1 do
                DeleteMacro(i)
            end
        end
    elseif what == "BINDING" then
        for i = 1, GetNumBindings() do
            local action, key1, key2
            if C_KeyBindings then
                action, _, key1, key2 = GetBinding(i)
            else
                action, key1, key2 = GetBinding(i)
            end

            for _, key in pairs({ key1, key2 }) do
                if key then
                    if C_KeyBindings and C_KeyBindings.GetBindingContextForAction then
                        local bindingContext = C_KeyBindings.GetBindingContextForAction(action)
                        SetBinding(key, nil, bindingContext)
                    else
                        SetBinding(key, nil)
                    end
                end
            end
        end
        SaveBindings(GetCurrentBindingSet())
    end
end
