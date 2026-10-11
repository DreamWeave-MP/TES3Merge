--!strict
--!native
-- `@tes3merge/cli`: the argument lists it reads into the merge's options, the ones it refuses and
-- why, the exit status of each way a run can end, and whole runs over the harness's load orders.
-- Its messages go to the suite's own standard error.
local cli = require '@tes3merge/cli'
local fixtures = require './fixtures'
local tes3 = require '@tes3'
local test = require '@jess/test'

local expect = test.expect
local suite = test.new()

local Merged = 'Merged Objects.esp'

-- Each argument list `parse` refuses, and what it says of it.
local Refused: { { argv: { string }, message: string } } = {
  { argv = { '--bogus' }, message = 'unknown option \'--bogus\'' },
  { argv = { '--Inclusive' }, message = 'unknown option \'--Inclusive\'' },
  { argv = { '-n' }, message = 'unknown option \'-n\'' },
  { argv = { '-I' }, message = 'unknown option \'-I\'' },
  { argv = { '--i' }, message = 'unknown option \'--i\'' },
  { argv = { '-ir' }, message = 'unknown option \'-ir\'' },
  { argv = { '--inclusive=true' }, message = 'unknown option \'--inclusive=true\'' },
  { argv = { '--records=NPC_' }, message = 'unknown option \'--records=NPC_\'' },
  { argv = { '--nomasters' }, message = 'unknown option \'--nomasters\'' },
  { argv = { '--' }, message = 'unknown option \'--\'' },
  { argv = { '--records' }, message = '--records requires a record type' },
  { argv = { '--records', '--inclusive' }, message = '--records requires a record type' },
  { argv = { '-r' }, message = '-r requires a record type' },
  { argv = { '--ignore-records' }, message = '--ignore-records requires a record type' },
  { argv = { '--ir', '-i' }, message = '--ir requires a record type' },
  { argv = { '--record-types' }, message = '--record-types requires a record type' },
  { argv = { '--patches' }, message = '--patches requires a patch name' },
  { argv = { '--patches', '--no-masters' }, message = '--patches requires a patch name' },
  { argv = { '--config' }, message = '--config requires an openmw.cfg or its folder' },
  { argv = { '--encoding' }, message = '--encoding requires an encoding' },
  { argv = { '--output-dir' }, message = '--output-dir requires a folder' },
  { argv = { '--file-name' }, message = '--file-name requires a file name' },
  { argv = { '--file-filter' }, message = '--file-filter requires <file>=<true|false>' },
  { argv = { '--object-filter' }, message = '--object-filter requires <pattern>=<true|false>' },
  {
    argv = { '--file-filter', 'A.esp' },
    message = '--file-filter takes <file>=<true|false>, not \'A.esp\'',
  },
  {
    argv = { '--file-filter', 'A.esp=no' },
    message = '--file-filter takes <file>=<true|false>, not \'A.esp=no\'',
  },
  {
    argv = { '--file-filter', '=false' },
    message = '--file-filter takes <file>=<true|false>, not \'=false\'',
  },
  {
    argv = { '--object-filter', '^ttm_' },
    message = '--object-filter takes <pattern>=<true|false>, not \'^ttm_\'',
  },
  {
    argv = { '--object-filter', '^ttm_=' },
    message = '--object-filter takes <pattern>=<true|false>, not \'^ttm_=\'',
  },
  { argv = { 'multipatch' }, message = 'the multipatch command isn\'t ported: tes3merge only merges' },
  {
    argv = { 'verify', '--verbose' },
    message = 'the verify command isn\'t ported: tes3merge only merges',
  },
  { argv = { 'merge' }, message = 'unexpected argument \'merge\'' },
  { argv = { 'help' }, message = 'unexpected argument \'help\'' },
  { argv = { '--inclusive', 'multipatch' }, message = 'unexpected argument \'multipatch\'' },
  { argv = { '--activate', 'NPC_' }, message = 'unexpected argument \'NPC_\'' },
  { argv = { '--output-dir', 'out', 'elsewhere' }, message = 'unexpected argument \'elsewhere\'' },
  { argv = { '--help', '--bogus' }, message = 'unknown option \'--bogus\'' },
}

--- The command an argument list names, without the message that comes with a refusal.
local function parsed(argv: { string }): cli.Command? return (cli.parse(argv)) end

