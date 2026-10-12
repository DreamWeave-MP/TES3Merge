--!strict
--!native
--[[
tes3merge, timed through its public modules: whole merges over load orders built here with
`@tes3`, each `@tes3merge` called with an `@openmw` Context the way its command line calls it;
the command line's argument lists read; and the command line itself, warm and run once.

  jess run --capability filesystem.read --capability filesystem.write \
    --capability process.spawn --package . --package-path .. \
    bench/bench.luau <scratch> [filter] [jess binary] [package path]

The load order is a master of 6,200 records of the types the tool merges (items, spells with
their effects, NPCs and creatures with their packages and inventories, leveled lists, interior
and exterior cells with their references, settings) and four plugins that each define every
fourth, sixth, tenth, and fifteenth of them again, changed, plus records of their own: 823 of
the master's records are defined by three files or more. A second order is the master and one
plugin, where nothing has three definitions; a third is a master of 248 records and two plugins.
They are written to a folder under `<scratch>`, which is removed afterwards.

One line per workload, `name<TAB>seconds per call`: the median of seven batches of about a tenth
of a second each, with a full collection between batches. The tool reports through `print`, so
each merge also prints its own line (`tes3merge: wrote ...`) between those: the lines of the
bench are the ones holding a tab. Every merge's report and the records it wrote are weighed
before the first batch and after the last, outside the time, and compared with what is pinned
here, so a path that stops doing its work fails instead of posting a time.

Given the jess binary to start (and `process.spawn`), the cold workloads too: what one process
pays for one command from its first `require` on. Each is the median of seven processes running
`cold.luau`, which find the packages this one depends on in the package path, the folder above
this package without one.
]]

local bytes = require '@dream/bytes'
local cli = require '@tes3merge/cli'
local fs = require '@dream/fs'
local openmw = require '@openmw'
local process = require '@dream/process'
local tes3 = require '@tes3'
local tes3merge = require '@tes3merge'

-- A build without the verified toolchain runs Luau slower than a release does, so a number from
-- one says nothing about what ships.
if not jess.bench.verified then
  error(
    'tes3merge bench: this jess was built without the verified toolchain: measure on a release',
    0
  )
end

local scratch: string?, filter: string?, binary: string?, packages: string? = ...
if not scratch then error('tes3merge bench: a scratch folder is required', 0) end

local Wanted = if filter and filter ~= '' then string.split(filter, '|') else nil

--- Whether the workload called `name` runs: every one without a filter, else those whose name
--- holds one of the filter's parts, which `|` separates.
local function runs(name: string): boolean
  if not Wanted then return true end

  for _, part in Wanted do
    if string.find(name, part, 1, true) then return true end
  end

  return false
end

--- Where this file is, from its chunk name: `cold.luau` is beside it.
local function here(): string
  local source = debug.info(1, 's')
  local first = string.sub(source, 1, 1)
  local path = if first == '@' or first == '=' then string.sub(source, 2) else source

  return string.match(path, '^(.*)/[^/]*$') or '.'
end

local Here = here()
local PackagePath = packages or `{Here}/../..`
local Root = `{scratch}/tes3merge-bench`
local Data = `{Root}/data`
local Merged = 'Merged Objects.esp'

local function io<Value>(value: Value?, message: string?, kind: dream_fs_ErrorKind?): Value
  if not value then error(message or tostring(kind), 0) end

  return value
end

type Fields = { [string]: unknown }

--- A record of one kind: the master's `index`th at revision 0, and the same record as the
--- plugin of revision 1 to 4 changes it.
type Maker = (index: number, revision: number) -> Fields

local Services = 'BARTERS_WEAPONS | BARTERS_ARMOR | OFFERS_TRAINING | OFFERS_REPAIRS'

