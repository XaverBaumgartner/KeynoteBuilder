# Keynote Builder

A macOS application that assembles Apple Keynote presentations from modular slide blocks. Uses fuzzy matching to resolve user section names in config files to keynote files in the `blocks/` folder, and features smart staleness checking to only build what has changed.

![macOS](https://img.shields.io/badge/platform-macOS-lightgrey?logo=apple)
![Keynote](https://img.shields.io/badge/app-Keynote-blue)
![License](https://img.shields.io/badge/license-MIT-green)

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
│   └── .manifests/                # Hashes for staleness checking
└── KeynoteBuilder.app             
```

| Folder | Purpose |
|---|---|
| `decks/` | Contains your configuration files. |
| `blocks/` | Folder of Keynote slide building blocks. |
| `outputs/` | Where the generated `.key` presentations are saved. |

## How to Use
1. **Write a config file** — create a `.txt` file in the `decks/` folder and list the sections you want, one per line.
2. **Run the app** — it finds all configs in `decks/` and checks them against existing files in `outputs/` to determine which ones are yet to be built or need to be rebuilt (modified config or modified blocks).
3. **Select Decks** — Select which stale decks to build, check fuzzy matches for correctness.
4. **Done** — the merged `.key` files are placed in the `outputs/` folder.

## Configuration

Edit a `.txt` file in `decks/` to list the sections you want in your presentation, one per line:

```
Welcome
slideBlockA
slideBlockB
slideBlockC
Thank you
```

- **Order matters** — sections appear in the presentation in the order listed.
- **Duplicates are fine** — list a section twice to include it twice.
- **Fuzzy matching** — `wilvome` will resolve to `Welcome.key` automatically in the `blocks/` folder using Jaro–Winkler similarity. The config file is dynamically updated with the corrected names after a successful run.

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
