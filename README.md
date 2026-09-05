# pak

A read-only, interactive TUI explorer for the Arch Linux package database. Written in Zig using [vaxis](https://github.com/rockorager/libvaxis).

`pak` answers the questions pacman makes awkward: *what does this package actually pull in? what breaks if I remove it? which packages are orphaned on my system?* It reads directly from `/var/lib/pacman/local/` — no subprocess calls to pacman, no network, nothing written to your system.

> **Status:** Active development. The core parse pipeline, dependency graph, package list pane, info panel, and dep tree are working. Remove simulation and file ownership features are planned.

---

## The problem

Answering a real question about your system state currently looks like this:

```bash
pacman -Qi cmake        # info, one package at a time
pactree cmake           # static dep tree, no interaction
pacman -Qdt             # orphans, global list, no context
pacman -Rns --print cmake  # simulate removal, no context
```

`pak` collapses all of this into one interactive session. Navigate your package list, inspect deps and reverse-deps, and identify orphans — without ever touching your system.

---

## What's implemented

- Full parse of the pacman local database (`desc` files only, ~1,200–1,500 packages)
- Five-pass pipeline: directory scan → desc parse → sort by name → index construction → dep resolution
- `provides` resolution with multi-provider support (e.g. `sh` → `bash`)
- `required_by` and `opt_req_by` reverse-dependency graphs
- Orphan detection (dep packages with no `required_by` and no `opt_req_by`)
- Three-pane TUI: package list | info panel | dep tree
- Package list with substring filter, orphan filter (`[!]`), dep filter (`[S]`), sort by name or size
- Info panel: name, version, description, size, deps, optional deps, required-by, opt-required-by
- Collapsible dependency tree with cycle detection, shared-package marking, and optional-dep distinction
- Live terminal resize via `SIGWINCH`

## What's planned

- Remove simulation overlay (exclusive transitive size, packages that would be reclaimed)
- Per-package file list with filter (`files` parse)
- Global file owner search (`/usr/lib/libSDL2.so → sdl2`)
- Clipboard yank for simulated `pacman -Rns` command

---

## What pak is not

- **Not a pacman wrapper.** It never calls pacman, installs, removes, or upgrades anything.
- **Not network-aware.** Fully offline. No sync, no update checks.
- **Not an AUR helper.**
- **Not a replacement for pacman.** It is a lens on the state pacman has already created.

---

## Installation

### Pre-built binary (recommended)

Every [release](https://github.com/LuisPCNeri/pak/releases) ships a statically compiled binary. No dependencies, no Zig toolchain required — just download and run:

```bash
chmod +x pak
./pak
```

### Build from source

Requires Zig nightly and Arch Linux.

```bash
git clone https://github.com/LuisPCNeri/pak
cd pak
zig build -Doptimize=ReleaseFast
./zig-out/bin/pak
```

---

## Layout

```
pak | 1247 packages | Total Size: 8.43 GiB
──────────────┬───────────────────────────┬──────────────────────────────────
 base    [E]  │ Name: gcc                 │ ▾ gcc
 binutils[S]  │ Version: 14.2.1-2         │   ├─ ▸ binutils  [shared]
 cmake   [!]  │ Description: The GNU      │   ├─ ▾ glibc
 gcc     [S]  │   Compiler Collection     │   │    ├─ ▸ linux-api-headers
 glibc   [S]  │ Size: 89.4 KiB            │   │    └─ ▸ tzdata  [shared]
              │                           │   ├─ ▸ libmpc     [shared]
              │ Dependencies: binutils    │   └─ ▸ libisl
              │   glibc libmpc zlib       │        └─ ▸ gmp
              │   libisl                  │
              │                           │
              │ Required By: gcc-libs     │
──────────────┴───────────────────────────┴──────────────────────────────────
[q]uit  [↑/↓] Scroll  [←/→] Switch Pane  [f]ind  [n]ame sort  [s]ize sort  [SPACE] Open/close Graph Node
```

Pane proportions: 25% (package list) | 35% (info) | 40% (dep tree). The info panel always tracks the selected package and is not directly focusable — focus switches between the list and the dep tree.

---

## Keybindings

| Key | Action |
|---|---|
| `↑` / `↓` | Move cursor in the active pane |
| `Page Up` / `Page Down` | Move cursor by 10 |
| `←` / `→` or `j` / `k` | Switch active pane |
| `f` | Enter search/filter mode |
| `Esc` | Exit search mode and clear filter |
| `Enter` | Confirm search (stay filtered, return to normal mode) |
| `Backspace` | Delete last character in filter |
| `Space` or `Enter` | Expand / collapse node in dep tree |
| `s` | Sort package list by size (largest first) |
| `n` | Sort package list by name |
| `q` | Quit |

---

## Package list badges

| Badge | Meaning |
|---|---|
| `[E]` | Explicitly installed |
| `[S]` | Installed as a dependency, still required |
| `[!]` | Orphan — installed as a dependency, nothing requires it |

---

## Filter syntax

Type after pressing `f`. The filter is a **substring match** on package names. Two special filters also work:

| Term | Effect |
|---|---|
| `[!]` | Show only orphaned packages |
| `[S]` | Show only dependency-installed packages that are still required |

Press `Esc` to clear the filter and return to the full list.

---

## Dep tree

The dep tree on the right tracks the selected package in real time. It shows both required and optional dependencies. Optional deps are rendered **dimmed**.

| Indicator | Meaning |
|---|---|
| `▾` | Node is expanded |
| `▸` | Node is collapsed (has children) |
| `[shared]` | More than one package depends on this |
| `(↺)` | Would create a cycle — not expanded further |

Press `Space` or `Enter` to expand or collapse the node under the tree cursor.

---

## Project structure

```
pak/
├── src/
│   ├── main.zig                ← entry point, event loop, input handling
│   ├── db/
│   │   ├── database.zig        ← Package and Database structs
│   │   └── parse.zig           ← five-pass parse pipeline
│   ├── tui/
│   │   └── tui.zig             ← layout, header, footer, render orchestration
│   ├── panes/
│   │   ├── package_list.zig    ← left pane
│   │   ├── info.zig            ← middle pane
│   │   └── dep_tree.zig        ← right pane: collapsible dep tree
│   └── util/
│       └── fuzzy.zig           ← substring filter, special filters, sort
├── build.zig
└── build.zig.zon               ← vaxis dependency
```

---

## License

MIT
