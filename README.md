# PayloadGlass CLI (`sis`)

**A complete, local scanner for hostile documents, archives, files, and AI-bound content.**

PayloadGlass CLI — the `sis` command — identifies malicious constructs across
document, container, and executable formats, with native analysis per format
family and full traversal of arbitrarily nested content. It produces grouped
findings with evidence spans, an inspectable asset graph, and machine-readable
output — and it runs entirely on your machine. No account, no upload.

> `sis` is short for *Smiley Is Suspicious* — the analysis engine behind PayloadGlass.

**[payloadglass.com](https://payloadglass.com)** · **[Live in-browser demo](https://demo.payloadglass.com)** · **[Releases](https://github.com/payloadglass/sis-release/releases)**

A file submitted to `sis` is not assumed to be what its extension claims. Format
is determined from content. Containers are unpacked and their contents analysed
natively. A PDF embedding an OOXML file embedding an RTF document embedding an
OLE macro is handled as a single analysis graph, not as isolated format passes.

---

## Install

**macOS / Linux:**

```sh
curl -fsSL https://raw.githubusercontent.com/payloadglass/sis-release/main/scripts/install.sh | sh
```

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/payloadglass/sis-release/main/scripts/install.ps1 | iex
```

Custom install destination:

```sh
SIS_INSTALL_DIR=/opt/bin curl -fsSL https://raw.githubusercontent.com/payloadglass/sis-release/main/scripts/install.sh | sh
```

The installer downloads the matching archive for your platform and places the
`sis` binary in `~/.local/bin` (override with `SIS_INSTALL_DIR`). If that
directory is not on your `PATH`, the installer prints a note.

Prebuilt targets (also available directly from [Releases](https://github.com/payloadglass/sis-release/releases)):

| Platform | Target | Archive |
| --- | --- | --- |
| Linux x86_64 | `x86_64-unknown-linux-gnu` | `.tar.gz` |
| macOS (universal: Apple Silicon + Intel) | `universal-apple-darwin` | `.tar.gz` |
| Windows x86_64 | `x86_64-pc-windows-msvc` | `.zip` |

On macOS and Windows the binary is unsigned, so the first launch may show a
platform trust prompt (Gatekeeper / SmartScreen).

## Quick start

```sh
# Fast triage — any supported format (detected from content, not extension)
sis scan suspicious.pdf
sis scan lure.docx
sis scan dropper.lnk

# Deep analysis with machine-readable output
sis scan sample.pdf --deep --json

# Batch-scan a mixed-format directory, one JSON object per finding
sis scan --path attachments/ --deep --jsonl-findings

# SARIF for code-scanning pipelines
sis scan sample.pdf --deep --sarif-out report.sarif

# Classify whether a document is safe to feed to a model (exit code = label)
sis ingest-risk sample.pdf --json

# Sanitise active content and prove what changed
sis sanitize sample.pdf --out clean.pdf --report-json report.json

# Generate a markdown report
sis report sample.pdf --deep -o report.md

# Interactive forensic REPL — parse once, query many
sis repl sample.pdf
> findings.high
> actions.chains
> stream 8 0 --decode
```

## What it analyses

Format is identified from content, not extension. Nested content of any
supported type is detected and analysed inline — there is no distinction between
a top-level file and a nested payload.

| Format | Extensions | Detector namespace |
| --- | --- | --- |
| PDF | `.pdf` | `pdf:*` |
| HTML / HTA | `.html`, `.htm`, `.hta` | `html:*`, `hta:*` |
| RTF | `.rtf` | `rtf:*` |
| Office Open XML | `.docx`, `.xlsx`, `.pptx` | `ooxml:*` |
| OneNote | `.one` | `one:*` |
| MIME HTML | `.mht`, `.mhtml` | `mht:*` |
| OLE compound document | `.doc`, `.xls`, `.msg` | `ole:*` |
| Windows shortcut | `.lnk` | `lnk:*` |
| PE executable | `.exe`, `.dll`, `.scr` | `pe:*` |
| ELF executable | (no fixed extension) | `elf:*` |
| ISO / UDF image | `.iso` | `iso:*` |
| Archive / ZIP / 7z / RAR | `.zip`, `.7z`, `.rar` | `arc:*` |
| VBScript | `.vbs`, `.vbe` (embedded) | `vbs:*` |
| CSS | `.css` (embedded) | `css:*` |

Cross-format and structural findings (polyglots, magic-byte conflicts, format
masquerade) surface under `file:*`; Unicode and homoglyph indicators under
`unicode:*`.

`sis` runs 60+ detectors producing 200+ distinct finding kinds across format and
container structure, PDF internals, actions and triggers, JavaScript and
VBScript (static + instrumented dynamic sandbox), Office macros and OLE, forms
and XML, embedded/nested files, streams and filters, fonts, images, rich media,
URIs and phishing, the passive render pipeline, crypto and signatures, content
phishing, and AI-poisoning / prompt-injection channels. Findings are correlated
into trigger/action/payload chains and composite scores that span format
boundaries.

## The five risk lenses

Every file is read for five consumers, because risk depends on who ingests it:

- **Human-open** — risk if a person opens it in a normal application.
- **Renderer** — risk to an automated parser or rendering pipeline.
- **AI-ingestion** — hidden or retrieval-only channels carrying instructions to a model.
- **Agent-action** — content that an autonomous tool might act on (links, embedded commands).
- **CDR-residual** — what risk would remain after a safe derivative is produced.

## Commands

| Command | Purpose |
| --- | --- |
| `sis scan` | Primary detector pipeline for one file or a batch of paths |
| `sis query` | Forensic query interface over a parsed file |
| `sis repl` | Interactive query REPL — parse once, query many |
| `sis report` | Full report generation (markdown / JSON / YAML) |
| `sis explain` | Detailed explanation for a specific finding ID |
| `sis ingest-risk` | Classify a document's AI-ingestion risk; exit code encodes the label |
| `sis sanitize` | CDR strip-and-report for active-content removal |
| `sis sandbox` | Dynamic sandbox evaluation for extracted dynamic assets |
| `sis correlate` | Cross-input correlation of findings, chains, and IOCs |
| `sis generate` | YARA rule generation and test-fixture mutation |
| `sis diff` | Diff two scan outputs for finding- or verdict-level drift |
| `sis watch` | Watch a directory and scan files as they arrive |
| `sis doc` | Print bundled documentation |
| `sis config` | Configuration initialisation and validation |
| `sis update` | Self-update from GitHub releases |

Run `sis --help` for the full command surface.

## Configuration

Default config path (`~/.config/sis/config.toml` on Linux/macOS,
`%APPDATA%\sis\config.toml` on Windows):

```sh
sis config init
sis config verify
```

```toml
[logging]
level = "warn"

[scan]
deep = true
parallel = true
```

## Documentation

All reference material ships inside the binary:

```sh
sis doc index          # list available topics
sis doc taxonomy       # finding taxonomy and data model
sis doc formats        # supported formats and nesting rules
sis doc architecture   # architecture and command-surface overview
```

## Updating

```sh
sis update                     # latest release
sis update --include-prerelease
```

---

## About PayloadGlass

PayloadGlass is a local-first trust layer for hostile documents, archives,
files, and AI-bound content. The CLI is the complete local scanner; see
**[payloadglass.com](https://payloadglass.com)** for the whole picture and the
**[live in-browser demo](https://demo.payloadglass.com)**, where you can drop a
hostile file and watch it get analysed with zero bytes uploaded.

- Website — https://payloadglass.com
- Live demo — https://demo.payloadglass.com
- Releases — https://github.com/payloadglass/sis-release/releases
