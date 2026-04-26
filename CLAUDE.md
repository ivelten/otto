# CLAUDE.md

Project guidance for Claude Code when working in this repository.

## Project: Otto

Otto is a personal automation bot written in Haskell. The name is short, direct, contains "auto" (automation), and evokes orderliness — fitting for a bot that executes tasks with near-obsessive precision. The mental model is an "autistic", hyper-focused assistant.

Otto's long-term role is to assist the owner with personal automations. The first task is managing a personal blog and website.

The collaboration model is **cyborg**: Otto researches content and drafts posts; the owner reviews, revises, and publishes.

## Deployment

- **Host:** a single long-running Linux VM (`aarch64-linux`). Hosting-provider
  details are intentionally kept out of the repository.
- **Database:** PostgreSQL (primary store for research data, drafts,
  configuration).

## Initial scope: content research

The first feature is a **weekly** content-research pipeline:

- Run real web searches against the owner's topics of interest, once a week.
  The cadence is intentionally weekly, not daily — the goal is one
  well-edited post per week, and a tighter loop just inflates the catalog
  with noise. The ingestion command is `otto digest` (it pulls feeds, crawls,
  and persists). The production host invokes it from a systemd timer. A
  future `otto weekly` will synthesize the post draft from the catalog
  alone; the split keeps writers and readers of the catalog as separate
  commands.
- Prefer recent content — items older than the 7-day window are dropped at
  the pipeline boundary; stale links never reach the crawler.
- Crawl each page, extract its text, and store a readable Markdown rendition.
  Never rely on the source link surviving; the catalog is the source of truth.
- Handle multiple source types: HTML, `.docx`, YouTube videos, GitHub
  repositories, and more. Each source type has its own module responsible
  for turning its input into canonical Markdown. Binary or non-textual
  sources are transcribed to text using an AI provider.

The resulting research catalog is the input for later features (draft generation, post review, publishing pipeline).

## Architecture principles

- **Provider-agnostic AI layer.** Otto must be able to use multiple AI providers (Gemini, Claude, OpenAI, Deepseek, …). Build an abstraction that normalizes responses into a common internal format. The system picks the best model/provider per task.
- **Vendor-agnostic crawler layer.** Same idea applied to URL fetching: a single abstraction normalizes different fetch strategies (Jina Reader today, local Playwright tomorrow, …) into a common `CrawlResult`. The first implementation is Jina Reader; others slot in behind the same handle without touching callers.
- **Handle pattern for swappable capabilities.** The AI (`Provider`), the crawler (`Crawler`), the catalog (`Catalog`), and the feed loader (`Feeds`) are all record-of-functions values held in `Env` through small `Has*` classes (`HasAI`, `HasCrawler`, `HasCatalog`, `HasFeeds`, mirroring `HasLog`). New capabilities (database pool, job queue, …) follow the same shape so they stay trivially swappable in tests and composable at bootstrap.
- **Per-source-type modules.** Research extraction is factored into modules by source type (HTML, docx, YouTube, GitHub, …), each responsible for turning its input into canonical Markdown. This is a different axis from the crawler layer: a source-type module decides *how to interpret* bytes; the crawler decides *how to obtain* them.
- **Haskell.** All application code is Haskell. The toolchain is provided by the devcontainer (GHC 9.10.3, Cabal 3.12.1.0, Stack, HLS, Ormolu, Hoogle, cabal-gild). See [README.md](README.md) for the full list.

## Tech stack

