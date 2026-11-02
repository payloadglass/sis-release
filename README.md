# PayloadGlass CLI (`sis`)

**A local scanner for hostile documents, archives, files, and AI-bound content.**

PayloadGlass CLI — the `sis` command — identifies malicious constructs across
document, container, and executable formats, with native analysis per format
family and budget-bounded recursive traversal of nested content. It produces grouped
findings with evidence spans, an inspectable asset graph, and machine-readable
output — and it runs entirely on your machine. No account, no upload.

> `sis` is short for *Smiley Is Suspicious* — the analysis engine behind PayloadGlass.

**[payloadglass.com](https://payloadglass.com)** · **[Investigation workbench](https://workbench.payloadglass.com)** · **[Releases](https://github.com/payloadglass/sis-release/releases)**

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

Both installers verify the downloaded archive against the release's `SHA256SUMS` before extracting it, and install nothing on a mismatch.

Releases that ship `sis-cdr-worker` get it installed in the same directory as
`sis`, because `sis sanitize release` looks for the worker next to the `sis`
executable. Older releases (such as v0.7.0-beta.1) do not include it; the
installer prints a note and `sis sanitize release` is unavailable there.

Prebuilt targets (also available directly from [Releases](https://github.com/payloadglass/sis-release/releases)):

| Platform | Target | Archive |
| --- | --- | --- |
| Linux x86_64 | `x86_64-unknown-linux-gnu` | `.tar.gz` |
| Linux arm64 | `aarch64-unknown-linux-gnu` | `.tar.gz` |
| macOS (universal: Apple Silicon + Intel) | `universal-apple-darwin` | `.tar.gz` |
| Windows x86_64 | `x86_64-pc-windows-msvc` | `.zip` |

On macOS and Windows the binary is unsigned, so the first launch may show a
platform trust prompt (Gatekeeper / SmartScreen).

### Beta releases

v0.7.0-beta.1 is a public **prerelease**. Beta means usable but still moving:
output, verdicts and command behaviour can change between betas. It is opt-in;
a normal install or `sis update` keeps giving the latest stable release.

Get the beta:

```sh
sis update --include-prerelease
```

or, for a fresh install:

```sh
curl -fsSL https://raw.githubusercontent.com/payloadglass/sis-release/main/scripts/install.sh | SIS_INSTALL_PRERELEASE=1 sh
```

```powershell
$env:SIS_INSTALL_PRERELEASE = "1"; irm https://raw.githubusercontent.com/payloadglass/sis-release/main/scripts/install.ps1 | iex
```

Go back to stable by re-running the normal installer (without
`SIS_INSTALL_PRERELEASE`), which installs the latest stable release over the
beta. In PowerShell, clear the variable first with
`Remove-Item Env:SIS_INSTALL_PRERELEASE`.

Report problems in this repository's
[Issues](https://github.com/payloadglass/sis-release/issues/new/choose) using
the templates. Never attach a sample or paste its contents; give its sha256.

### Container image

A multi-architecture image (`linux/amd64` and `linux/arm64`) is published to
GitHub Container Registry, for hosts where you would rather install nothing:

```sh
docker run --rm --network none --read-only \
  -v "$PWD:/work:ro" ghcr.io/payloadglass/sis:v0.6.9 scan /work
```

`sis` is the entrypoint, so pass subcommands directly. The container runs as
uid `65532` with `/work` as its working directory, needs no writable root
filesystem, and needs no network to analyse local content — the flags above are
the recommended posture, not a workaround.

**There is no `latest` tag.** Tags are release tags, so pin the version you
intend to run. For a byte-exact pin, use the image digest:

```sh
docker pull ghcr.io/payloadglass/sis@sha256:<digest>
```

Find the digest of a tag with `docker buildx imagetools inspect
ghcr.io/payloadglass/sis:v0.6.9` (the `Digest:` line), or on the package page
linked below.

Available tags are listed under
[Packages](https://github.com/orgs/payloadglass/packages?repo_name=sis-release).

<details>
<summary>What the image's attestation does and does not cover</summary>

The image is **assembled**, not rebuilt: it repackages the Linux archives this
release already publishes, after verifying them against `SHA256SUMS`. The
runtime base is pinned by digest, and the assembly step is Sigstore-signed and
recorded in the public transparency log.

The attestation therefore names the assembly workflow as the builder and
attests *"this image was assembled from these exact published bytes."* It is
**not** a cryptographic tie to a source commit — the same trade-off the release
archives document. Verify it with:

```sh
gh attestation verify --owner payloadglass \
  oci://ghcr.io/payloadglass/sis:v0.6.9
```

</details>

## Quick start

```sh
# Fast triage — any supported format (detected from content, not extension)
sis scan suspicious.pdf
sis scan lure.docx
sis scan dropper.lnk

# Deep analysis with machine-readable output
sis scan sample.pdf --deep --format json

# Batch-scan a mixed-format directory, one JSON object per finding
sis scan attachments/ --deep --format jsonl-findings

# SARIF for code-scanning pipelines
sis scan sample.pdf --deep --format json --emit sarif=report.sarif

# Report observed AI-ingestion risk of a document (exit code = label)
sis assess sample.pdf --for ai-ingest --json

# Sanitise active content (preview; selected formats only)
sis sanitize apply sample.pdf --out clean.pdf --report-json report.json --verify-rescan

# Generate a markdown report
sis report sample.pdf --deep -o report.md

# Interactive forensic REPL — parse once, query many
sis query repl sample.pdf
> findings.high
> actions.chains
> stream 8 0 --decode
```

## What it analyses

Format is identified from content, not extension. Nested content of any
supported type is detected and analysed inline, under explicit depth and size
budgets; omissions are recorded in `analysis_coverage` where the format reports
them. The same detectors apply to a nested payload as to a top-level file.

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
| Mach-O executable | (no fixed extension) | `pe:*` / `elf:*` family |
| ISO / UDF image | `.iso` | `iso:*` |
| Archive / ZIP / 7z / RAR / TAR | `.zip`, `.7z`, `.rar`, `.tar` | `arc:*`, `zip:*`, `7z:*`, `rar:*` |
| JavaScript | `.js` (standalone or embedded) | `js:*` |
| VBA / VBScript | `.vbs`, `.vbe`, macro streams | `vba:*`, `vbs:*` |
| PowerShell | `.ps1` | `ps1:*` |
| Shell script | `.sh` | `sh:*` |
| Python | `.py` | `py:*` |
| Windows Script File | `.wsf` | `wsf:*` |
| XML / SVG / CSS | `.xml`, `.svg`, `.css` | `xml:*`, `svg:*`, `css:*` |
| Images | JPEG, PNG, GIF, BMP, TIFF, WebP, JP2, JBIG2 | `image:*` |
| Fonts | embedded / standalone | `font:*` |
| Flash / media | `.swf`, media streams | `swf:*` |

Cross-format and structural findings (polyglots, magic-byte conflicts, format
masquerade) surface under `file:*`; Unicode and homoglyph indicators under
`unicode:*`.

60+ detectors across ~25 analysis families declare **800+ distinct finding kinds**
across format and container structure, PDF internals, actions and triggers, scripting
(JavaScript, VBA/VBScript, PowerShell, shell, Python — static plus an
instrumented dynamic sandbox), Office macros and OLE, forms and XML,
embedded/nested files, streams and filters, fonts, images, QR and visual lures,
rich media, URIs and phishing, the passive render pipeline, crypto and
signatures, AI-poisoning / prompt-injection channels, and — verdict-inert and
evidence-safe — **secrets and PII**. Findings are correlated into
trigger/action/payload chains and composite scores that span format boundaries.

## How risk is read

A file is not one number, and risk depends on who ingests the content.

**Threat assessment.** The security verdict is the worst of three readings:
**hostility** (executes, exploits, fetches, evades), **deception** (manipulates a
human) and **AI-ingestion** (corrupts a model/RAG/agent workflow). Findings carry
evidence spans, and the report records what the analysis could not inspect.

**Decision context.** Other evidence informs a decision without changing the
verdict: sensitive data (secrets, credentials, PII — detected locally,
evidence-safe and verdict-inert) and provenance or custody. Provenance reads
`Unknown` on a bare scan, because the file alone does not say where it came from.

This is not a fixed list of universal risk axes, and consumer- and
destination-specific decisions (open, index, forward, hand to an agent) are
planned, not shipped. Today `sis assess` reports AI-ingestion risk for one
consumer.

## Commands

| Command | Purpose |
| --- | --- |
| `sis scan` | Analyse a file or directory; use `--stream` for chunked analysis |
| `sis query` | Live or saved-report projections; PDF session with `sis query repl` |
| `sis explain` | Explain verdicts, findings, claims, integrity, routing, members and effects |
| `sis report` | Reanalyse for an operator-facing report |
| `sis assess` | Bounded AI-ingestion risk and consumer-policy guidance (`--for ai-ingest`) |
| `sis extract` | Channel-aware text and disclosed removal derivatives |
| `sis sanitize` | Preview: `plan` and `apply` for selected formats; isolated `release` needs a worker the v0.7.0-beta.1 build does not ship; `verify` checks evidence. See the known limitations |
| `sis sandbox` | Explicit dynamic evaluation of supported assets |
| `sis corpus` | Structure clustering and saved-report correlation/comparison |
| `sis workflow` | Typed workflow composition and bundle validation |
| `sis docs` | Bundled guidance; start with `sis docs index` or `sis docs scan` |
| `sis doctor` | Build, provider and configuration diagnostics |
| `sis completion` | Completion for the installed command surface |
| `sis config` | Configuration initialisation and validation |
| `sis update` | Self-update from published releases (`--include-prerelease` for betas) |
| `sis pdf-object` | Preview, v0.7.0 betas only: raw or decoded access to one PDF object by number |
| `sis pdf-export` | Preview, v0.7.0 betas only: whole-document PDF shapes (structure, IR, content graphs) |

<!-- revisit at beta.2 tag: regenerate this table from sis README.md at the tag; HTML/SVG sanitisation status depends on #2066 -->

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
sis docs index          # list available topics
sis docs taxonomy       # finding taxonomy and data model
sis docs formats        # supported formats and nesting rules
sis docs architecture   # architecture and command-surface overview
```

## Updating

```sh
sis update                     # latest release
sis update --include-prerelease
```

---

## About PayloadGlass

PayloadGlass is a local-first trust layer for hostile documents, archives,
files, and AI-bound content. The CLI is the local scanner; see
**[payloadglass.com](https://payloadglass.com)** for the whole picture and the
**[investigation workbench](https://workbench.payloadglass.com)**, where you can drop a
hostile file and watch it get analysed with zero bytes uploaded.

- Website — https://payloadglass.com
- Investigation workbench — https://workbench.payloadglass.com
- Releases — https://github.com/payloadglass/sis-release/releases
