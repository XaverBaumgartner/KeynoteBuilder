# Keynote Builder

A macOS applet that assembles Apple Keynote presentations from modular slide blocks. Uses fuzzy matching to resolve user section names in a config file to keynote files in the `blocks/` folder.

![macOS](https://img.shields.io/badge/platform-macOS-lightgrey?logo=apple)
![Keynote](https://img.shields.io/badge/app-Keynote-blue)
![License](https://img.shields.io/badge/license-MIT-green)

## Project Structure

```
.
├── blocks/                        # Keynote slide modules (.key files)
│   ├── slideBlockA.key
│   ├── slideBlockB.key
│   ├── Welcome.key
│   ├── Thank you.key
│   ├── slideBlockC.key
│   └── ...
├── config.txt                     # User-generated list of presentation sections
└── KeynoteBuilder.app             
```

| File | Purpose |
|---|---|
| `config.txt` | One section name per line. Names don't need to be exact — fuzzy matching handles typos and abbreviations. |
| `blocks/` | Folder of Keynote slide building blocks. |

## How to Use
1. **Write a config file** — list the sections you want, one per line.
2. **Run the app** — it fuzzy-matches each line to a `.key` file in the `blocks/` folder using Jaro–Winkler similarity.
3. **Review & confirm** — Upon running the app, a dialog shows the resolved file list and any name corrections. Confirm to proceed, cancel to abort and edit the config file.
4. **Done** — a merged `Presentation.key` is created.

## Configuration

Edit `config.txt` to list the sections you want in your presentation, one per line:

```
Welcome
slideBlockA
slideBlockB
slideBlockC
Thank you
```

- **Order matters** — sections appear in the presentation in the order listed.
- **Duplicates are fine** — list a section twice to include it twice.
- **Fuzzy matching** — `wilvome` will resolve to `Welcome.key` automatically. The config file is updated with the corrected names after a successful run.

## Requirements
- **macOS** (tested on macOS Tahoe 26.3)
- **Apple Keynote** (tested on Keynote 15.1)
- **Perl 5** (ships with macOS)

## Build from source

```bash
git clone https://github.com/XaverBaumgartner/KeynoteBuilder.git
cd KeynoteBuilder

make build
```

The Makefile compiles the AppleScript into an app bundle and copies `fuzzy_match.pl` into its `Contents/Resources/` directory.

### Make Targets

| Target | Command | Description |
|---|---|---|
| `build` | `make build` | Compiles the AppleScript and bundles `fuzzy_match.pl` into the `.app` |
| `run` | `make run` | Builds (if needed) and launches the app |
| `clean` | `make clean` | Removes the compiled `.app` bundle |

## License

This project is licensed under the [MIT License](LICENSE).