- **Packaging.** Single Cabal package (`otto.cabal`) at the repository root, exposing a library + executable. Only split into multiple packages when a concrete need forces it (e.g. a shared component consumed by an independent binary).
- **License.** `BSD-3-Clause` — the Haskell community default; keeps the door open for open-sourcing pieces later without re-licensing.
- **Application monad.** `newtype App a = App { runApp :: ReaderT Env IO a }` — the "ReaderT pattern". The outer stack is intentionally flat: no `ExceptT` on top of `IO`, because `ExceptT e IO` does not compose safely with `async` / `race` / `concurrently` (which we need for parallel crawling). `ExceptT` / `Either` stay *inside* pipelines (parsing, validation, decode) and return `Either OttoError a`; unexpected `IO` failures remain exceptions and are caught at the application edges.
- **Logging.** [`co-log`](https://hackage.haskell.org/package/co-log). Log actions are first-class values (`LogAction m msg`) composed with `cmap` / `cfilter` / `cmapM`. mtl-friendly via `WithLog env msg m`. Swap loggers in tests by passing a different value — no mocking.
  - **Destinations (production):** the application bootstrap composes two sinks into a single `LogAction`:
    1. **stdout**, captured by `systemd-journald` on the production host (query with `journalctl -u otto`). Receives every severity.
    2. **Discord webhook**, filtered with `cfilter` to `Warning` and above. Loud alerts where the owner already is, without flooding the channel with routine output.
  - The library choice is independent of destinations — adding Grafana Cloud, Loki, or any other sink later is a matter of composing an additional `LogAction`, without touching application code.
- **Testing.** [`tasty`](https://hackage.haskell.org/package/tasty) as the umbrella runner, with:
  - [`tasty-hunit`](https://hackage.haskell.org/package/tasty-hunit) for unit tests.
  - [`tasty-hedgehog`](https://hackage.haskell.org/package/tasty-hedgehog) for property-based tests (integrated shrinking).
  - [`tasty-golden`](https://hackage.haskell.org/package/tasty-golden) for golden tests: pin canonical outputs (rendered Markdown per source type, formatted error messages, etc.) against reference files on disk. When output changes intentionally, regenerate the golden files; otherwise, failing tests are the regression signal.
- **Content fetching.** [Jina Reader](https://r.jina.ai) (`https://r.jina.ai/<URL>`) as the primary crawler. A single GET returns canonical Markdown with light metadata headers (title, source URL, published time, warnings). The free anonymous tier covers personal-scale crawling; `OTTO_JINA_API_KEY` is wired up for future upgrade to the authenticated tier (higher RPM). Target-site blocks (CAPTCHA, 403, Cloudflare) are surfaced by Jina as `Warning:` headers and modeled here as `CrawlerBlocked` errors — logged for manual review rather than retried. No local Chromium required; when the small fraction of blocked URLs turns out to be worth chasing, a Playwright-based crawler can be added behind the same `Crawler` handle without touching callers.
- **GHC language.** `default-language: GHC2024` (turns on `LambdaCase`, `NamedFieldPuns`, `TypeApplications`, `ImportQualifiedPost`, `NumericUnderscores`, `ScopedTypeVariables`, the `Derive*` family, `Flexible*`, and more — no need to repeat these per file).
- **Default extensions** (on top of `GHC2024`, in every package's `.cabal`):
  - `OverloadedStrings` — `Text` / `ByteString` literals without manual `pack`.
  - `DerivingStrategies` — forces explicit `deriving stock` / `deriving newtype` / `deriving via` for hygiene.
  - `DerivingVia` — derivation via newtype wrappers.
  - `StrictData` — strict fields by default; opt into laziness explicitly with `~`.
  - `OverloadedRecordDot` — `user.name` accessor syntax.

## Repository conventions

### Language

All repository content is in **English**: code, identifiers, comments, commit messages, documentation, README. Even when the owner discusses the work in any other language, the artifacts stay in English.

### Formatting

- Indentation: 2 spaces for every file, unless the ecosystem standard is different (see [.editorconfig](.editorconfig)).
- Haskell code is formatted with Ormolu on save.
- `.cabal` files are formatted with cabal-gild.
- Markdown is linted with [`markdownlint-cli2`](https://github.com/DavidAnson/markdownlint-cli2). Configuration lives in [`.markdownlint-cli2.jsonc`](.markdownlint-cli2.jsonc); the same file drives both the `davidanson.vscode-markdownlint` extension (in-editor, already in the devcontainer) and the CLI. Run `npx markdownlint-cli2 "**/*.md"` to check, `npx markdownlint-cli2 --fix "**/*.md"` to autofix the rules that support it. CI doesn't enforce yet — the editor surface is the primary one for now.

### Haskell code style

- **Function size and complexity.** Keep cyclomatic complexity low: decompose branchy code into named helpers, prefer pipelines and pattern matching over nested `if` / `case`. If a function needs a comment to explain its control flow, split it.
- **Haddock.** Every module starts with a module-level Haddock header (`{-|` block or `-- |` above `module`) explaining the module's purpose and the shape of its public API — this is what a reader sees first on Hackage/Hoogle. Every top-level identifier exported from a module also carries a Haddock block describing its contract for callers — *what* it does, preconditions, and non-obvious invariants. On non-trivial functions or data types, include executable `>>>` examples; examples age better than prose.
- **Typed errors.** Model errors through the type system, not strings. Each module defines its own error sum type (e.g. `CrawlerError`, `ProviderError`, `DbError`) capturing the concrete failure modes, with fields that preserve the context needed to debug or recover. At the application boundary, a single union type (e.g. `OttoError`) wraps the per-module errors so callers can pattern-match without losing specificity. Every error type implements `Show` such that its rendering is a formatted, human-readable message ready for logging or printing — no extra formatting layer needed at the call site.
- **Railway-oriented style.** Model failure as data. Use `ExceptT` / `Either` for sequential pipelines where the first error short-circuits, and an applicative `Validation` (e.g. the [`validation`](https://hackage.haskell.org/package/validation) package) for accumulating errors (form/input validation). Reserve `error` / `undefined` / partial functions for invariants a caller cannot violate — never for expected failure modes.

### Documentation

- **Sources of truth.** Module-level and per-identifier Haddock is the canonical documentation for code; `CHANGELOG.md` is the canonical history; `CLAUDE.md` is the canonical architecture/conventions surface; `README.md` is the project's first-impression page only.
- **Root `README.md` stays small.** It carries the project pitch, quickstart, a layout pointer, and links out — never long-form reference material that scales with the codebase. Do not introduce per-directory `README.md` files: they duplicate Haddock and multiply drift.
- **Every change checks the README.** Whenever a change adds a subcommand, env var, dependency, or top-level directory, ask whether the root `README.md` needs an update. Update it in the same commit, or note explicitly why it was skipped.
- **Split when a section starts dominating.** When one section (typically `Configuration` or `Subcommands`) outgrows the rest of the README, move *that* section into a dedicated file under `docs/` (e.g. `docs/configuration.md`, `docs/cli.md`) and leave a one-line pointer in the README. Split by topic, not by source-tree path.

### Git

- **Author:** commits are authored by the repository owner (the local git `user.name` / `user.email`). Never commit as the Claude user. Claude may appear only as a co-author via the standard `Co-Authored-By:` trailer, including the model name — e.g. `Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>`.
- **Subject line:** start with a [gitmoji](https://gitmoji.dev/), then a single space, then a sentence whose first letter is uppercase. Keep the first letter uppercase unless the first token is a proper noun, package name, or other lowercase-by-convention identifier.
  - Examples: `✨ Add content-research crawler`, `🐛 Fix feed parser off-by-one`, `📝 Update CLAUDE.md with AI provider notes`, `⬆️ Bump aeson to 2.2`.

### Private data and local files

The rule: **never commit owner-private data** — subscription lists, personal preferences, runtime output, secrets, project-specific topic taxonomies. When a config file is genuinely needed at runtime, ship a `<name>.example` template with placeholder values, gitignore the real `<name>`, and document the copy-and-edit workflow in [README.md](README.md). The current example: [`config/sources.yaml.example`](config/sources.yaml.example) is committed; the real `config/sources.yaml` is gitignored. Secrets (API keys, webhook URLs) stay in environment variables (`OTTO_*` family — see `app/Main.hs` and the README), never in committed files.

**Public identity is intentional and stays.** Author name, email, copyright line, GitHub handle in `otto.cabal` / `LICENSE`, and the `User-Agent` string in `Otto.Feed.Http` are required package metadata and identify Otto to upstream services — don't try to scrub them.

Currently gitignored:

- `.envrc` and `.direnv/` — per-project environment via direnv.
- `.claude/settings.local.json` — Claude Code local (per-machine) settings.
- Any `.env*` files carrying secrets.
- `config/sources.yaml` — owner's private feed registry; copy from `config/sources.yaml.example`.
- `catalog/` — runtime output of `otto research` / `otto digest`.
- `NEXT.md`, `TODO.md`, `NOTES.md` — local working / pick-up-next notes.

## Memory for Claude

Use **this file** (`CLAUDE.md`) as the persistent memory and guidance surface. Other Claude configuration files under `.claude/` inside this repo are also fine. Do **not** write to the external auto-memory directory — everything relevant should live in the repo so it is versioned and visible.
