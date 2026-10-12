# tes3merge benchmarks

`bench/bench.luau` times the tool the way it is reached: `@tes3merge` called with an `@openmw`
Context over load orders the bench builds with `@tes3`, the argument lists `@tes3merge/cli`
reads, and the command line, warm and from a cold start. The load order is a master of 6,200
records of the types the tool merges (items, spells with their effects, NPCs and creatures with
their packages and inventories, leveled lists, interior and exterior cells with their references,
settings) and four plugins that define every fourth, sixth, tenth, and fifteenth of them again,
changed, plus records of their own: about 12,300 records in five files, 823 of the master's
defined three times or more. A second order is the master and one plugin, where nothing has three definitions, which
is what most of a real load order looks like; a third is a master of 248 records and two plugins.

A warm workload is warmed up, sized to a batch of about a tenth of a second, and reported as the
median of seven batches with a full collection between them. A `cold:` workload is the median of
seven fresh processes running `bench/cold.luau`, the command line run once and timed inside the
script from its first `require`. Every merge's report and a digest of the records it wrote are
compared with what the bench has pinned, before the first batch and after the last, so a path
that stops doing the work stops the run instead of posting a time.

```sh
jess run --capability filesystem.read --capability filesystem.write \
  --capability process.spawn --package jpk/tes3merge --package-path jpk \
  jpk/tes3merge/bench/bench.luau <scratch> [filter] [jess binary] [package path]
```

Without the binary (and `process.spawn`) the cold workloads are skipped. The tool reports through
`print`, so each merge prints its own line among the bench's: the bench's are the ones that hold
a tab.

## The move onto l3i 2.0, base against head

- Machine: Intel Core i7-10870H @ 2.20 GHz, 16 threads, shared with other work while this ran
  (load average 1.7 to 2.2 over the run).
- Date: 2026-10-12.
- Binary: the verified release build of Jess 0.1.0 on l3i 2.0.2 (Luau 0.742), the same one for
  both sides, as are the packages this one depends on.
- Base: `f14c91d`, the package before the move, with this bench. Head: `e6abdad`; what follows
  it is this page and a helper's new name.
- Protocol: the whole bench against an export of base and against head, four times each,
  alternating and swapping which goes first, back to back under one lock; each cell is the
  median of its four runs. A difference under 5 percent is called no change.

| Workload | Base | Head | Base / head |
|---|---:|---:|---:|
| merge five plugins, every type | 52.60 ms | 42.20 ms | 1.25x |
| merge five plugins, inventories as a union | 16.63 ms | 15.48 ms | 1.07x |
| merge five plugins, leveled lists | 8.85 ms | 8.50 ms | no change |
| merge five plugins, spells, enchantments, and potions | 7.76 ms | 7.09 ms | 1.10x |
| merge five plugins, items | 13.43 ms | 11.61 ms | 1.16x |
| merge five plugins, cells | 14.17 ms | 11.22 ms | 1.26x |
| merge five plugins, three object filters | 53.39 ms | 45.05 ms | 1.19x |
| merge five plugins, no patches, no masters | 47.09 ms | 39.31 ms | 1.20x |
| two plugins, nothing to merge | 15.02 ms | 11.10 ms | 1.35x |
| two plugins, the patches alone | 22.46 ms | 16.11 ms | 1.39x |
| merge three small plugins | 3.18 ms | 2.96 ms | 1.08x ¹ |
| parse 8 argument lists | 13.40 µs | 14.05 µs | no change ² |
| the command, five plugins | 52.41 ms | 43.23 ms | 1.21x |
| cold: --version | 307.83 ms | 273.13 ms | 1.13x |
| cold: the command, three small plugins | 322.12 ms | 285.03 ms | 1.13x |
| cold: the command, five plugins | 373.39 ms | 327.10 ms | 1.14x |

¹ 1.04x in a second run of the same protocol, so not shown to have moved. That second run, with
a third side in it, read 1.24x, 1.09x, 1.05x, 1.10x, 1.16x, 1.23x, 1.13x, 1.18x, 1.31x, 1.34x,
1.04x, 1.02x, 1.15x, 1.10x, 1.12x, and 1.14x down the table.

² `@tes3merge/cli` is the same code on both sides: this row's 0.95x here and 1.02x in the second
run is what the machine's noise looks like.

## What moved, and why

Nothing in this package is a loop over a buffer, so nothing here went to the data plane. What it
does with its time is ask `@tes3` for things (open, a record's tag and id, a decoded record, an
encoded one), and group and compare the tables it gets back. The gains are from asking less and
allocating less, each measured on its own against the commit before it:

- **Grouping** (`f3b5f4f`; nothing to merge 1.34x, the patches alone 1.27x, every type 1.10x).
  Every record of a merged type went under a key made by lowering its id and joining it to its
  tag, in a table of its own holding the plugin, the file's name, and the index, in a list made
  for its key. An id is now a number from an `@dream/intern` pool of its type, which compares
  ASCII letters without their case and counts up in the order ids are first seen, the order the
  output is written in; a record is one number, its plugin's place and its index; and an id one
  file defines holds that number and no list. A load order's records are mostly defined once.
- **The fog patch** (`b44eb2c`; cells 1.12x, the patches alone 1.11x). A cell is decoded to tell
  an interior from an exterior, which is what identifies it. Every cell fewer than three files
  define was then decoded a second time to see whether the patch would change it; that is read
  from the first decoding now.
- **Object filters** (`5beede2`; three object filters 1.19x). Each filter listed every record it
  matched in every plugin, as tables, before any record was looked at. A record of a merged type
  now asks the filters itself, last to first, and stops at the one that matches.
- **Merging fields** (`932c105`; 1.05x to 1.11x on the rows that merge the most, at the edge of
  what this machine resolves). A merge gathered the field names of two definitions into a table
  to walk it. It walks the later definition's fields, then the first's that the later lacks.
- **A cold start** (`9d6a932`; 1.10x to 1.16x on the three cold rows). `@tes3cmd`, which only an
  object filter uses, took about 37 ms of the 310 to 330 a run spent before its merge began. It
  is loaded when a filter asks for it.
- **Flags** (`e6abdad`; cells 1.05x over eight rounds, nothing elsewhere). Whether a flags text
  holds a name is first asked of the text whole, before it is split into its names.

The dialect itself (`bc1d5ae`: three comprehensions, a sink, a reducer, three record patterns in
generators) measured as no change, warm and cold, as a comprehension should: 0.98x to 1.04x on
every row.

## What is left

A cold run is 270 to 330 ms, of which the merge itself is at most 45: the rest is compiling
`@tes3` (about 115 ms) and `@openmw` with the packages under it (about 160 ms), which are not
this package's to shorten.

In a merge, two decodings are still made only to be looked at, and both are held where they are
by what they do when a record doesn't decode: they raise, and the run stops. Identifying a cell
decodes it (a cell takes 3 µs to group, any other record 0.7 µs), where its `DATA` holds the
flag and the grid; and a creature fewer than three files define is decoded to see whether it is
one of the 22 summons the patch names, where its id is already known. By the time each takes in
a profile of the two-plugin rows, and not by any measurement of the change, reading neither
would take about a fifth off "nothing to merge" and a third off "the patches alone"; it would
also let a malformed cell or creature through that stops a run today, which is why it wasn't
done.

An object filter is asked through `@tes3cmd`'s `matchesRecord`, which reads the record's id each
time: three filters read it up to three times. Reading it once is `@tes3cmd`'s to offer.
