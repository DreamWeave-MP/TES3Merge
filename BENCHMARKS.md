# tes3merge benchmarks

`bench/bench.jsl` times the tool the way it is reached: `@tes3merge` called with an `@openmw`
Context over load orders the bench builds with `@tes3`, the argument lists `@tes3merge/cli`
reads, and the command line, warm and from a cold start. The load order is a master of 6,200
records of the types the tool merges (items, spells with their effects, NPCs and creatures with
their packages and inventories, leveled lists, interior and exterior cells with their references,
settings) and four plugins that define every fourth, sixth, tenth, and fifteenth of them again,
changed, plus records of their own: about 12,300 records in five files, 823 of the master's
defined three times or more. A second order is the master and one plugin, where nothing has
three definitions, which is what most of a real load order looks like; a third is a master of
248 records and two plugins.

A warm workload is warmed up, sized to a batch of about a tenth of a second, and reported as the
median of seven batches with a full collection between them. A `cold:` workload is the median of
seven fresh processes running `bench/cold.jsl`, the command line run once and timed inside the
script from its first `require`. Every merge's report and a digest of the records it wrote are
compared with what the bench has pinned, before the first batch and after the last, so a path
that stops doing the work stops the run instead of posting a time.

```sh
jess run --capability filesystem.read --capability filesystem.write \
  --capability process.spawn --package jpk/tes3merge --package-path jpk \
  jpk/tes3merge/bench/bench.jsl <scratch> [filter] [jess binary] [package path]
```

Without the binary (and `process.spawn`) the cold workloads are skipped. The tool reports through
`print`, so each merge prints its own line among the bench's: the bench's are the ones that hold
a tab.

## The move onto l3i 2.0, base against head

- Machine: Intel Core i7-10870H @ 2.20 GHz, 16 threads, shared with other work while this ran
  (load average 1.3 to 1.7 over the run).
- Date: 2026-10-12.
- Binary: the verified release build of Jess 0.1.0 on l3i 2.0.2 (Luau 0.742), the same one for
  both sides, as are the packages this one depends on.
- Base: `f14c91d`, the package before the move, with this bench. Head: `328c643`; what follows
  it is tests and this page.
- Protocol: the whole bench against an export of base and against head, eight times each in two
  sets of four, alternating and swapping which goes first, each set back to back under one
  lock; each cell is the median of its eight runs. A difference under 5 percent is called no
  change.

| Workload | Base | Head | Base / head |
|---|---:|---:|---:|
| merge five plugins, every type | 50.91 ms | 42.62 ms | 1.19x |
| merge five plugins, inventories as a union | 16.66 ms | 15.66 ms | 1.06x |
| merge five plugins, leveled lists | 8.83 ms | 8.40 ms | no change ¹ |
| merge five plugins, spells, enchantments, and potions | 7.67 ms | 6.99 ms | 1.10x |
| merge five plugins, items | 13.59 ms | 11.55 ms | 1.18x |
| merge five plugins, cells | 14.04 ms | 11.29 ms | 1.24x |
| merge five plugins, three object filters | 51.25 ms | 44.97 ms | 1.14x |
| merge five plugins, no patches, no masters | 46.00 ms | 39.42 ms | 1.17x |
| two plugins, nothing to merge | 15.16 ms | 11.25 ms | 1.35x |
| two plugins, the patches alone | 22.52 ms | 16.63 ms | 1.35x |
| merge three small plugins | 3.14 ms | 2.96 ms | 1.06x |
| parse 8 argument lists | 13.12 µs | 13.68 µs | no change ² |
| the command, five plugins | 50.69 ms | 43.22 ms | 1.17x |
| cold: --version | 303.90 ms | 274.65 ms | 1.11x |
| cold: the command, three small plugins | 316.48 ms | 295.56 ms | 1.07x |
| cold: the command, five plugins | 367.49 ms | 326.52 ms | 1.13x |

