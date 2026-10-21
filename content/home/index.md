+++
title = "tes3merge"
description = "Merges the records of a Morrowind load order into one patch plugin, a port of NullCascade's TES3Merge, as a Jess package and command in Luau."
date = 2026-10-21

[taxonomies]
tags = ["Jess", "Luau", "OpenMW"]

[extra]
sections = ["overview", "releases", "credits"]
+++

Merges the records of a Morrowind load order into one patch plugin, a port of NullCascade's TES3Merge, as a Jess package and command in Luau.

<!-- more -->

A [Jess](https://github.com/DreamWeave-MP/jess) package, `org.dreamweave.tes3merge`. Add it to a `jess.toml` and
`jess workspace sync` pins it from this site:

```toml
[dependencies]
"org.dreamweave.tes3merge" = "0.1"
```

Every release below is the package's own archive, with its content digest beside the archive's
SHA-256; `jess.lock` pins the first and checks both.