local Summons = {
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

local Effects = { 'Shield', 'FireDamage', 'Blind', 'Recall', 'WaterWalking', 'Levitate', 'Burden' }

local function miscItem(index: number, revision: number): Fields
  return {
    type = 'MiscItem',
    id = `bench_misc_{index}`,
    name = if revision == 1 then `Polished Trinket {index}` else `Trinket {index}`,
    mesh = 'm\\misc_trinket_01.nif',
    icon = 'm\\tx_trinket_01.tga',
    script = if revision == 3 then 'bench_script' else '',
    data = {
      weight = 1 + index % 7,
      value = if revision == 2 then 500 else 10 + index % 90,
      flags = '',
    },
  }
end

local function weapon(index: number, revision: number): Fields
  return {
    type = 'Weapon',
    id = `bench_weapon_{index}`,
    name = if revision == 1 then `Honed Blade {index}` else `Blade {index}`,
    mesh = 'w\\w_blade_01.nif',
    icon = 'w\\tx_blade_01.tga',
    script = '',
    enchanting = if revision == 3 then 'bench_enchanting_6' else '',
    data = {
      weight = 8 + index % 20,
      value = 40 + index % 400,
      weaponType = 'AxeOneHand',
      health = 300 + index % 900,
      speed = if revision == 4 then 1.25 else 1,
      reach = 1,
      enchantment = 5 + index % 60,
      chopMin = 1 + index % 5,
      chopMax = if revision == 2 then 60 else 10 + index % 30,
      slashMin = 1,
      slashMax = 12 + index % 20,
      thrustMin = 1,
      thrustMax = if revision == 2 then 40 else 8,
      flags = '',
    },
  }
end

local function armor(index: number, revision: number): Fields
  return {
    type = 'Armor',
    id = `bench_armor_{index}`,
    name = `Cuirass {index}`,
    mesh = 'a\\a_cuirass_gnd.nif',
    icon = 'a\\tx_cuirass.tga',
    script = '',
    enchanting = '',
    bipedObjects = {
      {
        bipedObjectType = 'Chest',
        maleBodypart = if revision == 3 then 'a_cuirass_heavy' else 'a_cuirass',
        femaleBodypart = 'a_cuirass_f',
      },
    },
    data = {
      armorType = 'Cuirass',
      weight = 20 + index % 30,
      value = if revision == 1 then 900 else 100 + index % 300,
      health = 400 + index % 800,
      enchantment = 30,
      armorRating = if revision == 2 then 80 else 10 + index % 50,
    },
  }
end

local function clothing(index: number, revision: number): Fields
  return {
    type = 'Clothing',
    id = `bench_clothing_{index}`,
    name = if revision == 2 then `Fine Amulet {index}` else `Amulet {index}`,
    mesh = 'c\\amulet_gnd.nif',
    icon = 'c\\tx_amulet.tga',
    script = '',
    enchanting = if revision == 1 then 'bench_enchanting_12' else '',
    bipedObjects = {},
    data = {
      clothingType = 'Amulet',
      weight = 1,
      value = 20 + index % 200,
      enchantment = if revision == 4 then 120 else 60,
    },
  }
end

local Page = string.rep('The page goes on, as pages in these books do, for a while longer. ', 9)

local function book(index: number, revision: number): Fields
  return {
    type = 'Book',
    id = `bench_book_{index}`,
    name = `Volume {index}`,
    mesh = 'm\\text_octavo_01.nif',
    icon = 'm\\tx_octavo_01.tga',
    script = '',
    enchanting = '',
    text = if revision == 1 then `<DIV ALIGN="LEFT">Errata.<BR>{Page}` else `<DIV>{Page}`,
    data = {
      weight = 3,
      value = if revision == 2 then 250 else 25 + index % 50,
      bookType = 'Book',
      skill = 'None',
      enchantment = 0,
    },
  }
end

local function light(index: number, revision: number): Fields
  return {
    type = 'Light',
    id = `bench_light_{index}`,
    name = `Lantern {index}`,
    mesh = 'l\\light_lantern.nif',
    icon = 'l\\tx_lantern.tga',
    script = '',
    sound = if revision == 3 then 'Fire' else '',
    data = {
      weight = 2,
      value = 10 + index % 30,
      time = if revision == 1 then 1200 else 600,
      radius = if revision == 2 then 512 else 128 + index % 128,
      color = { 240, 200 - index % 60, 120, 0 },
      flags = 'DYNAMIC | CAN_CARRY | FIRE',
    },
  }
end

--- The effects of a spell, a potion, or an enchantment: a plugin strengthens one, adds one, or
--- puts another in the first one's place.
local function effects(index: number, revision: number): { Fields }
  local list: { Fields } = {}

  for slot = 1, 2 + index % 3 do
    local first = slot == 1

    list[slot] = {
      magicEffect = if first and revision == 3
        then 'Paralyze'
        else Effects[(index + slot) % #Effects + 1],
      skill = 'None',
      attribute = 'None',
      range = if first then 'OnTouch' else 'OnSelf',
      area = 0,
      duration = 5 * slot,
      minMagnitude = 1 + index % 10,
      maxMagnitude = if first and revision == 1 then 90 else 10 + index % 20,
    }
  end

  if revision == 2 then
    table.insert(list, {
      magicEffect = 'Sanctuary',
      skill = 'None',
      attribute = 'None',
      range = 'OnSelf',
      area = 0,
      duration = 30,
      minMagnitude = 5,
      maxMagnitude = 15,
    })
  end

  return list
end

local function spell(index: number, revision: number): Fields
  return {
    type = 'Spell',
    id = `bench_spell_{index}`,
    name = if revision == 4 then `Greater Spell {index}` else `Spell {index}`,
    data = { spellType = 'Spell', cost = 5 + index % 80, flags = '' },
    effects = effects(index, revision),
  }
end

local function enchanting(index: number, revision: number): Fields
  return {
    type = 'Enchanting',
    id = `bench_enchanting_{index}`,
    data = {
      enchantType = 'CastOnce',
      cost = if revision == 4 then 99 else 10 + index % 40,
      maxCharge = 100 + index % 300,
      flags = '',
    },
    effects = effects(index, revision),
  }
end

local function alchemy(index: number, revision: number): Fields
  return {
    type = 'Alchemy',
    id = `bench_potion_{index}`,
    name = `Potion {index}`,
    mesh = 'm\\misc_potion_01.nif',
    icon = 'm\\tx_potion_01.tga',
    script = '',
    data = { weight = 1, value = if revision == 4 then 300 else 15 + index % 100, flags = '' },
    effects = effects(index, revision),
  }
end

local function aiData(index: number, revision: number): Fields
  return {
    hello = 30,
    fight = if revision == 3 then 90 else 30 + index % 40,
    flee = 20,
    alarm = 0,
    services = if index % 5 == 0 then Services else '',
  }
end

local function aiPackages(index: number, revision: number): { Fields }
  return {
    {
      type = 'Wander',
      distance = if revision == 4 then 2048 else 128 * (1 + index % 4),
      duration = 5,
      gameHour = 0,
      idle2 = 60,
      idle3 = 20,
      idle4 = 10,
      idle5 = 0,
      idle6 = 0,
      idle7 = 0,
      idle8 = 0,
      idle9 = 0,
      reset = 1,
    },
  }
end

--- What an NPC, a creature, or a container holds: a plugin adds one thing or another.
local function inventory(index: number, revision: number): { { unknown } }
  local list: { { unknown } } = {}

  for slot = 1, 3 + index % 4 do
    list[slot] = { slot, `bench_misc_{index + slot}` }
  end

  if revision == 1 then table.insert(list, { 1, 'bench_weapon_4' }) end
  if revision == 3 then table.insert(list, { 25, 'gold_001' }) end

  return list
end

local function npc(index: number, revision: number): Fields
  local autoCalculated = index % 2 == 0
  local skills: { number } = {}

  for skill = 1, 27 do
    skills[skill] = if revision == 2 and skill % 9 == 0 then 75 else 5 + (index + skill) % 40
  end

  return {
    type = 'Npc',
    id = `bench_npc_{index}`,
    name = if revision == 1 then `Citizen {index} the Elder` else `Citizen {index}`,
    mesh = '',
    script = if revision == 3 then 'bench_script' else '',
    race = 'Dark Elf',
    class = 'Commoner',
    faction = if index % 4 == 0 then 'Hlaalu' else '',
    head = 'b_n_dark elf_m_head_01',
    hair = 'b_n_dark elf_m_hair_01',
    npcFlags = if autoCalculated then 'AUTO_CALCULATE' else '',
    bloodType = 0,
    data = {
      level = if revision == 1 then 30 else 1 + index % 20,
      disposition = 50,
      reputation = if revision == 4 then 10 else 0,
      rank = 0,
      gold = if revision == 2 then 5000 else index % 300,
      stats = if autoCalculated
        then nil
        else {
          attributes = { 40, 40, 40, 40, 40, 40, 40, if revision == 2 then 70 else 40 },
          skills = skills,
          health = if revision == 4 then 400 else 50 + index % 100,
          magicka = 80,
          fatigue = 200,
        },
    },
    spells = { 'bench_spell_4', `bench_spell_{index % 300 + 1}` },
    inventory = inventory(index, revision),
    aiData = aiData(index, revision),
    aiPackages = aiPackages(index, revision),
    travelDestinations = {},
  }
end

local function creature(index: number, revision: number): Fields
  return {
    type = 'Creature',
    id = Summons[index] or `bench_creature_{index}`,
    name = if revision == 1 then `Dire Beast {index}` else `Beast {index}`,
    mesh = 'r\\beast.nif',
    script = if revision == 2 then 'bench_script' else '',
    sound = '',
    scale = 1,
    creatureFlags = 'WALKS',
    bloodType = 0,
    data = {
      creatureType = 'Normal',
      level = if revision == 3 then 25 else 1 + index % 15,
      strength = 50,
      intelligence = 20,
      willpower = 30,
      agility = 40,
      speed = 12,
      endurance = 50,
      personality = 10,
      luck = 50,
      health = if revision == 4 then 900 else 40 + index % 200,
      magicka = 0,
      fatigue = 400,
      soul = 20 + index % 200,
      combat = 50,
      magic = 20,
      stealth = 10,
      attack1 = { 5, 15 },
      attack2 = { 5, 15 },
      attack3 = { 5, if revision == 3 then 45 else 15 },
      gold = 0,
    },
    spells = {},
    inventory = inventory(index, revision),
    aiData = aiData(index, revision),
    aiPackages = aiPackages(index, revision),
    travelDestinations = {},
  }
end

local function container(index: number, revision: number): Fields
  return {
    type = 'Container',
    id = `bench_container_{index}`,
    name = if revision == 2 then `Locked Chest {index}` else `Chest {index}`,
    mesh = 'o\\contain_chest.nif',
    script = '',
    encumbrance = if revision == 4 then 400 else 100,
    containerFlags = 'IS_BASE',
    inventory = inventory(index, revision),
  }
end

--- A leveled list's entries, each an id and a level: a plugin adds some, drops one, or repeats
--- one the list already has.
local function leveled(prefix: string, index: number, revision: number): { { unknown } }
  local list: { { unknown } } = {}

  for slot = 1, 8 + index % 9 do
    if revision == 2 and slot == 3 then continue end

    table.insert(list, { `{prefix}{(index * 7 + slot * 13) % 300 + 1}`, 1 + slot % 12 })
  end

  if revision == 1 then
    table.insert(list, { `{prefix}301`, 20 })
    table.insert(list, { `{prefix}302`, 1 })
  end

  if revision == 3 then
    table.insert(list, { `{prefix}{(index * 7 + 13) % 300 + 1}`, 2 })
    table.insert(list, { `{prefix}303`, 9 })
  end

  return list
end

local function leveledItem(index: number, revision: number): Fields
  return {
    type = 'LeveledItem',
    id = `bench_items_{index}`,
    leveledItemFlags = 'CALCULATE_FOR_EACH_ITEM',
    chanceNone = if revision == 4 then 75 else 10,
    items = leveled('bench_misc_', index, revision),
  }
end

local function leveledCreature(index: number, revision: number): Fields
  return {
    type = 'LeveledCreature',
    id = `bench_creatures_{index}`,
    leveledCreatureFlags = 'CALCULATE_FROM_ALL_LEVELS',
    chanceNone = if revision == 4 then 50 else 0,
    creatures = leveled('bench_creature_', 30 + index, revision),
  }
end

local function references(index: number): { Fields }
  local list: { Fields } = {}

  for slot = 1, 6 do
    list[slot] = {
      id = `bench_misc_{(index + slot) % 700 + 1}`,
      mastIndex = 0,
      refrIndex = index * 8 + slot,
      temporary = true,
      translation = { 64 * slot, 32 * (index % 20), 0 },
      rotation = { 0, 0, 0 },
    }
  end

  return list
end

--- An interior, a third of them with the fog a later plugin's density of 0 hides.
local function interior(index: number, revision: number): Fields
  return {
    type = 'Cell',
    name = `Bench Hall {index}`,
    data = {
      flags = if revision == 1 then 'IS_INTERIOR | HAS_WATER' else 'IS_INTERIOR',
      grid = { 0, 0 },
    },
    waterHeight = 0,
    atmosphereData = {
      ambientColor = { 70, 70, 70, 0 },
      sunlightColor = { 240, 220, 220, 0 },
      fogColor = { 10, if revision == 2 then 90 else 10, 10, 0 },
      fogDensity = if index % 3 == 0 then 0 else 1,
    },
    references = references(index),
  }
end

--- An exterior, which the first plugin names and the third puts in another region.
local function exterior(index: number, revision: number): Fields
  return {
    type = 'Cell',
    name = if revision == 1 then `Bench Coast {index}` else '',
    data = { flags = 'HAS_WATER', grid = { index % 40 - 20, index // 40 - 3 } },
    region = if revision == 3 then 'Ascadian Isles Region' else 'Bitter Coast Region',
    references = references(index),
  }
end

local function static(index: number, revision: number): Fields
  return {
    type = 'Static',
    id = `bench_static_{index}`,
    mesh = if revision == 0 then 'x\\ex_rock_01.nif' else `x\\ex_rock_0{revision + 1}.nif`,
  }
end

local function activator(index: number, revision: number): Fields
  return {
    type = 'Activator',
    id = `bench_activator_{index}`,
    name = if revision == 2 then `Old Lever {index}` else `Lever {index}`,
    mesh = if revision == 4 then 'x\\lever_02.nif' else 'x\\lever_01.nif',
    script = '',
  }
end

local function door(index: number, revision: number): Fields
  return {
    type = 'Door',
    id = `bench_door_{index}`,
    name = `Door {index}`,
    mesh = 'd\\door_01.nif',
    script = if revision == 1 then 'bench_script' else '',
    openSound = 'Door Stone Open',
    closeSound = if revision == 3 then 'Door Heavy Close' else 'Door Stone Close',
  }
end

local function setting(index: number, revision: number): Fields
  return {
    type = 'GameSetting',
    id = `fBenchSetting{index}`,
    value = { type = 'Float', data = if revision == 0 then index / 8 else index / 8 + revision },
  }
end

--- Each kind the master has, and how many of it: 6,200 records in all.
local Kinds: { { make: Maker, count: number } } = {
  { make = setting, count = 300 },
  { make = static, count = 500 },
  { make = activator, count = 150 },
  { make = door, count = 150 },
  { make = miscItem, count = 700 },
  { make = weapon, count = 400 },
  { make = armor, count = 300 },
  { make = clothing, count = 200 },
  { make = book, count = 200 },
  { make = light, count = 200 },
  { make = alchemy, count = 200 },
  { make = spell, count = 300 },
  { make = enchanting, count = 200 },
  { make = container, count = 300 },
  { make = creature, count = 300 },
  { make = npc, count = 500 },
  { make = leveledItem, count = 350 },
  { make = leveledCreature, count = 150 },
  { make = interior, count = 300 },
  { make = exterior, count = 500 },
}

--- Each plugin after the master: which of the master's records it defines again, and how far
--- past the master's its own records are numbered.
local Plugins: { { name: string, every: number, own: number } } = {
  { name = 'Rebalance.esp', every = 4, own = 10000 },
  { name = 'Overhaul.esp', every = 6, own = 20000 },
  { name = 'Tweaks.esp', every = 10, own = 30000 },
  { name = 'Patch.esp', every = 15, own = 40000 },
}

local function write(name: string, records: { Fields })
  local built = tes3.new(if string.find(name, '%.esm$') then 'master' else 'plugin')

  for _, record in records do
    built:insertValue(built:count(), record :: tes3.Value)
  end

  built:updateRecordCount()
  io(fs.writeFile(`{Data}/{name}`, built:save()))
end

--- Writes the master and its plugins, each kind cut to one part in `divisor`, under names that
--- start with `prefix`. Gives their names in load order.
local function order(prefix: string, divisor: number): { string }
  local names = { `{prefix}Bench.esm` }
  local master: { Fields } = {}

  for _, kind in Kinds do
    for index = 1, kind.count // divisor do
      table.insert(master, kind.make(index, 0))
    end
  end

  write(names[1], master)

  for revision, plugin in Plugins do
    local records: { Fields } = {}

    for _, kind in Kinds do
      local count = kind.count // divisor

      for index = plugin.every, count, plugin.every do
        table.insert(records, kind.make(index, revision))
      end

      -- A tenth as many of its own, which no other file defines.
      for index = 1, count // 10 do
        table.insert(records, kind.make(plugin.own + index, 0))
      end
    end

    table.insert(names, `{prefix}{plugin.name}`)
    write(names[revision + 1], records)
  end

  return names
end

--- A configuration folder under the root, its openmw.cfg naming `content` in the data folder,
--- and a folder beside it to write the merge into.
type Order = { config: string, out: string }

local function configuration(name: string, content: { string }): Order
  local folder = `{Root}/{name}`
  local built: Order = { config = `{folder}/openmw.cfg`, out = `{folder}/out` }
  io(fs.mkdir(built.out, { recursive = true }))

  local lines = { `data="{Data}"\n` }
  for _, file in content do
    table.insert(lines, `content={file}\n`)
  end

  io(fs.writeFile(built.config, table.concat(lines)))
  return built
end

--- How many records the merged plugin at `path` holds, and a digest of them: its header aside,
--- which holds the time of the run.
local function records(path: string): string
  local written = io(fs.readFile(path))
  local merged = tes3.open(written)
  local _, start = merged:span(1)
  local digest = bytes.sha256(bytes.slice(written, start, buffer.len(written) - start))

  return `{merged:count() - 1} records {digest}`
end

--- What a merge did, as one line: its report's counts, and the records it wrote.
local function weigh(options: tes3merge.Options): string
  local report = assert(options.report, 'the merge left no report')
  local tags: { string } = {}

  for tag, count in report.merged do
    table.insert(tags, `{tag}={count}`)
  end

  table.sort(tags)

  local summary =
    `{report.files} files, {report.candidates} candidates, {#report.masters} masters, {#report.failed} failed, {table.concat(tags, ' ')}`
  local path = report.path
  return if path then `{summary}, {records(path)}` else `{summary}, nothing written`
end

local function median(samples: { number }): number
  table.sort(samples)
  return samples[(#samples + 1) // 2]
end

--- Seconds per call of `body`: warmed up, then the median of seven batches of a size that takes
--- about a tenth of a second. `verify` is given the result of the first call and of one more
--- after the last batch, outside the time.
local function measure<Result>(body: () -> Result, verify: (result: Result) -> ()): number
  jess.bench.collect()
  verify(body())

  local start = os.clock()
  body()

  local once = math.max(os.clock() - start, 1e-7)
  local iterations = math.max(1, math.floor(0.1 / once))
  local samples: { number } = {}

  for batch = 1, 7 do
    jess.bench.collect()
    start = os.clock()

    for _ = 1, iterations do
      body()
    end

    samples[batch] = (os.clock() - start) / iterations
  end

  verify(body())
  return median(samples)
end

--- Times `body`, whose every call must weigh `expected`.
local function workload<Result>(
  name: string,
  expected: string,
  body: () -> Result,
  weight: (result: Result) -> string
)
  if not runs(name) then return end

  local function verify(result: Result)
    local actual = weight(result)
    if actual ~= expected then error(`{name}: did "{actual}", not "{expected}"`, 0) end
  end

  print(`{name}\t{string.format('%.9f', measure(body, verify))}`)
end

--- Times a merge of `built` under the options `make` gives, which are made anew for each call:
--- the tool leaves its report in them.
local function merge(
  name: string,
  expected: string,
  built: Order,
  make: (out: string) -> tes3merge.Options
)
  workload(name, expected, function(): tes3merge.Options
    local options = make(built.out)
    tes3merge({ tes3merge = options }, openmw.new(built.config))
    return options
  end, weigh)
end

if fs.exists(Root) then io(fs.remove(Root, { recursive = true })) end

io(fs.mkdir(Data, { recursive = true }))

local Five = configuration('five', order('', 1))
local Two = configuration('two', { 'Bench.esm', 'Rebalance.esp' })
local Small = configuration('small', order('Small', 25)[1:3])

merge(
  'merge five plugins, every type',
  '5 files, 823 candidates, 5 masters, 0 failed, ACTI=5 ALCH=26 ARMO=40 BOOK=26 CELL=198 CLOT=26 CONT=30 CREA=60 DOOR=20 ENCH=26 LEVC=20 LEVI=47 LIGH=26 MISC=94 NPC_=66 SPEL=40 WEAP=54, 804 records b407f6140b12dad108de99a89fac500bf7edfa57b9579bf45eb1a1abb22ff7dc',
  Five,
  function(out: string): tes3merge.Options return { outputDir = out } end
)

merge(
  'merge five plugins, inventories as a union',
  '5 files, 146 candidates, 5 masters, 0 failed, CONT=40 CREA=60 NPC_=66, 166 records fc60f077477466aac72c713a1727aaf20e596590919c8eec7da8aa6c469fcec8',
  Five,
  function(out: string): tes3merge.Options
    return { outputDir = out, inclusive = true, records = { 'NPC_', 'CREA', 'CONT' } }
  end
)

merge(
  'merge five plugins, leveled lists',
  '5 files, 67 candidates, 5 masters, 0 failed, LEVC=20 LEVI=47, 67 records 893c2b82187321a084aae0dd52c78f144bef1ff4cdb9b29c5811c846049239df',
  Five,
  function(out: string): tes3merge.Options
    return { outputDir = out, records = { 'LEVI', 'LEVC' } }
  end
)

merge(
  'merge five plugins, spells, enchantments, and potions',
  '5 files, 92 candidates, 5 masters, 0 failed, ALCH=26 ENCH=26 SPEL=40, 92 records 987562a2a8135f2c815c838696c5deb4b396b989c83338b795f0fc40254a6e51',
  Five,
  function(out: string): tes3merge.Options
    return { outputDir = out, records = { 'SPEL', 'ENCH', 'ALCH' } }
  end
)

merge(
  'merge five plugins, items',
  '5 files, 266 candidates, 5 masters, 0 failed, ARMO=40 BOOK=26 CLOT=26 LIGH=26 MISC=94 WEAP=54, 266 records 2075ab138ccd496f11a2b91c84d64dbb52f82f50388711143fd46c78830830fa',
  Five,
  function(out: string): tes3merge.Options
    return { outputDir = out, records = { 'MISC', 'WEAP', 'ARMO', 'CLOT', 'BOOK', 'LIGH' } }
  end
)

merge(
  'merge five plugins, cells',
  '5 files, 106 candidates, 5 masters, 0 failed, CELL=198, 198 records 5207fa3aa2adda6728ae0db86b9826c3393b3f67ca3ac2678ce73566550e354d',
  Five,
  function(out: string): tes3merge.Options return { outputDir = out, records = { 'CELL' } } end
)

merge(
  'merge five plugins, three object filters',
  '5 files, 452 candidates, 5 masters, 0 failed, ACTI=5 ALCH=13 ARMO=20 BOOK=13 CELL=198 CLOT=13 CONT=10 CREA=41 DOOR=10 ENCH=13 LEVC=10 LEVI=23 LIGH=13 MISC=47 SPEL=20 WEAP=27, 476 records f649ae0566152ed2b4f78925c4378fe92aa44567f426aed500c954a389a50706',
  Five,
  function(out: string): tes3merge.Options
    return {
      outputDir = out,
      objectFilters = { { '^bench_', false }, { '_[0-9]*0$', true }, { '^bench_npc_', false } },
    }
  end
)

merge(
  'merge five plugins, no patches, no masters',
  '5 files, 823 candidates, 0 masters, 0 failed, ACTI=5 ALCH=26 ARMO=40 BOOK=26 CELL=58 CLOT=26 CONT=30 CREA=40 DOOR=20 ENCH=26 LEVC=20 LEVI=47 LIGH=26 MISC=94 NPC_=66 SPEL=40 WEAP=54, 644 records 36bc8f339531b3734a8dd89d7914540f7883db46f0936630dff7e305135efdef',
  Five,
  function(out: string): tes3merge.Options
    return { outputDir = out, patches = { 'none' }, noMasters = true }
  end
)

merge(
  'two plugins, nothing to merge',
  '2 files, 0 candidates, 0 masters, 0 failed, , nothing written',
  Two,
  function(out: string): tes3merge.Options return { outputDir = out, patches = { 'none' } } end
)

merge(
  'two plugins, the patches alone',
  '2 files, 0 candidates, 2 masters, 0 failed, CELL=110 CREA=22, 132 records 803929fbb43279da3a1a12ede4d7b9d0f13c99ce2ae51784686747c3626bcb40',
  Two,
  function(out: string): tes3merge.Options return { outputDir = out } end
)

merge(
  'merge three small plugins',
  '3 files, 13 candidates, 3 masters, 0 failed, ARMO=1 CELL=6 CONT=1 CREA=12 LEVI=1 MISC=2 NPC_=1 SPEL=1 WEAP=1, 26 records 42e692207cec88fcb7df3825c13c37fcbf39243a7a6d925cf9ef1ac5099aee28',
  Small,
  function(out: string): tes3merge.Options return { outputDir = out } end
)

--- Argument lists the command line takes, in every spelling it reads.
local ArgumentLists: { { string } } = {
  { '--config', Five.config, '--output-dir', Five.out },
  { '-r', 'NPC_', 'LEVI', 'LEVC', '--ir', 'STAT', '-i', '--no-masters' },
  { '--records=NPC_', 'CREA', '--patches:none', '--verbose' },
  { '-p', '--file-filter=Rebalance.esp=false', '--object-filter', '^bench_=true' },
  { '--record-types', 'MISC', 'WEAP', 'ARMO', 'CLOT', '--encoding', '1251', '--activate' },
  { '--file-name', 'Merged.esp', '--object-filter=^ttm_=false', '-p', 'fogbug', 'summons' },
  { '--help' },
  { '--version' },
}

workload('parse 8 argument lists', '6 merges, 13 lists, 3 filters', function(): string
  local merges, lists, filters = 0, 0, 0

  for _, argv in ArgumentLists do
    local command = assert(cli.parse(argv))
    local options = command.options
    if not options then continue end

    merges += 1
    lists += #(options.records or {}) + #(options.recordTypes or {}) + #(options.patches or {})
    filters += #(options.objectFilters or {}) + if options.fileFilters then 1 else 0
  end

  return `{merges} merges, {lists} lists, {filters} filters`
end, function(result: string): string return result end)

workload(
  'the command, five plugins',
  '0, 804 records b407f6140b12dad108de99a89fac500bf7edfa57b9579bf45eb1a1abb22ff7dc',
  function(): number return cli.run { '--config', Five.config, '--output-dir', Five.out } end,
  function(status: number): string return `{status}, {records(`{Five.out}/{Merged}`)}` end
)

--- Times the command line run once on `argv`, a process a sample. It must exit 0 and its last
--- line must be `expected`.
local function cold(name: string, expected: string, argv: { string })
  if not binary or not runs(name) then return end

  local arguments = {
    'run',
    '--capability',
    'filesystem.read',
    '--capability',
    'filesystem.write',
    '--package',
    `{Here}/..`,
    '--package-path',
    PackagePath,
    -- Past this, an argument that starts with a dash is the script's and not `jess run`'s.
    '--',
    `{Here}/cold.luau`,
  }

  for _, argument in argv do
    table.insert(arguments, argument)
  end

  local samples: { number } = {}

  for run = 1, 7 do
    local result, message = process.run(binary, arguments, { stdout = 'capture', stderr = 'null' })
    if not result then error(`{name}: {message}`, 0) end

    local printed = result.stdout or ''
    local last, status, seconds = string.match(printed, '([^\n]*)\n\n(%d+)\t([%d.]+)\n$')
    if status ~= '0' or last ~= expected then
      error(`{name}: exited {status} having printed "{last}", not 0 and "{expected}"`, 0)
    end

    samples[run] = tonumber(seconds) :: number
  end

  print(`{name}\t{string.format('%.9f', median(samples))}`)
end

cold('cold: --version', cli.version, { '--version' })

cold(
  'cold: the command, three small plugins',
  `tes3merge: wrote 26 merged records to {Small.out}/{Merged}`,
  { '--config', Small.config, '--output-dir', Small.out }
)

cold(
  'cold: the command, five plugins',
  `tes3merge: wrote 804 merged records to {Five.out}/{Merged}`,
  { '--config', Five.config, '--output-dir', Five.out }
)

io(fs.remove(Root, { recursive = true }))