--- The merged plugin a run left in `folder`.
local function merged(folder: string): tes3.Plugin
  return fixtures.open(jess.fs.join(folder, Merged))
end

suite.describe('parse', function()
  suite.it('reads no arguments as a merge with nothing set', function()
    local command, message = cli.parse {}
    expect(command).toEqual { action = 'merge', options = {} }
    expect(message).toBeNil()
  end)

  suite.it('maps each of TES3Merge\'s flags onto its option', function()
    expect(parsed { '--records', 'NPC_' }).toEqual {
      action = 'merge',
      options = { records = { 'NPC_' } },
    }

    expect(parsed { '--ignore-records', 'STAT' }).toEqual {
      action = 'merge',
      options = { ignoreRecords = { 'STAT' } },
    }

    expect(parsed { '--inclusive' }).toEqual { action = 'merge', options = { inclusive = true } }
    expect(parsed { '--no-masters' }).toEqual { action = 'merge', options = { noMasters = true } }

    for _, name in { 'fogbug', 'summons', 'cellnames', 'all', 'none' } do
      expect(parsed { '--patches', name }).toEqual {
        action = 'merge',
        options = { patches = { name } },
      }
    end
  end)

  suite.it('takes TES3Merge\'s other spellings as the same flags', function()
    expect(parsed { '-i' }).toEqual { action = 'merge', options = { inclusive = true } }
    expect(parsed { '-r', 'NPC_', 'CREA' }).toEqual {
      action = 'merge',
      options = { records = { 'NPC_', 'CREA' } },
    }

    expect(parsed { '--ir', 'STAT' }).toEqual {
      action = 'merge',
      options = { ignoreRecords = { 'STAT' } },
    }

    expect(parsed { '-p', 'fogbug' }).toEqual { action = 'merge', options = { patches = { 'fogbug' } } }

    -- A flag repeated under another spelling adds to what the first gave.
    expect(parsed { '-r', 'NPC_', '--records', 'CREA', '-i', '-r', 'LEVI', '--inclusive' }).toEqual {
      action = 'merge',
      options = { records = { 'NPC_', 'CREA', 'LEVI' }, inclusive = true },
    }

    expect(parsed { '--ignore-records', 'STAT', '--ir', 'MISC', '-p', 'none', '--patches', 'all' }).toEqual {
      action = 'merge',
      options = { ignoreRecords = { 'STAT', 'MISC' }, patches = { 'none', 'all' } },
    }
  end)

  suite.it('maps each TES3Merge.ini setting\'s flag onto its option', function()
    expect(parsed { '--record-types', 'MISC', 'BOOK' }).toEqual {
      action = 'merge',
      options = { recordTypes = { 'MISC', 'BOOK' } },
    }

    expect(parsed { '--file-filter', 'S3LightFixes.omwaddon=false' }).toEqual {
      action = 'merge',
      options = { fileFilters = { ['S3LightFixes.omwaddon'] = false } },
    }

    expect(parsed { '--object-filter', '^ttm_=false' }).toEqual {
      action = 'merge',
      options = { objectFilters = { { '^ttm_', false } } },
    }

    expect(parsed { '--encoding', 'win1251' }).toEqual {
      action = 'merge',
      options = { encoding = 'win1251' },
    }

    expect(parsed { '--output-dir', 'merged here' }).toEqual {
      action = 'merge',
      options = { outputDir = 'merged here' },
    }
  end)

  suite.it('maps each of the port\'s own flags onto its option', function()
    expect(parsed { '--file-name', 'Merged.omwaddon' }).toEqual {
      action = 'merge',
      options = { fileName = 'Merged.omwaddon' },
    }

    expect(parsed { '--activate' }).toEqual { action = 'merge', options = { activate = true } }
    expect(parsed { '--verbose' }).toEqual { action = 'merge', options = { verbose = true } }
    expect(parsed { '--config', 'some/openmw.cfg' }).toEqual {
      action = 'merge',
      config = 'some/openmw.cfg',
      options = {},
    }
  end)

  suite.it('reads a whole command line', function()
    local command = cli.parse {
      '--config',
      'cfg',
      '--records',
      'NPC_',
      'CREA',
      '--ignore-records',
      'LEVI',
      '--inclusive',
      '--no-masters',
      '--patches',
      'fogbug',
      'summons',
      '--record-types',
      'NPC_',
      'CREA',
      'LEVI',
      '--file-filter',
      'A.esp=false',
      '--object-filter',
      '^ttm_=false',
      '--encoding',
      '1251',
      '--output-dir',
      'out',
      '--file-name',
      'Merged.esp',
      '--activate',
      '--verbose',
    }

    expect(command).toEqual {
      action = 'merge',
      config = 'cfg',
      options = {
        records = { 'NPC_', 'CREA' },
        ignoreRecords = { 'LEVI' },
        inclusive = true,
        noMasters = true,
        patches = { 'fogbug', 'summons' },
        recordTypes = { 'NPC_', 'CREA', 'LEVI' },
        fileFilters = { ['A.esp'] = false },
        objectFilters = { { '^ttm_', false } },
        encoding = 1251,
        outputDir = 'out',
        fileName = 'Merged.esp',
        activate = true,
        verbose = true,
      },
    }
  end)

  suite.it('takes every value up to the next flag, and adds a repeated flag\'s to them', function()
    expect(parsed { '--records', 'NPC_', 'CREA', '--verbose', '--records', 'LEVI' }).toEqual {
      action = 'merge',
      options = { records = { 'NPC_', 'CREA', 'LEVI' }, verbose = true },
    }

    expect(parsed { '--patches', 'none', '--patches', 'fogbug', 'ALL' }).toEqual {
      action = 'merge',
      options = { patches = { 'none', 'fogbug', 'ALL' } },
    }

    -- Values go to the merge as they are spelled: it decides what a record type or a patch is.
    expect(parsed { '--ignore-records', 'stat', 'no such type' }).toEqual {
      action = 'merge',
      options = { ignoreRecords = { 'stat', 'no such type' } },
    }
  end)

  suite.it('keeps filters in order, splitting each at its last =', function()
    local command = cli.parse {
      '--object-filter',
      '^ttm_=false',
      '--file-filter',
      'A.esp=FALSE',
      '--object-filter',
      '^ttm_(a|b)=c$=True',
      '--file-filter',
      'Name=With=Equals.esp=true',
      '--file-filter',
      'A.esp=true',
    }

    expect(command).toEqual {
      action = 'merge',
      options = {
        objectFilters = { { '^ttm_', false }, { '^ttm_(a|b)=c$', true } },
        fileFilters = { ['A.esp'] = true, ['Name=With=Equals.esp'] = true },
      },
    }
  end)

  suite.it('reads a code page number as a number and anything else as it is spelled', function()
    expect(assert(assert(cli.parse { '--encoding', '1250' }).options).encoding).toBe(1250)
    expect(assert(assert(cli.parse { '--encoding', '932' }).options).encoding).toBe(932)
    expect(assert(assert(cli.parse { '--encoding', 'win1252' }).options).encoding).toBe 'win1252'
    expect(assert(assert(cli.parse { '--encoding', 'cp1252' }).options).encoding).toBe 'cp1252'
  end)

  suite.it('takes what follows a one-value flag as it is spelled, the last use winning', function()
    expect(parsed { '--output-dir', '--verbose', '--file-name', '-.esp' }).toEqual {
      action = 'merge',
      options = { outputDir = '--verbose', fileName = '-.esp' },
    }

    expect(parsed { '--config', 'first', '--output-dir', 'one', '--config', 'second' }).toEqual {
      action = 'merge',
      config = 'second',
      options = { outputDir = 'one' },
    }
  end)

  suite.it('reads help under either spelling, wherever it is', function()
    for _, argv in { { '--help' }, { '-h' }, { '--verbose', '--help' }, { '-h', '--config', 'cfg' } } do
      local command, message = cli.parse(argv)
      expect(command).toEqual { action = 'help' }
      expect(message).toBeNil()
    end
  end)

  suite.it('refuses what it can\'t read, and says why', function()
    for _, case in Refused do
      local command, message = cli.parse(case.argv)
      expect(command).toBeNil()
      expect(message).toBe(case.message)
    end
  end)

  suite.it('leaves the argument list as it was, and gives each parse its own options', function()
    local argv = { '--records', 'NPC_', 'CREA', '--file-filter', 'A.esp=false' }
    local first, second = assert(cli.parse(argv)), assert(cli.parse(argv))
    expect(argv).toEqual { '--records', 'NPC_', 'CREA', '--file-filter', 'A.esp=false' }
    expect(first.options ~= second.options).toBe(true)
    expect(assert(first.options).records ~= assert(second.options).records).toBe(true)
    expect(assert(first.options).fileFilters ~= assert(second.options).fileFilters).toBe(true)
  end)
end)

