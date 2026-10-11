--!strict
--!native
-- `@tes3merge` over load orders built in scratch: every scenario of the tool's old harness
-- (`libs/cli/tests/tes3merge.rs`), asserting what it asserted of the merged plugin, the
-- configuration, and what the tool printed; then what the tool leaves in its report.
local fixtures = require './fixtures'
local fs = require '@dream/fs'
local process = require '@dream/process'
local tes3 = require '@tes3'
local tes3merge = require '@tes3merge'
local test = require '@jess/test'

local expect = test.expect
local suite = test.new()

local Merged = 'Merged Objects.esp'

type Record = { [string]: any }

--- The record of type `tag` named `id`, decoded.
local function record(merged: tes3.Plugin, tag: string, id: string): Record
  local index = assert(tes3.records.find(merged, tag, id), `the merge has no {tag} {id}`)
  return merged:decode(index) :: Record
end

--- The first record of type `tag`, as its index.
local function first(merged: tes3.Plugin, tag: string): number?
  for index = 0, merged:count() - 1 do
    if merged:tag(index) == tag then return index end
  end

  return nil
end

local function masterNames(merged: tes3.Plugin): { string }
  local names = {}
  for _, master in merged:masters() do
    table.insert(names, master.name)
  end

  return names
end

--- The size of record `index`'s first `tag` subrecord.
local function subrecordSize(merged: tes3.Plugin, index: number, tag: string): number?
  for _, subrecord in merged:subrecords(index) do
    if subrecord.tag == tag then return subrecord.size end
  end

  return nil
end

--- A harness scenario that merges `files` with only an output folder set, and gives the result.
local function mergeAndOpen(
  name: string,
  content: { string },
  files: { [string]: { fixtures.Fields } }
): tes3.Plugin
  local order = fixtures.order(name, files, content)
  fixtures.merge(order, { outputDir = order.out })
  return fixtures.open(jess.fs.join(order.out, Merged))
end