This is the table as measured again when the move was reviewed. As first recorded, over four
rounds against `e6abdad`, it read 1.25x, 1.07x, no change, 1.10x, 1.16x, 1.26x, 1.19x, 1.20x,
1.35x, 1.39x, 1.08x, no change, 1.21x, 1.13x, 1.13x, and 1.14x down the rows: each within 6
percent of what is here, and on the high side of it more often than not.

¹ 1.05x here and 1.04x in the run of every commit below: at the threshold, and not over it.

² `@tes3merge/cli` is the same code on both sides. This row read 0.96x and 0.97x in the two
sets, and 1.01x between the same two sides in the run of every commit below.

## What moved, and why

Nothing in this package is a loop over a buffer, so nothing here went to the data plane. What it
does with its time is ask `@tes3` for things (open, a record's tag and id, a decoded record, an
encoded one), and group and compare the tables it gets back. The gains are from asking less and
allocating less. Each commit was measured against the one before it: the warm workloads against
an export of every commit of the move, four rounds, first to last and last to first by turns,
each round back to back under the lock. Three of them (the filters, the fields, the flags) were
measured again as a pair on the rows named, eight rounds, and both readings are given.

- **Grouping** (`f3b5f4f`; nothing to merge 1.32x, the patches alone 1.23x, no patches 1.15x,
  items 1.14x, every type 1.12x). Every record of a merged type went under a key made by
  lowering its id and joining it to its tag, in a table of its own holding the plugin, the
  file's name, and the index, in a list made for its key. An id is now a number from an
  `@dream/intern` pool of its type, which compares ASCII letters without their case and counts
  up in the order ids are first seen, the order the output is written in; a record is one
  number, its plugin's place and its index; and an id one file defines holds that number and no
  list. A load order's records are mostly defined once. This is most of what the table shows.
- **The fog patch** (`b44eb2c`; cells 1.18x, the patches alone 1.05x). A cell is decoded to tell
  an interior from an exterior, which is what identifies it. Every cell fewer than three files
  define was then decoded a second time to see whether the patch would change it; that is read
  from the first decoding now.
- **Object filters** (`5beede2`; three object filters 1.08x over four rounds and 1.05x over
  eight). Each filter listed every record it matched in every plugin, as tables, before any
  record was looked at. A record of a merged type now asks the filters itself, last to first,
  and stops at the one that matches. Most of a filtered merge is still the merge.
- **A cold start** (`9d6a932`; 1.12x, 1.12x, and 1.10x on the three cold rows, four rounds).
  `@tes3cmd`, which only an object filter uses, took about 32 ms of the 305 to 355 a run spent.
  It is loaded when a filter asks for it.
- **Flags** (`e6abdad`; cells 1.04x over four rounds and 1.06x over eight, the patches alone
  1.03x and 1.04x: at the threshold). Whether a flags text holds a name is first asked of the
  text whole, before it is split into its names.
- **Merging fields** (`932c105`) is not shown to have moved anything: 0.98x to 1.05x on the rows
  that merge the most (every type 1.02x and 0.98x, inventories 1.03x both times, spells 1.01x
  and 1.03x, items 1.01x and 1.05x, no patches 1.01x both times). A merge gathered the field
  names of two definitions into a table to walk it; it walks the later definition's fields,
  then the first's that the later lacks. It makes one table fewer for every structure merged
  and gives the same merge, and is kept for that, not for a time.

The dialect itself (`bc1d5ae`: three comprehensions, a sink, a reducer, three record patterns in
generators) measured as no change, as a comprehension should: 0.98x to 1.03x on every warm row,
and 0.98x to 1.00x on the cold ones over four rounds against the commit before it.

## What is left

A cold run is 275 to 330 ms, of which the merge itself is at most 45. Loading what the command
line needs takes a fresh process about 278 ms (the median of twelve): `@tes3` 112 ms, `@openmw`
with the packages under it 153 ms, which are not this package's to shorten, and this package's
own two modules about 12 ms.

