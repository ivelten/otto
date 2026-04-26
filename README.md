# otto

Personal automation bot written in Haskell. Researches content across the
web, extracts it as canonical Markdown, and calls LLMs to summarize and
draft posts. See [docs/overview.md](docs/overview.md) for the end-to-end
system overview and workflow diagrams; see [CLAUDE.md](CLAUDE.md) for
architecture principles and repository conventions; see
[CHANGELOG.md](CHANGELOG.md) for what has landed.

## Requirements

- [Docker](https://www.docker.com/products/docker-desktop)
- [VS Code](https://code.visualstudio.com/) with the
  [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)

The development environment ships in a devcontainer carrying GHC 9.10.3,
Cabal 3.12.1.0, HLS, Ormolu, Hoogle, and the rest of the Haskell
toolchain. The underlying image is
[ivelten/haskell-devcontainer](https://github.com/ivelten/haskell-devcontainer).

## Quickstart

Open the repository in VS Code and choose **Reopen in Container** (or
run `./open-devcontainer.sh` from the terminal). Once inside:

```bash
cabal update
cabal build all
cabal test
cabal run otto -- --help
```

### Subcommands

- `otto` — startup probe; logs a banner and exits.
- `otto ask [--provider NAME | -p NAME] PROMPT...` — sends PROMPT
  through the selected AI provider. Provider precedence: the
  `--provider` / `-p` flag wins, otherwise the `OTTO_PROVIDER` env
  variable, otherwise `anthropic` (default). Valid provider names:
  `anthropic`, `gemini`.
- `otto crawl URL` — fetches URL through the crawler (Jina Reader) and
  prints the extracted Markdown on stdout. Blocked targets (CAPTCHA /
  403 from the upstream site) go to stderr with a non-zero exit.
- `otto research URL` — fetches URL and persists it to the catalog as
  `<OTTO_CATALOG_DIR>/<slug>.md` with YAML frontmatter. Crawl errors
  are appended to `<OTTO_CATALOG_DIR>/.failures.jsonl` instead of
  discarded.
- `otto digest` — runs the research-ingestion pipeline. Loads
  `config/sources.yaml`, fetches every seed RSS / Atom feed, filters
  items to the last 7 days, crawls each surviving entry, and persists
  successes (or failure records) to the catalog. Designed to be
  invoked on a recurring systemd timer (weekly today).
- `otto --help` / `otto -h` — prints usage and the list of recognized
  environment variables.

A future `otto weekly` will read the catalog and synthesize the
weekly post draft; it has no implementation yet — synthesis lands
with the draft-generation work item.

Examples:

```bash
# Ask Claude
OTTO_ANTHROPIC_API_KEY=... cabal run -v0 otto -- ask "Explain monads briefly."

# Ask Gemini via the flag
OTTO_GEMINI_API_KEY=... cabal run -v0 otto -- ask --provider gemini "Explain monads briefly."

# Crawl a page to stdout (works anonymously on Jina's free tier)
cabal run -v0 otto -- crawl https://example.com > example.md

# Persist a page to the catalog (default: ./catalog/<slug>.md)
cabal run -v0 otto -- research https://example.com

# Run the digest pipeline against config/sources.yaml
cabal run -v0 otto -- digest
```

## Configuration

Otto reads configuration from environment variables. For local
development, put them in a `.envrc` at the repository root (loaded
automatically by `direnv`).

### AI providers

- `OTTO_PROVIDER` — selects the active AI provider. Accepts `anthropic`
  (default) or `gemini`. The `--provider` / `-p` flag on `otto ask`
  overrides this.
- `OTTO_ANTHROPIC_API_KEY` — required when the Anthropic provider is used.
- `OTTO_ANTHROPIC_BASE_URL` — optional; defaults to
  `https://api.anthropic.com`.
- `OTTO_ANTHROPIC_DEFAULT_MODEL` — optional; defaults to
  `claude-sonnet-4-6`.
- `OTTO_GEMINI_API_KEY` — required when the Gemini provider is used.
- `OTTO_GEMINI_BASE_URL` — optional; defaults to
  `https://generativelanguage.googleapis.com`.
- `OTTO_GEMINI_DEFAULT_MODEL` — optional; defaults to `gemini-2.5-pro`.

### Crawler (Jina Reader)

- `OTTO_JINA_API_KEY` — optional. When set, authenticates against Jina's
  paid tier for higher RPM. When unset, Otto uses the anonymous free
  tier.
- `OTTO_JINA_BASE_URL` — optional; defaults to `https://r.jina.ai`.
- `OTTO_JINA_ENGINE` — optional, `direct` (default) or `browser`.
  `browser` forces Jina's server-side headless renderer and consumes
  more credits on paid tiers.

### Catalog

- `OTTO_CATALOG_DIR` — optional; root directory for persisted research.
  Defaults to `./catalog/`. `otto research URL` writes one
  `<dir>/<slug>.md` per saved page and appends crawl failures to
  `<dir>/.failures.jsonl`.

### Sources

- `OTTO_SOURCES_PATH` — optional; path to the YAML registry of topics
  and seed feeds consumed by `otto digest`. Defaults to
  `./config/sources.yaml`. Each entry pairs a free-form topic label
  with a list of RSS / Atom URLs; per-feed items are filtered to the
  last 7 days before being crawled and persisted.

The repository ships
[`config/sources.yaml.example`](config/sources.yaml.example) as a
template; the real `config/sources.yaml` is gitignored so the owner's
actual subscriptions stay private. Before the first `otto digest`,
copy the example and fill in your own feeds:

```bash
cp config/sources.yaml.example config/sources.yaml
$EDITOR config/sources.yaml
```

### Logging

- `OTTO_DISCORD_WEBHOOK_URL` — optional. When set, `Warning+` log
  entries are also posted to this Discord webhook. When unset, stdout
  only.

### Testing

- `OTTO_JINA_INTEGRATION` — set to any non-empty value to enable the
  Jina live smoke test against `example.com` in `cabal test`. Off by
  default so the suite stays offline.

## Layout

```text
.
├── src/Otto/
│   ├── AI/                   # Provider abstraction + impls (Anthropic, Gemini, Mock)
│   ├── Catalog/              # Catalog abstraction + filesystem impl + pure renderer
│   ├── Crawler/              # Crawler abstraction + Jina Reader impl + Mock
│   ├── Feed/                 # Feed abstraction + HTTP + RSS/Atom parser
│   ├── Sources/              # Sources YAML registry: types, config, error, loader
│   ├── App.hs                # Application monad, Env, HasLog/HasAI/HasCrawler/HasCatalog/HasFeeds
│   ├── Error.hs              # OttoError union
│   ├── Logging.hs            # co-log bootstrap (stdout + optional Discord)
│   └── Pipeline.hs           # Research-ingestion orchestrator (`otto digest`)
├── app/Main.hs               # Executable entry point + CLI dispatch
├── config/
│   └── sources.yaml.example  # Template; copy to sources.yaml (gitignored) for `otto digest`
├── test/
│   ├── Main.hs               # tasty runner
│   ├── Otto/                 # Spec modules mirroring src/Otto
│   └── golden/               # Golden fixtures (Anthropic / Gemini / catalog / sources / feed)
├── .github/workflows/ci.yml  # ARM64 build + test on push / PR
├── otto.cabal                # Single-package manifest
├── cabal.project
├── CLAUDE.md                 # Architecture, tech stack, repository conventions
├── CHANGELOG.md              # What landed, Keep-a-Changelog style
└── README.md
```

## License

BSD-3-Clause. See [LICENSE](LICENSE).
