# Keynote Builder

A macOS application that rapidly assembles Apple Keynote presentations from modular slide blocks. Uses fuzzy matching to resolve user section names in config files to keynote files in the `blocks/` folder, and features a high-performance caching engine with smart staleness checking to only build what has changed.

![macOS](https://img.shields.io/badge/platform-macOS-lightgrey?logo=apple)
![Keynote](https://img.shields.io/badge/app-Keynote-blue)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Smart Caching & Staleness Checking:** Builds presentations using optimal chunk caching. Contiguous blocks of unchanged slides are rapidly copied from `outputs/.cache/`, minimizing AppleScript overhead.
- **Fuzzy Matching:** Automatically resolves typos in your configuration using Jaro–Winkler similarity (e.g., `wilvome` resolves to `Welcome.key`). The config file is then auto-corrected.
- **Dynamic Agenda:** Automatically compiles a numbered Agenda slide based on your deck's configuration, automatically filtering out structural slides like "Willkommen", "Schluss", or "Agenda".
- **Dynamic Pause Slides:** Intelligently parses natural language time formats (e.g., `Pause 15`, `Pause bis 14:30`) to create custom pause slides ("15 Minuten" or "bis 14:30").
- **Menti Integration:** Instantly generate Mentimeter slides by providing an 8-digit code (e.g., `Menti 1234 5678`).

## Project Structure

```
.
├── blocks/                        # Keynote slide modules
│   ├── slideBlockA.key
│   ├── slideBlockB.key
│   ├── Welcome.key
│   ├── Thank you.key
│   └── ...
├── decks/                         # Presentation configs
│   ├── CustomerMeeting.txt
│   ├── AllHands.txt
│   └── ...
├── outputs/                       # Compiled Keynote presentations
│   ├── CustomerMeeting.key
│   ├── AllHands.key
│   ├── .manifests/                # Hashes for staleness checking
│   └── .cache/                    # Caching directory

└── KeynoteBuilder.app             
```

| Folder | Purpose |
|---|---|
| `decks/` | Contains your configuration files. |
| `blocks/` | Folder of Keynote slide building blocks. |
| `outputs/` | Where the generated `.key` presentations are saved. |

## How to Use
1. **Write a config file** — create a `.txt` file in the `decks/` folder and list the sections you want, one per line.
2. **Run the app** — it finds all configs in `decks/` and checks them against existing manifests to determine which ones are yet to be built or need to be rebuilt.
3. **Select Decks** — Select which stale decks to build, check fuzzy matches for correctness.
4. **Done** — the merged `.key` files are placed in the `outputs/` folder.

## Configuration

Edit a `.txt` file in `decks/` to list the sections you want in your presentation, one per line:

```
Welcome
slideBlockA
Menti 1234 5678
slideBlockB
Pause 15 Minuten
slideBlockC
Thank you
```

- **Order matters** — sections appear in the presentation in the order listed.
- **Duplicates are fine** — list a section twice to include it twice.
- **Fuzzy matching** — `wilvome` will resolve to `Welcome.key` automatically in the `blocks/` folder using Jaro–Winkler similarity. The config file is dynamically updated with the corrected names after a successful run.
- **Dynamic Blocks** — Use `Menti <code>` or `Pause <duration/time>` to trigger dynamic slide generation.


## Requirements
- **macOS** (tested on macOS Tahoe 26.3)
- **Apple Keynote** (tested on Keynote 15.1)

## Build from source

```bash
git clone https://github.com/XaverBaumgartner/KeynoteBuilder.git
cd KeynoteBuilder

make build
```

The Makefile compiles the Swift files into a native macOS app bundle (`KeynoteBuilder.app`).

### Make Targets

| Target | Command | Description |
|---|---|---|
| `build` | `make build` | Compiles the Swift code and creates the `.app` bundle. |
| `run` | `make run` | Builds (if needed) and launches the application. |
| `clean` | `make clean` | Removes the compiled `.app` bundle. |

## License

This project is licensed under the [MIT License](LICENSE).