In a merge, two decodings are still made only to be looked at, and both are held where they are
by what they do when a record doesn't decode: they raise, and the run stops. Identifying a cell
decodes it (2.1 µs for a cell's id and its decoding, against 0.3 µs for an item's id), where its
`DATA` holds the flag and the grid; and a creature fewer than three files define is decoded
(4.4 µs) to see whether it is one of the 22 summons the patch names, where its id is already
known. Those are timed on 300 records of each kind shaped like the bench's and opened as the
merge opens them. Counted from them over the two-plugin order's 1,080 cells and 330 such
creatures, and not by any measurement of the change, reading neither would take about 2 ms off
the 11 of "nothing to merge" and about 3.4 ms off the 17 of "the patches alone"; it would also
let a malformed cell or creature through that stops a run today, which is why it wasn't done.

An object filter is asked through `@tes3cmd`'s `matchesRecord`, which reads the record's id each
time: three filters read it up to three times. Reading it once is `@tes3cmd`'s to offer.

## Which modules are native, and why

Jess compiles to machine code only what is marked (`--!native` on a module, `@native` on one
function), and every load pays for what is marked. A module carries `--!native` when a row below
spends its time there and the module is small (12 KB or less); a larger module carries `@native`
on the functions the row spends its time in, and nothing else.

Measured 2026-10-14 with `jess 0.1.0`, the verified release build of jess `07c38cb` on l3i
2.0.3, on the i7-10870H, the one-minute load 1.47 and 0.99 at the start of the two
sessions. In each session the bench ran alternately on this package and on a copy of it with
every module marked, three fresh runs of `bench/bench.jsl` each, every run's row the median of
its batches; a column is the median of the three, and a ratio is against the all-marked runs of
the same session. Which functions a row spends its time in comes from `jess run --profile` of
that row alone, unmarked. The load cost is a fresh `jess run --package <this package>
--package-path jpk` of a script that only requires `@tes3merge`, the two sides alternating, the
median of five each after one warm-up.

| Requiring `@tes3merge` | All marked | This state |
| --- | ---: | ---: |
| Unmarked | 0.123 s | 0.120 s |
| Final | 0.129 s | 0.127 s |

| Row | All marked (ms) | Unmarked / all marked | Final (ms) | Final / all marked |
| --- | ---: | ---: | ---: | ---: |
| merge five plugins, every type | 48.89 | **1.148×** | 51.34 | **1.050×** |
| merge five plugins, inventories as a union | 18.47 | **1.185×** | 19.04 | 1.031× |
| merge five plugins, leveled lists | 9.300 | **1.133×** | 9.533 | 1.025× |
| merge five plugins, spells, enchantments, and potions | 7.759 | **1.163×** | 7.733 | 0.997× |
| merge five plugins, items | 12.72 | **1.221×** | 12.64 | 0.994× |
| merge five plugins, cells | 12.45 | **1.055×** | 12.62 | 1.013× |
| merge five plugins, three object filters | 37.80 | **1.176×** | 39.06 | 1.033× |
| merge five plugins, no patches, no masters | 44.18 | **1.238×** | 44.03 | 0.997× |
| two plugins, nothing to merge | 11.87 | **1.141×** | 11.92 | 1.004× |
| two plugins, the patches alone | 18.67 | **1.137×** | 18.60 | 0.996× |
| merge three small plugins | 3.089 | **1.109×** | 3.005 | 0.973× |
| parse 8 argument lists | 0.01443 | **1.388×** | 0.01928 | **1.336×** |
| the command, five plugins | 50.83 | **1.222×** | 50.98 | 1.003× |

What carries the directive: `init`, whole. `cli` and `main` parse a command line once a run and
are never marked, so `parse 8 argument lists` is the one row more than 5% slower than all marked
(1.34x, of a 14 µs call).

Marking only the functions of `init` a merge's profile names cost 0.004 s less a load than all
marked, in a session of its own, and left 9 rows more than 5% slower, the merges among them at
1.07x to 1.16x: a merge reaches most of `init`, so the rest of it is no long tail to leave as
bytecode. Whole, `init` saves 0.002 s a load and every merge is within 5% of all marked; a run of
the tool is a merge, so that is the state kept.