suite.describe('run', function()
  suite.it(
    'numbers its exit statuses as starwind does',
    function() expect(cli.Exit).toEqual { ok = 0, invalidInput = 8, runtime = 9 } end
  )

  suite.it('returns 0 for help', function()
    expect(cli.run { '--help' }).toBe(0)
    expect(cli.run { '-h' }).toBe(0)
  end)

  suite.it('returns 8 for every command line parse refuses', function()
    for _, case in Refused do
      expect(cli.run(case.argv)).toBe(8)
    end
  end)

  suite.it('returns 8 without a configuration', function()
    -- `jess package test` grants no process.environment, so OPENMW_CONFIG can't name one here.
    expect(cli.run {}).toBe(8)
    expect(cli.run { '--verbose' }).toBe(8)
    expect(cli.run { '--config', '' }).toBe(8)
  end)

  suite.it('returns 8 for a configuration that isn\'t there, and writes nothing', function()
    local order = fixtures.order('cli-missing', fixtures.Objects, fixtures.Three)
    local before = fixtures.read(order.config)
    expect(cli.run { '--config', jess.fs.join(order.root, 'nowhere/openmw.cfg') }).toBe(8)
    expect(cli.run { '--config', jess.fs.join(order.root, 'nowhere') }).toBe(8)

    -- A folder is the configuration only when it holds an openmw.cfg.
    expect(cli.run { '--config', order.data }).toBe(8)
    expect(jess.fs.exists(jess.fs.join(order.data, Merged))).toBe(false)
    expect(fixtures.read(order.config)).toBe(before)
  end)

  suite.it('merges the load order --config names', function()
    local order = fixtures.order('cli-merge', fixtures.Objects, fixtures.Three)
    fixtures.forget()
    expect(cli.run {
      '--config',
      order.config,
      '--ignore-records',
      'STAT',
      '--output-dir',
      order.out,
    }).toBe(0)

    -- The module's own first scenario, through the command line.
    expect(fixtures.output()).toBe(`tes3merge: wrote 4 merged records to {order.out}/{Merged}\n`)

    local plugin = merged(order.out)
    local masters = {}
    for _, master in plugin:masters() do
      table.insert(masters, master.name)
      expect(master.size).toBe(jess.fs.size(jess.fs.join(order.data, master.name)))
    end

    expect(masters).toEqual { 'Base.esm', 'A.esp', 'B.esp' }
    expect(plugin:header().author).toBe 'TES3Merge'

    local sequence = {}
    for index = 1, plugin:count() - 1 do
      table.insert(sequence, `{plugin:tag(index)} {tes3.records.id(plugin, index)}`)
    end

    expect(sequence).toEqual {
      'MISC jess_gem',
      'LEVI jess_list',
      'NPC_ jess_npc',
      'CREA atronach_flame_summon',
    }

    local gem = plugin:decode(assert(tes3.records.find(plugin, 'MISC', 'jess_gem'))) :: { [string]: any }
    expect(gem.name).toBe 'Shiny Gem'
    expect(gem.data.value).toBe(20)
    expect((string.find(fixtures.read(order.config), Merged, 1, true))).toBeNil()
  end)

  suite.it('takes the folder that holds the configuration, and every option with it', function()
    local order = fixtures.order(
      'cli-options',
      fixtures.Cells,
      { 'Base.esm', 'A.esp', 'B.esp', 'Ignored.esp' },
      { dataLocal = true }
    )
    fixtures.forget()
    expect(cli.run {
      '--config',
      order.root,
      '--object-filter',
      '^ttm_=false',
      '--file-filter',
      'Ignored.esp=false',
      '--file-name',
      'Merged.omwaddon',
      '--no-masters',
      '--activate',
      '--verbose',
    }).toBe(0)

    -- The module's cells scenario, through the command line, under another name.
    local path = `{order.dataLocal}/Merged.omwaddon`
    expect(fixtures.output()).toContain 'Merged CELL record: #3,-2\n'
    expect(fixtures.output()).toContain 'Merged CELL record: jess room\n'
    expect(fixtures.output()).toContain(`tes3merge: wrote 3 merged records to {path}\n`)

    local plugin = fixtures.open(path)
    expect(plugin:masters()).toEqual {}
    expect(tes3.records.find(plugin, 'MISC', 'ttm_gem')).toBeNil()

    local kept = plugin:decode(assert(tes3.records.find(plugin, 'MISC', 'jess_kept'))) :: { [string]: any }
    expect(kept.data.value).toBe(2)
    expect(fixtures.read(order.config)).toContain 'content=Merged.omwaddon'
  end)

  suite.it('reads and writes the encoding it is given', function()
    local order = fixtures.order(
      'cli-encoding',
      fixtures.Cyrillic,
      fixtures.Three,
      { dataLocal = true, encoding = 'win1251' }
    )
    fixtures.forget()
    expect(cli.run { '--config', order.config, '--encoding', '1251', '--verbose' }).toBe(0)
    expect(fixtures.output()).toContain 'Merged MISC record: jess_меч'

    local plugin = fixtures.open(jess.fs.join(order.dataLocal, Merged), 'win1251')
    local sword = plugin:decode(assert(tes3.records.find(plugin, 'MISC', 'jess_меч'))) :: { [string]: any }
    expect(sword.name).toBe 'Острый меч'
  end)

  suite.it('returns 9 when the merge raises, having written nothing', function()
    local order = fixtures.order('cli-raises', fixtures.Objects, fixtures.Three)
    local before = fixtures.read(order.config)
    local base = { '--config', order.config, '--output-dir', order.out, '--activate' }

    for _, extra in
      {
        { '--patches', 'fogbugs' },
        { '--encoding', '932' },
        { '--encoding', 'utf8' },
        { '--records', 'stat' },
        { '--record-types', 'MISC', '--ignore-records', 'MISC' },
        { '--object-filter', '(=false' },
      }
    do
      local argv = table.clone(base)
      table.move(extra, 1, #extra, #argv + 1, argv)
      expect(cli.run(argv)).toBe(9)
    end

    expect(jess.fs.exists(jess.fs.join(order.out, Merged))).toBe(false)
    expect(fixtures.read(order.config)).toBe(before)
  end)

  suite.it('returns 9 for a configuration with nowhere to write', function()
    local order = fixtures.order('cli-nowhere', fixtures.Objects, fixtures.Three)
    jess.fs.write(order.config, 'content=Base.esm\n')
    expect(cli.run { '--config', order.config, '--patches', 'none' }).toBe(0)

    -- With something to write and no data folder, the merge stops before writing.
    jess.fs.write(
      order.config,
      `resources="{order.root}/resources"\ndata="{order.root}/resources/vfs"\ncontent=A.esp\n`
    )
    jess.fs.write(
      jess.fs.join(order.root, 'resources/vfs/A.esp'),
      assert(jess.fs.readBuffer(jess.fs.join(order.data, 'A.esp')))
    )
    expect(cli.run { '--config', order.config }).toBe(9)
    expect(jess.fs.exists(jess.fs.join(order.root, 'resources/vfs/' .. Merged))).toBe(false)
  end)

  suite.it('returns 0 for a merge that left plugins out, and for one with nothing to do', function()
    local order = fixtures.order(
      'cli-failed',
      fixtures.Objects,
      { 'Base.esm', 'Broken.esp', 'A.esp', 'B.esp' }
    )
    jess.fs.write(jess.fs.join(order.data, 'Broken.esp'), 'not a plugin')
    expect(cli.run { '--config', order.config, '--output-dir', order.out }).toBe(0)
    expect(merged(order.out):count()).toBe(5)

    local nothing = fixtures.order('cli-nothing', fixtures.Objects, { 'Base.esm', 'B.esp' })
    fixtures.forget()
    expect(cli.run { '--config', nothing.config, '--patches', 'none' }).toBe(0)
    expect(fixtures.output()).toBe 'tes3merge: no merges were deemed necessary\n'
    expect(jess.fs.exists(jess.fs.join(nothing.data, Merged))).toBe(false)
  end)
end)

return suite