suite.describe('merging', function()
  suite.it('merges the load order', function()
    local order = fixtures.order('merge', fixtures.Objects, fixtures.Three)
    local run = fixtures.merge(order, { ignoreRecords = { 'STAT' }, outputDir = order.out })
    expect(run.printed).toContain 'wrote 4 merged records'

    local merged = fixtures.open(jess.fs.join(order.out, Merged))
    expect(masterNames(merged)).toEqual { 'Base.esm', 'A.esp', 'B.esp' }
    for _, master in merged:masters() do
      expect(master.size).toBe(jess.fs.size(jess.fs.join(order.data, master.name)))
    end

    expect(merged:masters()[1].size > 0).toBe(true)
    expect(merged:header().author).toBe 'TES3Merge'

    local gem = record(merged, 'MISC', 'jess_gem')
    expect(gem.name).toBe 'Shiny Gem'
    expect(gem.data.value).toBe(20)

    local items = {}
    for _, entry in record(merged, 'LEVI', 'jess_list').items do
      table.insert(items, entry[1])
    end

    expect(items).toEqual { 'jess_extra', 'jess_gem', 'jess_new', 'jess_old' }

    local npc = record(merged, 'NPC_', 'jess_npc')
    expect(npc.data.level).toBe(10)
    expect(npc.data.gold).toBe(99)

    -- Filtered types don't merge, and neither does a record one file defines.
    expect(tes3.records.find(merged, 'STAT', 'jess_rock')).toBeNil()
    expect(tes3.records.find(merged, 'ACTI', 'jess_single')).toBeNil()
    expect(record(merged, 'CREA', 'atronach_flame_summon').flags).toContain 'PERSISTENT'
    expect(merged:count()).toBe(5)
    expect(merged:header().recordCount).toBe(4)

    -- TES3Merge leaves openmw.cfg alone unless asked.
    expect((string.find(fixtures.read(order.config), Merged, 1, true))).toBeNil()
  end)

  suite.it('fixes cells and honors filters', function()
    local order = fixtures.order(
      'cells',
      fixtures.Cells,
      { 'Base.esm', 'A.esp', 'B.esp', 'Ignored.esp' },
      { dataLocal = true }
    )
    fixtures.merge(order, {
      objectFilters = { { '^ttm_', false } },
      fileFilters = { ['Ignored.esp'] = false },
      activate = true,
    })

    -- Without outputDir, the merge goes to data-local, and `activate` enables it.
    expect(jess.fs.exists(jess.fs.join(order.data, Merged))).toBe(false)
    local merged = fixtures.open(jess.fs.join(order.dataLocal, Merged))

    local cells: { [string]: Record } = {}
    for index = 0, merged:count() - 1 do
      if merged:tag(index) ~= 'CELL' then continue end

      local cell = merged:decode(index) :: Record
      cells[cell.name] = cell
    end

    -- The rename survives a later plugin's original name, and fogbugged interiors get fog.
    expect(cells['My City'] ~= nil).toBe(true)
    expect(#cells['My City'].references).toBe(0)
    expect(cells['Jess Room'].atmosphereData.fogDensity > 0).toBe(true)

    -- Object filters skip matching ids, and ignored files aren't read.
    expect(tes3.records.find(merged, 'MISC', 'ttm_gem')).toBeNil()
    expect(record(merged, 'MISC', 'jess_kept').data.value).toBe(2)
    expect(fixtures.read(order.config)).toContain 'content=Merged Objects.esp'
  end)

  suite.it('merges a real load order when JESS_TES3MERGE_CFG names one', function()
    -- `process.env` throws in a runtime without the process.environment capability, which
    -- `jess package test` doesn't grant: the scenario is skipped there, as it is without the
    -- variable.
    local readable, real = pcall(process.env, 'JESS_TES3MERGE_CFG')
    if not readable or not real or real == '' then return end

    -- The real configuration is only read. A configuration chained after it sets data-local to
    -- this case's own folder, so nothing the merge writes can land in the real data folders.
    local realFolder = if jess.fs.isDir(real) then real else assert(jess.fs.parent(real))
    local order = fixtures.order('real', {}, {})
    jess.fs.write(jess.fs.join(order.dataLocal, 'openmw.cfg'), `data-local="{order.out}"\n`)
    jess.fs.write(
      order.config,
      `config="{realFolder}"\nconfig="{order.dataLocal}"\ndata="{order.data}"\n`
    )

    local started = os.clock()
    local run = fixtures.merge(order, { outputDir = order.out })
    print(`{string.gsub(run.printed, '%s+$', '')} in {os.clock() - started}s`)
  end)

  suite.it('takes native patch names', function()
    local cases: { { patches: { string }, patched: boolean } } = {
      { patches = { 'ALL' }, patched = true },
      { patches = { 'none' }, patched = false },
      { patches = { 'cellnames', 'summons' }, patched = true },
    }

    for _, case in cases do
      local order = fixtures.order('patches', fixtures.Objects, fixtures.Three)
      fixtures.merge(order, { patches = case.patches, outputDir = order.out })

      local merged = fixtures.open(jess.fs.join(order.out, Merged))
      local summon = tes3.records.find(merged, 'CREA', 'atronach_flame_summon')
      expect(summon ~= nil).toBe(case.patched)
    end

    local order = fixtures.order('bad-patch', fixtures.Objects, fixtures.Three)
    expect(
      function() fixtures.merge(order, { patches = { 'fogbugs' }, outputDir = order.out }) end
    ).toThrow 'unknown patch "fogbugs"'
    expect(jess.fs.exists(jess.fs.join(order.out, Merged))).toBe(false)
  end)

  suite.it('reads and writes the configured encoding', function()
    local cases: { { options: fixtures.Fields, lines: string } } = {
      { options = { verbose = true }, lines = 'encoding=win1251\n' },
      { options = { verbose = true, encoding = 1251 }, lines = '' },
    }

    for _, case in cases do
      local order = fixtures.order(
        'encoding',
        fixtures.Cyrillic,
        fixtures.Three,
        { dataLocal = true, lines = case.lines, encoding = 'win1251' }
      )
      local run = fixtures.merge(order, case.options)

      -- Ids read in the wrong encoding would print as mojibake.
      expect(run.printed).toContain 'Merged MISC record: jess_меч'

      local merged = fixtures.open(jess.fs.join(order.dataLocal, Merged), 'win1251')
      local sword: Record?
      for index = 0, merged:count() - 1 do
        if merged:tag(index) ~= 'MISC' then continue end

        expect(tes3.records.id(merged, index)).toBe 'jess_меч'
        sword = merged:decode(index) :: Record
      end

      local found = assert(sword, 'the sword merges')
      expect(found.id).toBe 'jess_меч'
      expect(found.name).toBe 'Острый меч'
      expect(found.data.value).toBe(5)
    end

    local order = fixtures.order('bad-encoding', fixtures.Objects, fixtures.Three)
    expect(function() fixtures.merge(order, { encoding = 932 }) end).toThrow 'encoding code 932 isn\'t supported'
  end)

  suite.it('writes to the first data folder without data-local', function()
    local order = fixtures.order('first-data', fixtures.Objects, fixtures.Three)
    fixtures.merge(order, {})
    expect(jess.fs.isFile(jess.fs.join(order.data, Merged))).toBe(true)
  end)

  suite.it('creates its output folder', function()
    local order = fixtures.order('new-folder', fixtures.Objects, fixtures.Three)
    assert((fs.remove(order.out, { recursive = true })))
    fixtures.merge(order, { outputDir = order.out .. '/new/merged' })
    expect(jess.fs.isFile(jess.fs.join(order.out, 'new/merged/' .. Merged))).toBe(true)
  end)

  suite.it('leaves a merge outside the data folders inactive', function()
    local order = fixtures.order('outside', fixtures.Objects, fixtures.Three)
    local before = fixtures.read(order.config)
    local run = fixtures.merge(order, { outputDir = order.out, activate = true })
    expect(jess.fs.isFile(jess.fs.join(order.out, Merged))).toBe(true)
    expect(run.printed).toContain 'didn\'t activate it'
    expect(fixtures.read(order.config)).toBe(before)
  end)

  suite.it('keeps free text byte for byte', function()
    local merged = mergeAndOpen('text', fixtures.Three, fixtures.Text)
    local bare = assert(tes3.records.find(merged, 'BOOK', 'jess_bare'), 'both books merge')
    local terminated = assert(tes3.records.find(merged, 'BOOK', 'jess_nul'), 'both books merge')
    expect((merged:decode(bare) :: Record).data.weight).toBe(2)
    expect((merged:decode(bare) :: Record).data.value).toBe(5)

    -- TEXT without a terminator keeps none, and TEXT with one keeps it.
    expect(subrecordSize(merged, bare, 'TEXT')).toBe(4)
    expect(subrecordSize(merged, terminated, 'TEXT')).toBe(5)

    -- A middle plugin's DESC keeps its spelling.
    local effect = assert(first(merged, 'MGEF'), 'the effect merges')
    expect((merged:decode(effect) :: Record).description).toBe 'New'
    expect(subrecordSize(merged, effect, 'DESC')).toBe(3)
  end)

  suite.it('keeps a string subrecord a middle plugin leaves out', function()
    local merged = mergeAndOpen('removed', fixtures.Three, fixtures.Removed)
    local effect = merged:decode(assert(first(merged, 'MGEF'), 'the effect merges')) :: Record

    -- A middle plugin leaving BSND out keeps the latest one.
    expect(effect.boltSound).toBe 'bolt'
    expect(effect.castSound).toBe 'new cast'
    expect(effect.hitSound).toBe 'new hit'
  end)

  suite.it('patches only what the merge leaves alone', function()
    local merged = mergeAndOpen('patched', fixtures.Three, fixtures.Patched)
    local atronach = record(merged, 'CREA', 'atronach_frost_summon')
    expect(atronach.name).toBe 'Frost Atronach'
    expect(atronach.script).toBe 'jess_script'

    -- A merged record isn't patched; a record the merge leaves alone is.
    expect((string.find(atronach.flags, 'PERSISTENT', 1, true))).toBeNil()
    expect(record(merged, 'CREA', 'scamp_summon').flags).toContain 'PERSISTENT'
  end)

  suite.it('lists every plugin the merge walked as a master', function()
    local merged =
      mergeAndOpen('masters', { 'Base.esm', 'A.esp', 'C.esp', 'B.esp' }, fixtures.Masters)
    local lever = record(merged, 'ACTI', 'jess_lever')
    expect(lever.name).toBe 'Old Lever'
    expect(lever.mesh).toBe 'b.nif'
    expect(masterNames(merged)).toEqual { 'Base.esm', 'A.esp', 'C.esp', 'B.esp' }
  end)

  suite.it('writes records by type then id in first-seen order', function()
    local merged = mergeAndOpen('order', fixtures.Three, fixtures.Sequence)
    local sequence = {}
    for index = 0, merged:count() - 1 do
      local tag = merged:tag(index)
      if tag ~= 'TES3' then table.insert(sequence, `{tag} {tes3.records.id(merged, index)}`) end
    end

    expect(sequence).toEqual { 'MISC jess_a', 'MISC jess_c', 'BOOK jess_b' }
  end)
end)

suite.describe('the port', function()
  suite.it('needs a Context', function()
    expect(function() tes3merge({}, nil) end).toThrow 'tes3merge needs an OpenMW config'
  end)

  suite.it('leaves its report in state.tes3merge', function()
    local order = fixtures.order('report', fixtures.Objects, fixtures.Three)
    local run = fixtures.merge(order, { ignoreRecords = { 'STAT' }, outputDir = order.out })
    local path = `{order.out}/{Merged}`
    expect((run.state.tes3merge :: Record).report).toEqual {
      path = path,
      masters = { 'Base.esm', 'A.esp', 'B.esp' },
      files = 3,
      candidates = 3,
      merged = { MISC = 1, LEVI = 1, NPC_ = 1, CREA = 1 },
      failed = {},
    }

    expect(run.printed).toBe(`tes3merge: wrote 4 merged records to {path}\n`)
  end)

  suite.it('creates the options table of a state without one', function()
    local order = fixtures.order('defaults', fixtures.Objects, fixtures.Three, { dataLocal = true })
    local run = fixtures.merge(order, nil)
    local report = (run.state.tes3merge :: Record).report
    expect(report.path).toBe(`{order.dataLocal}/{Merged}`)

    -- Statics are merged by default, so the rock is a candidate too.
    expect(report.candidates).toBe(4)
    expect(report.activated).toBeNil()
  end)

  suite.it('writes nothing when nothing needs merging', function()
    local order = fixtures.order('nothing', fixtures.Objects, { 'Base.esm', 'B.esp' })
    local run = fixtures.merge(order, { patches = { 'none' }, outputDir = order.out })
    expect(run.printed).toBe 'tes3merge: no merges were deemed necessary\n'
    expect(jess.fs.exists(jess.fs.join(order.out, Merged))).toBe(false)
    expect((run.state.tes3merge :: Record).report).toEqual {
      masters = {},
      files = 2,
      candidates = 0,
      merged = {},
      failed = {},
    }
  end)

  suite.it('lists a plugin it can\'t read as failed, and merges the rest', function()
    local order = fixtures.order(
      'unreadable',
      fixtures.Objects,
      { 'Base.esm', 'Broken.esp', 'A.esp', 'Missing.esp', 'B.esp', 'Scripts.omwscripts' }
    )
    local broken = jess.fs.join(order.data, 'Broken.esp')
    jess.fs.write(broken, 'not a plugin')
    jess.fs.write(jess.fs.join(order.data, 'Scripts.omwscripts'), 'PLAYER: scripts/player.lua\n')

    local run = fixtures.merge(order, { outputDir = order.out })
    local report = (run.state.tes3merge :: Record).report

    -- A content file no data folder has isn't a failure, and a script list isn't a plugin.
    expect(report.failed).toEqual {
      `Broken.esp: failed to parse '{broken}': truncated record header at offset 0`,
    }
    expect(report.files).toBe(3)
    expect(report.masters).toEqual { 'Base.esm', 'A.esp', 'B.esp' }
  end)

  suite.it('writes no master list with noMasters', function()
    local order = fixtures.order('no-masters', fixtures.Objects, fixtures.Three)
    local run = fixtures.merge(order, { noMasters = true, outputDir = order.out })
    expect(fixtures.open(jess.fs.join(order.out, Merged)):masters()).toEqual {}
    expect((run.state.tes3merge :: Record).report.masters).toEqual {}
  end)

  suite.it('merges inventories as a union with inclusive', function()
    local function chest(inventory: { { unknown } }): fixtures.Fields
      return { type = 'Container', id = 'jess_chest', name = 'Chest', inventory = inventory }
    end

    local files = {
      ['Base.esm'] = { chest { { 1, 'jess_gem' } } },
      ['A.esp'] = { chest { { 1, 'jess_gem' }, { 2, 'jess_key' } } },
      ['B.esp'] = { chest { { 1, 'jess_gem' }, { 3, 'jess_coin' } } },
    }

    local latest = fixtures.order('exclusive', files, fixtures.Three)
    fixtures.merge(latest, { outputDir = latest.out })
    expect(jess.fs.exists(jess.fs.join(latest.out, Merged))).toBe(false)

    local union = fixtures.order('inclusive', files, fixtures.Three)
    fixtures.merge(union, { inclusive = true, outputDir = union.out })
    local merged = fixtures.open(jess.fs.join(union.out, Merged))
    expect(record(merged, 'CONT', 'jess_chest').inventory).toEqual {
      { 1, 'jess_gem' },
      { 3, 'jess_coin' },
      { 2, 'jess_key' },
    }
  end)

  suite.it('saves the configuration when the merge is already active', function()
    local order = fixtures.order('active', fixtures.Objects, fixtures.Three, { dataLocal = true })
    local first = fixtures.merge(order, { activate = true })
    expect((first.state.tes3merge :: Record).report.activated).toBe(true)
    expect(fixtures.read(order.config)).toContain 'content=Merged Objects.esp'
    expect(jess.fs.isFile(order.config .. '.bak')).toBe(true)
    expect(jess.fs.exists(order.config .. '.bak1')).toBe(false)

    -- The second run finds the merge in the content already, reads past it, and still saves.
    local saved = fixtures.read(order.config)
    local again = fixtures.merge(order, { activate = true })
    expect((again.state.tes3merge :: Record).report.activated).toBe(true)
    expect((again.state.tes3merge :: Record).report.files).toBe(3)
    expect(fixtures.read(order.config)).toBe(saved)
    expect(jess.fs.isFile(order.config .. '.bak1')).toBe(true)
  end)
end)

return suite
