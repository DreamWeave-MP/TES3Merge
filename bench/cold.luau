--!strict
--[[
One process of the bench's cold workloads: what the command line pays when it runs once, from its
first `require` on, every module it needs compiling as it is loaded:

  jess run --capability filesystem.read --capability filesystem.write --package . \
    --package-path .. bench/cold.luau <argv>...

The arguments are `tes3merge`'s own. Prints what the command printed, then a line holding its
exit status and the seconds it took, tab-separated. `bench.luau` runs it, seven processes a
workload.
]]

local started = os.clock()
local cli = require '@tes3merge/cli'
local status = cli.run { ... }

print(`\n{status}\t{string.format('%.9f', os.clock() - started)}`)
