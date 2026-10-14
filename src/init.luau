--!strict
--!native
--[[
@tes3merge: TES3Merge's object merging, as a function of (state, openmw), openmw being the load
order's config from `@openmw`'s `new`.

Options, from `state.tes3merge`:
  recordTypes    { string }            [RecordTypes]
  records        { string }            --records
  ignoreRecords  { string }            --ignore-records
  fileFilters    { [string]: boolean } [FileFilters]; false skips a file
  objectFilters  { { string | boolean } }  [ObjectFilters]; { pattern, allow }, last match wins
  inclusive      boolean               --inclusive
  noMasters      boolean               --no-masters
  patches        { string }            --patches; fogbug, summons, cellnames, all, none; default { "all" }
  encoding       string | number       [General] TextEncodingCode; default openmw.cfg's encoding=
  fileName       string                default "Merged Objects.esp"
  outputDir      string                default data-local, else the first data folder
  activate       boolean               enable the result in openmw.cfg; skipped when outputDir isn't a data folder
  verbose        boolean

Afterwards `state.tes3merge.report` holds { path, masters, files, candidates, merged, failed, activated }.

Ported from TES3Merge (https://github.com/NullCascade/TES3Merge):

The MIT License

Copyright (c) 2019 NullCascade

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local intern = require '@dream/intern'
local loadOrder = require '@load-order'
local openmw = require '@openmw'
local tes3 = require '@tes3'

type Context = openmw.Context
type Key = string | number
type Value = boolean | number | string | Table
type Table = { [Key]: Value }
type Set = { [string]: boolean }
type Merger = (current: Table, first: Table, later: Table, key: string) -> boolean

-- The records of one type that are up for merging. Each identity, an id whatever its ASCII case,
-- is a number from `ids`: 1 up, in the order first seen. Under it `definitions` holds the records
-- that have it, in load order, a lone one as it is and more as a list; and `needsFog`, which only
-- cells have, whether the fog patch would change the last of them. A record is one number: the
-- place of its plugin among the opened ones times `Stride`, plus its index there.
type Kind = {
  tag: string,
  ids: dream_intern_Pool,
  definitions: { number | { number } },
  needsFog: { boolean }?,
}

local Stride = 0x100000000

-- A leveled list's entry, and how many times the list that has the most of it has it.
type Tally = { entry: Table, count: number }

-- An object filter, read once: whether a record's id is one it names, and whether it keeps them.
type ObjectFilter = { regex: Regex, allow: boolean }

-- What the tool reads of a record before it merges it, as `plugin:decode` gives them.
type Creature = { id: string, flags: string }
type Cell = {
  data: { flags: string, grid: { number } },
  atmosphereData: { fogDensity: number }?,
}

export type Report = {
  path: string?,
  masters: { string },
  files: number,
  candidates: number,
  merged: { [string]: number },
  failed: { string },
  activated: boolean?,
}

export type Options = {
  recordTypes: { string }?,
  records: { string }?,
  ignoreRecords: { string }?,
  fileFilters: { [string]: boolean }?,
  objectFilters: { { string | boolean } }?,
  inclusive: boolean?,
  noMasters: boolean?,
  patches: { string }?,
  encoding: (string | number)?,
  fileName: string?,
  outputDir: string?,
  activate: boolean?,
  verbose: boolean?,
  report: Report?,
}

return function(state: { [string]: unknown }?, openmw: Context?)
  local shared: { [string]: unknown } = state or {}
  local options: Options = (shared.tes3merge :: Options?) or {}
  shared.tes3merge = options

  local function set(list: { string }?): Set
    local result: Set = {}
    for _, value in list or {} do
      result[value] = true
    end

    return result
  end

  local DefaultRecordTypes: { string } = {
    'ACTI',
    'ALCH',
    'APPA',
    'ARMO',
    'BODY',
    'BOOK',
    'BSGN',
    'CELL',
    'CLAS',
    'CLOT',
    'CONT',
    'CREA',
    'DOOR',
    'ENCH',
    'GMST',
    'INGR',
    'LEVC',
    'LEVI',
    'LIGH',
    'LOCK',
    'MGEF',
    'MISC',
    'NPC_',
    'PROB',
    'RACE',
    'REPA',
    'SKIL',
    'SNDG',
    'SOUN',
    'SPEL',
    'STAT',
    'WEAP',
  }

  local SummonedCreatures = set {
    'centurion_fire_dead',
    'wraith_sul_senipul',
    'ancestor_ghost_summon',
    'atronach_flame_summon',
    'atronach_frost_summon',
    'atronach_storm_summon',
    'bonelord_summon',
    'bonewalker_summon',
    'bonewalker_greater_summ',
    'centurion_sphere_summon',
    'clannfear_summon',
    'daedroth_summon',
    'dremora_summon',
    'golden saint_summon',
    'hunger_summon',
    'scamp_summon',
    'skeleton_summon',
    'ancestor_ghost_variner',
    'fabricant_summon',
    'bm_bear_black_summon',
    'bm_wolf_grey_summon',
    'bm_wolf_bone_summon',
  }

  -- Cell renames always merge, so cellnames needs nothing of its own.
  local PatchNames: { [string]: { string } } = {
    all = { 'fogbug', 'summons' },
    none = {},
    fogbug = { 'fogbug' },
    summons = { 'summons' },
    cellnames = {},
  }

  local mergeTypes: Set, patches: Set = {}, {}
  local onlyTypes: Set? = if options.records then set(options.records) else nil
  local ignoredTypes = set(options.ignoreRecords)

  for _, tag in options.recordTypes or DefaultRecordTypes do
    if (onlyTypes and not onlyTypes[tag]) or ignoredTypes[tag] then continue end

    mergeTypes[tag] = true
  end

  if not next(mergeTypes) then error 'tes3merge: no record types left to merge' end

  for _, name in options.patches or { 'all' } do
    local enabled = PatchNames[string.lower(name)]
      or error(
        `tes3merge: unknown patch "{name}"; expected fogbug, summons, cellnames, all, or none`
      )

    for _, patchName in enabled do
      patches[patchName] = true
    end
  end

  local fileName: string = options.fileName or 'Merged Objects.esp'

  local function asTable(value: Value?): Table? return if type(value) == 'table' then value else nil end

  local function asString(value: Value?): string?
    return if type(value) == 'string' then value else nil
  end

  -- A decoded struct always carries its fields, so an empty table is an empty list.
  local function isArray(value: Value?): boolean
    return type(value) == 'table' and (next(value) == nil or value[1] ~= nil)
  end

  -- NaN equals NaN, as it does for .NET's float Equals. A field set to false differs from one that's
  -- missing.
  local function equal(left: Value?, right: Value?): boolean
    if left == right then return true end

    if type(left) == 'number' and type(right) == 'number' then
      return left ~= left and right ~= right
    end

    if type(left) ~= 'table' or type(right) ~= 'table' then return false end

    for key, value in left do
      if not equal(value, right[key]) then return false end
    end

    for key in right do
      if left[key] == nil then return false end
    end

    return true
  end

  local function copyTable(value: Table): Table
    local result: Table = {}
    for key, item in value do
      result[key] = if type(item) == 'table' then copyTable(item) else item
    end

    return result
  end

  local function copy(value: Value?): Value?
    return if type(value) == 'table' then copyTable(value) else value
  end

  -- A flag is one of the names `|` and spaces separate, so a text that doesn't hold it anywhere
  -- doesn't hold it as one.
  local function hasFlag(flags: Value?, flag: string): boolean
    if type(flags) ~= 'string' or not string.find(flags, flag, 1, true) then return false end

    for name in string.gmatch(flags, '[^|%s]+') do
      if name == flag then return true end
    end

    return false
  end

  local function contains(list: Table, value: Value): boolean
    return any[for item in list => equal(item, value)]
  end

  -- Takes `later`'s value when `current` still has the first definition's.
  local function mergeBase(current: Table, first: Table, later: Table, key: Key): boolean
    if not equal(current[key], first[key]) or equal(later[key], first[key]) then return false end

    current[key] = copy(later[key]) :: Value
    return true
  end

  local mergeAll: (
    current: Table?,
    first: Table?,
    later: Table?,
    special: { [string]: Merger }?,
    skip: Set?
  ) -> boolean

  local function mergeField(
    current: Table,
    first: Table,
    later: Table,
    key: string,
    special: { [string]: Merger }?
  ): boolean
    local merger = special and special[key]
    if merger then return merger(current, first, later, key) end

    local value, firstValue, laterValue =
      asTable(current[key]), asTable(first[key]), asTable(later[key])
    if not value or not firstValue or not laterValue then
      return mergeBase(current, first, later, key)
    end

    if isArray(value) or isArray(firstValue) or isArray(laterValue) then
      return mergeBase(current, first, later, key)
    end

    -- TES3Merge counts a nested structure as changed whenever it merges one.
    mergeAll(value, firstValue, laterValue)
    return true
  end

  -- One field of `mergeAll`, `empty` being what an absent one holds besides nil.
  local function mergeEntry(
    current: Table,
    base: Table,
    later: Table,
    key: string,
    special: { [string]: Merger }?,
    empty: string?
  ): boolean
    local value, firstValue, laterValue = current[key], base[key], later[key]
    if firstValue == nil and value == nil and laterValue ~= nil then
      current[key] = copy(laterValue) :: Value
      return true
    end

    -- A later plugin clearing a value keeps the latest one.
    if (firstValue ~= nil and firstValue ~= empty) and (laterValue == nil or laterValue == empty) then
      return true
    end

    return mergeField(current, base, later, key, special)
  end

  -- A field set to false is a value, so only a missing field counts as absent, except that a
  -- record's own string fields are empty when it doesn't have their subrecord. TES3Merge sees those
  -- as missing (null) subrecords, so the top level (`skip` is only passed there) treats '' as absent.
  -- Merging a field reads and writes that field alone, and only in `current`: the fields are
  -- taken as `later` and then `first` hold them.
  function mergeAll(
    current: Table?,
    first: Table?,
    later: Table?,
    special: { [string]: Merger }?,
    skip: Set?
  ): boolean
    if not later or not current then return false end

    local empty: string? = if skip then '' else nil
    local base: Table = first or {}
    local modified = false

    for key in later do
      if type(key) ~= 'string' or key == 'type' or (skip and skip[key]) then continue end
      if mergeEntry(current, base, later, key, special, empty) then modified = true end
    end

    for key in base do
      if type(key) ~= 'string' or later[key] ~= nil then continue end
      if key == 'type' or (skip and skip[key]) then continue end
      if mergeEntry(current, base, later, key, special, empty) then modified = true end
    end

    return modified
  end

  local function effectList(current: Table, first: Table, later: Table, key: string): boolean
    local list = asTable(current[key]) or asTable(copy(first[key] or later[key]))
    if not list then return false end

    current[key] = list

    local firstList: Table, laterList: Table = asTable(first[key]) or {}, asTable(later[key]) or {}
    local modified = false

    for index = 1, 8 do
      local value, firstValue, laterValue =
        asTable(list[index]), asTable(firstList[index]), asTable(laterList[index])

      if value and firstValue and laterValue then
        if not equal(laterValue.magicEffect, firstValue.magicEffect) then
          list[index] = copyTable(laterValue)
          modified = true
        elseif mergeAll(value, firstValue, laterValue) then
          modified = true
        end
      elseif not firstValue and laterValue then
        list[#list + 1] = copyTable(laterValue)
        modified = true
      end
    end

    return modified
  end

  local function itemsList(current: Table, first: Table, later: Table, key: string): boolean
    local firstList, laterList, list =
      asTable(first[key]), asTable(later[key]), asTable(current[key])
    if not firstList or not laterList or not list then return false end

    local union: Table = {}
    for _, source in { firstList, list, laterList } do
      for _, item in source do
        if not contains(union, item) then union[#union + 1] = copy(item) :: Value end
      end
    end

    if equal(union, firstList) then return false end

    current[key] = union
    return true
  end

  local function wanderPackage(list: Value?): Table?
    for _, package in asTable(list) or {} do
      local fields = asTable(package)
      if fields and fields.type == 'Wander' then return fields end
    end

    return nil
  end

  local function aiPackages(current: Table, first: Table, later: Table, key: string): boolean
    local value, firstValue, laterValue =
      wanderPackage(current[key]), wanderPackage(first[key]), wanderPackage(later[key])

    -- TES3Merge reports a change here without making one.
    if not firstValue and laterValue then return true end
    if not value or not firstValue or not laterValue then return false end

    return mergeAll(value, firstValue, laterValue)
  end

  local function npcData(current: Table, first: Table, later: Table, key: string): boolean
    local data, firstData, laterData =
      asTable(current[key]), asTable(first[key]), asTable(later[key])
    if not data or not firstData or not laterData then
      return mergeBase(current, first, later, key)
    end

    local modified = false
    for _, field in { 'level', 'disposition', 'reputation', 'rank', 'gold' } do
      if mergeBase(data, firstData, laterData, field) then modified = true end
    end

    local laterStats = asTable(laterData.stats)
    if data.stats == nil and laterStats then
      data.stats = copyTable(laterStats)
      return true
    end

    local stats, firstStats = asTable(data.stats), asTable(firstData.stats) or laterStats
    if not stats or not firstStats or not laterStats then return modified end

    for _, field in { 'health', 'magicka', 'fatigue' } do
      if mergeBase(stats, firstStats, laterStats, field) then modified = true end
    end

    for _, listName in { 'attributes', 'skills' } do
      local values, firstValues, laterValues =
        asTable(stats[listName]), asTable(firstStats[listName]), asTable(laterStats[listName])

      if not values or not firstValues or not laterValues or equal(values, laterValues) then
        continue
      end

      for index = 1, #values do
        if values[index] ~= firstValues[index] or laterValues[index] == firstValues[index] then
          continue
        end

        values[index] = laterValues[index]
        modified = true
      end
    end

    return modified
  end

  local function entryId(entry: Table): string return tostring(entry[1]) end

  local function entryLevel(entry: Table): number
    local level = entry[2]
    return if type(level) == 'number' then level else 0
  end

  -- Each { id, level } entry appears as many times as the list with the most of it has it.
  local function leveledList(current: Table, first: Table, later: Table, key: string): boolean
    local firstList, laterList = asTable(first[key]), asTable(later[key])
    local list = asTable(current[key]) or firstList or laterList
    if not list then return false end

    local counts: { [string]: Tally }, order: { Tally } = {}, {}

    for _, source in { firstList or {}, list, laterList or {} } do
      local seen: { [string]: number } = {}

      for _, item in source do
        local entry = asTable(item)
        if not entry then continue end

        local entryKey = entryId(entry) .. '\0' .. tostring(entry[2])
        seen[entryKey] = (seen[entryKey] or 0) + 1
        if counts[entryKey] then continue end

        local tally: Tally = { entry = entry, count = 0 }
        counts[entryKey] = tally
        table.insert(order, tally)
      end

      for entryKey, count in seen do
        counts[entryKey].count = math.max(counts[entryKey].count, count)
      end
    end

    local union: { Table } =
      [for {entry, count} in order for _ in range(1, count) => copyTable(entry)]

    table.sort(union, function(left: Table, right: Table): boolean
      if entryLevel(left) ~= entryLevel(right) then return entryLevel(left) < entryLevel(right) end

      return entryId(left) < entryId(right)
    end)

    local merged: Table = {}
    for index, entry in union do
      merged[index] = entry
    end

    if equal(merged, firstList) then return false end

    current[key] = merged
    return true
  end

  local function namedFields(fields: { string }): Merger
    return function(current: Table, first: Table, later: Table, key: string): boolean
      local value, firstValue, laterValue =
        asTable(current[key]), asTable(first[key]), asTable(later[key])
      if not value or not firstValue or not laterValue then
        return mergeBase(current, first, later, key)
      end

      local modified = false
      for _, field in fields do
        if mergeBase(value, firstValue, laterValue, field) then modified = true end
      end

      return modified
    end
  end

  local SpecialMergers: { [string]: { [string]: Merger } } = {
    Spell = { effects = effectList },
    Enchanting = { effects = effectList },
    Alchemy = { effects = effectList },
    Npc = { aiPackages = aiPackages, data = npcData },
    Creature = { aiPackages = aiPackages },
    LeveledItem = { items = leveledList },
    LeveledCreature = { creatures = leveledList },
    Class = { data = namedFields { 'specialization', 'flags' } },
    Faction = { data = namedFields { 'flags' } },
  }

  if options.inclusive then
    for _, recordType in { 'Npc', 'Creature', 'Container' } do
      local special = SpecialMergers[recordType] or {}
      special.inventory = itemsList
      SpecialMergers[recordType] = special
    end
  end

  local function mergeFlags(current: Table, first: Table, later: Table): boolean
    if not equal(current.flags, first.flags) or equal(later.flags, first.flags) then
      return false
    end

    current.flags = later.flags
    return true
  end

  -- Only a cell's flags merge, plus an exterior cell's name (the cellnames fix).
  local function mergeCell(current: Table, first: Table, later: Table): boolean
    local modified = mergeFlags(current, first, later)

    local data = asTable(current.data)
    local name, firstName, laterName =
      asString(current.name), asString(first.name), asString(later.name)
    if hasFlag(data and data.flags, 'IS_INTERIOR') or not laterName then return modified end

    if not firstName and not name then
      current.name = laterName
      return true
    end

    if name ~= firstName or laterName == firstName or laterName == '' then return modified end

    current.name = laterName
    return true
  end

  local TopLevelSkip: Set = { flags = true }

  local function mergeRecord(current: Table, first: Table, later: Table): boolean
    if current.type == 'Cell' then return mergeCell(current, first, later) end

    local modified = mergeFlags(current, first, later)
    local recordType = current.type
    local special = if type(recordType) == 'string' then SpecialMergers[recordType] else nil
    if mergeAll(current, first, later, special, TopLevelSkip) then modified = true end

    return modified
  end

  local function patchSummon(record: Table): boolean
    local id = record.id
    if type(id) ~= 'string' or not SummonedCreatures[string.lower(id)] then return false end
    if hasFlag(record.flags, 'PERSISTENT') then return false end

    local flags = record.flags
    record.flags = if type(flags) == 'string' and flags ~= ''
      then flags .. ' | PERSISTENT'
      else 'PERSISTENT'
    return true
  end

  local function patchFog(record: Table): boolean
    local data = asTable(record.data)
    local flags = data and data.flags
    if not hasFlag(flags, 'IS_INTERIOR') or hasFlag(flags, 'BEHAVES_LIKE_EXTERIOR') then
      return false
    end

    local atmosphere = asTable(record.atmosphereData)
    if not atmosphere or atmosphere.fogDensity ~= 0 then return false end

    atmosphere.fogDensity = 0.01
    return true
  end

  local function patch(record: Table): boolean
    if patches.summons and record.type == 'Creature' and patchSummon(record) then return true end
    if patches.fogbug and record.type == 'Cell' and patchFog(record) then return true end

    return false
  end

  assert(openmw, 'tes3merge needs an OpenMW config')
  local context: Context = openmw

  local CodePages: { [number]: string } =
    { [1250] = 'win1250', [1251] = 'win1251', [1252] = 'win1252' }

  local function textEncoding(): string
    local option = options.encoding
    if type(option) ~= 'number' then return option or context.encoding or 'win1252' end

    return CodePages[option]
      or error(`tes3merge: encoding code {option} isn't supported; expected 1250, 1251, or 1252`)
  end

  local encoding = textEncoding()

  local ignoredFiles: Set = { [string.lower(fileName)] = true }
  for name, allow in options.fileFilters or {} do
    if allow == false then ignoredFiles[string.lower(name)] = true end
  end

  local entries: { loadOrder.Content }, mergeTags: { string } = {}, {}

  for _, content in context:content() do
    local name, path = string.lower(content.name), content.path
    if ignoredFiles[name] or not path or string.find(name, '%.omwscripts$') then continue end

    table.insert(entries, content)
  end

  for tag in mergeTypes do
    table.insert(mergeTags, tag)
  end

  -- Plugins come back in order, without the ones that failed.
  local opened = loadOrder.open(context, {
    entries = entries,
    types = mergeTags,
    cell = { references = false },
    encoding = encoding,
  })

  local unreadable: { string } = [for {name, problem} in opened.failures => `{name}: {problem}`]
  local loaded = opened.plugins

  -- Groups go by type, in the order each type first appears, then by id, in the order each id first
  -- appears: TES3Merge's dictionaries iterate in insertion order, and its output follows them.
  local kinds: { [string]: Kind }, kindOrder: { Kind } = {}, {}

  for tag in mergeTypes do
    kinds[tag] = {
      tag = tag,
      ids = intern.new 'ascii-nocase',
      definitions = {},
      needsFog = if tag == 'CELL' then {} else nil,
    }
  end

  -- Whether the fog patch would change an interior: it's on, and the cell has an atmosphere
  -- without fog and doesn't behave like an exterior.
  local function needsFog(cell: Cell): boolean
    local atmosphere = cell.atmosphereData
    if not patches.fogbug or not atmosphere then return false end
    if hasFlag(cell.data.flags, 'BEHAVES_LIKE_EXTERIOR') then return false end

    return atmosphere.fogDensity == 0
  end

  -- What a record is identified by, and whether the fog patch would change it. Skills, magic
  -- effects, and exterior cells are identified by index or grid, not by id; a cell is decoded to
  -- tell which it is, and that reading says what the patch would find.
  local function identity(plugin: tes3.Plugin, index: number, tag: string): (string?, boolean)
    local id = tes3.records.fieldId(plugin, index) or tes3.records.id(plugin, index)
    if tag ~= 'SKIL' and tag ~= 'MGEF' and tag ~= 'CELL' then return id, false end

    local value = plugin:decode(index) :: tes3.Value
    if tag == 'SKIL' then return tostring(value.skillId), false end
    if tag == 'MGEF' then return tostring(value.effectId), false end

    local cell = value :: Cell
    local data = cell.data
    if hasFlag(data.flags, 'IS_INTERIOR') then return id, needsFog(cell) end

    return `#{tostring(data.grid[1])},{tostring(data.grid[2])}`, false
  end

  -- A filter without a pattern matches nothing, so it isn't kept. A pattern is a regex over the
  -- record's id, matched without regard to case, as tes3cmd's selectors read one.
  local filters: { ObjectFilter } = {}
  for _, filter in options.objectFilters or {} do
    local pattern = filter[1]
    if type(pattern) ~= 'string' then continue end

    -- jess.regex.new throws on a pattern that isn't a regex.
    local compiled, regex = pcall(jess.regex.new, pattern, { caseInsensitive = true })
    if not compiled then error(`invalid regex '{pattern}': {regex}`, 0) end

    table.insert(filters, { regex = regex :: Regex, allow = filter[2] ~= false })
  end

  -- The last filter that matches a record decides, so they are asked last to first. A record
  -- without an id matches no filter.
  local function allowed(plugin: tes3.Plugin, index: number): boolean
    if #filters == 0 then return true end

    local id = tes3.records.id(plugin, index)
    if not id then return true end

    for position = #filters, 1, -1 do
      local filter = filters[position]
      if filter.regex:isMatch(id) then return filter.allow end
    end

    return true
  end

  for position, entry in loaded do
    local plugin, origin = entry.plugin, position * Stride

    for index = 0, plugin:count() - 1 do
      local tag = plugin:tag(index)
      local kind = kinds[tag]
      if not kind or not allowed(plugin, index) then continue end

      local id, foggy = identity(plugin, index, tag)
      if not id or id == '' then continue end

      local ids: dream_intern_Pool = kind.ids
      local token = ids:intern(id)
      local definitions, fog = kind.definitions, kind.needsFog
      local held = definitions[token]
      if not held then
        if token == 1 then table.insert(kindOrder, kind) end

        definitions[token] = origin + index
      elseif type(held) == 'number' then
        definitions[token] = { held, origin + index }
      else
        table.insert(held, origin + index)
      end

      if fog then fog[token] = foggy end
    end
  end

  -- A group as a message names it: its id, lowered.
  local function lowered(kind: Kind, token: number): string
    return string.lower(kind.ids:resolve(token))
  end

  -- The name of the file a record is in.
  local function definedIn(definition: number): string
    return loaded[definition // Stride].name
  end

  local function decode(definition: number): (Table?, string?)
    local plugin = loaded[definition // Stride].plugin

    -- `plugin:decode` throws when a record's bytes don't parse as its type. TES3Merge reports that
    -- group as failed and merges the rest, so this is the one place a decoding error is caught.
    local decoded, value = pcall(plugin.decode, plugin, definition % Stride)
    if not decoded then return nil, tostring(value) end

    return if value then value :: Table else nil, nil
  end

  -- Whether `patch` would change the record a group ends with: a creature read from the plugin
  -- that has it, a cell by what was read of it for its identity.
  local function wouldPatch(kind: Kind, token: number, last: number): boolean
    if patches.summons and kind.tag == 'CREA' then
      local creature = loaded[last // Stride].plugin:decode(last % Stride) :: Creature
      if not SummonedCreatures[string.lower(creature.id)] then return false end

      return not hasFlag(creature.flags, 'PERSISTENT')
    end

    local fog = kind.needsFog
    return if fog then fog[token] else false
  end

  local report: Report = {
    path = nil,
    masters = {},
    files = #loaded,
    candidates = 0,
    merged = {},
    failed = unreadable,
  }

  options.report = report

  local merged: { Table }, usedMasters: Set = {}, {}

  local function mergeGroup(kind: Kind, token: number, definitions: { number }): string?
    local count, tag = #definitions, kind.tag

    local last, lastFailure = decode(definitions[count])
    if lastFailure then return lastFailure end
    if not last then return nil end

    local current = copyTable(last)
    local used: Set =
      { [definedIn(definitions[1])] = true, [definedIn(definitions[count])] = true }
    local changed = false

    -- TES3Merge's merge reports a change for every record three or more plugins define, cells aside.
    local merging = count >= 3 and tag ~= 'CELL'

    if count >= 3 then
      local first, firstFailure = decode(definitions[1])
      if firstFailure then return firstFailure end

      for index = count - 1, 2, -1 do
        local later, laterFailure = decode(definitions[index])
        if laterFailure then return laterFailure end
        if first and later and mergeRecord(current, first, later) then changed = true end

        -- TES3Merge uses a plugin as a master once its merge has reported a change, its own or a
        -- later plugin's.
        if changed or merging then used[definedIn(definitions[index])] = true end
      end
    end

    -- TES3Merge only patches what its merge left alone (`isAnythingChanged || Patch(...)`).
    if not changed and not merging and patch(current) then changed = true end

    if current.type == 'Cell' then current.references = {} end
    if not changed or equal(current, last) then return nil end

    table.insert(merged, current)
    report.merged[tag] = (report.merged[tag] or 0) + 1

    for file in used do
      usedMasters[file] = true
    end

    if options.verbose then print(`Merged {tag} record: {lowered(kind, token)}`) end

    return nil
  end

  for _, kind in kindOrder do
    for token, held in kind.definitions do
      if type(held) == 'number' then
        if not wouldPatch(kind, token, held) then continue end
      elseif #held >= 3 then
        report.candidates += 1
      elseif not wouldPatch(kind, token, held[#held]) then
        continue
      end

      local failure = mergeGroup(kind, token, if type(held) == 'number' then { held } else held)
      if not failure then continue end

      table.insert(report.failed, `{kind.tag}:{lowered(kind, token)}: {failure}`)
    end
  end

  if #merged == 0 then
    print 'tes3merge: no merges were deemed necessary'
    return
  end

  local output = tes3.new('plugin', { encoding = encoding })
  output:setAuthor 'TES3Merge'
  output:setDescription(`Automatic merge generated at {os.date '!%Y-%m-%dT%H:%M:%SZ'}.`)

  if not options.noMasters then
    local masters: { { name: string, size: number } } =
      [for {name, size} in loaded if usedMasters[name] => { name = name, size = size }]

    into(report.masters)[for master in masters => master.name]
    output:setMasters(masters)
  end

  for _, record in merged do
    output:insertValue(output:count(), record :: tes3.Value)
  end

  local outputDir = options.outputDir or loadOrder.outputDirectory(context)
  assert(
    outputDir,
    'tes3merge: openmw.cfg has no data-local= or data= folder to write to; add one or set outputDir'
  )
  if not jess.fs.isDir(outputDir) then jess.fs.createDir(outputDir) end

  local path = `{outputDir}/{fileName}`
  output:updateRecordCount()
  jess.fs.write(path, output:save())
  report.path = path

  -- OpenMW only loads content files from its data folders, and `activate` refuses one anywhere
  -- else. A merge written outside them is left inactive rather than failing the run.
  if options.activate then
    local added, problem = loadOrder.activate(context, fileName)

    if added ~= nil then
      context:save()
    else
      print(
        `tes3merge: wrote {path} but didn't activate it, as OpenMW can't load it from there: {problem}`
      )
    end

    report.activated = added ~= nil
  end

  print(`tes3merge: wrote {#merged} merged records to {path}`)
end
