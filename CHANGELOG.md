# Changelog

All notable changes to this project will be documented in this file,
following [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Project scaffolding: `App` monad (`ReaderT Env IO`), `OttoError` sum
  type, composed logging via `co-log` (stdout + optional Discord webhook
  filtered to `Warning+`), and a `tasty` test harness.
- **Provider-agnostic AI layer** (`Otto.AI`): `Provider` record
  (record-of-functions), `HasAI` environment class, `generate` / `runAsk`
  helpers, `disabledProvider` fallback, `ProviderError` sum type with a
  hand-written `Show` instance, and a config loader that activates
  providers only when their API keys are set.
  - **Anthropic** implementation (`Otto.AI.Anthropic`) against the
    Messages API, with pure request-body builder and response decoder in
    `Otto.AI.Anthropic.Internal` and golden tests pinning the JSON wire
    format.
  - **Gemini** implementation (`Otto.AI.Gemini`) against Google's
    `generateContent` endpoint, mirroring the Anthropic layout.
  - **Mock** provider (`Otto.AI.Mock`) with request capture and FIFO
    response queue for unit tests.
- **Vendor-agnostic crawler layer** (`Otto.Crawler`): `Crawler` record,
  `HasCrawler` environment class, `fetch` helper, `CrawlerError` sum
  type with a dedicated `CrawlerBlocked` variant for target-site 403 /
  CAPTCHA responses.
  - **Jina Reader** implementation (`Otto.Crawler.Jina`) that calls
    `r.jina.ai/<URL>` and parses the metadata-then-Markdown envelope.
    Target-site blocks are detected via the `Warning:` header Jina
    returns.
  - **Mock** crawler (`Otto.Crawler.Mock`) with the same capture / queue
    shape as the AI mock.
- **Backend-agnostic catalog layer** (`Otto.Catalog`): `Catalog` record,
  `HasCatalog` environment class, `save` / `recordFailure` helpers,
  `CatalogError` sum type, and `crawlerErrorToFailure` to bridge crawl
  errors into the failure log. The catalog gives crawl results a
  durable home so the link is no longer the source of truth.
  - **Filesystem** implementation (`Otto.Catalog.FileSystem`) writes
    one `<dir>/<slug>.md` per URL with YAML frontmatter (source URL,
    title, published / crawled timestamps, crawler name) and appends
    crawl failures to `<dir>/.failures.jsonl`. Slugs are FNV-1a 64-bit
    hex over the URL — deterministic, so re-saving the same URL is
    idempotent. Files are written as UTF-8 explicitly, locale-independent.
  - Pure renderer (`Otto.Catalog.Render`) golden-tested for the
    canonical Markdown + YAML and JSONL wire formats.
- `otto research URL` subcommand: fetches the URL through the
  configured crawler and persists it via the catalog. Crawl errors are
  appended to `<dir>/.failures.jsonl` with the original URL, a stable
  error class tag (`blocked`, `network_error`, …), and the rendered
  error message.
- `otto` executable subcommands:
  - default invocation logs a startup banner.
  - `otto ask [--provider NAME | -p NAME] PROMPT…` sends the prompt
    through the selected provider and prints the reply on stdout.
    Provider precedence: flag > `OTTO_PROVIDER` env var > `anthropic`.
  - `otto crawl URL` fetches the URL through the configured crawler and
    prints the extracted Markdown on stdout; errors (including
    `CrawlerBlocked`) go to stderr with a non-zero exit.
  - `otto research URL` fetches the URL and persists it to the
    catalog; crawl errors are recorded in the failure log instead of
    discarded.
  - `otto --help` / `-h` prints usage and the list of recognized
    environment variables.
- GitHub Actions CI workflow on `ubuntu-24.04-arm` that builds the
  library, executable, and test suite and runs all tests on every push
  or PR to `master`. Cabal store + `dist-newstyle` cached keyed on OS +
  GHC + `*.cabal` + `cabal.project` hashes. A concurrency group cancels
  superseded runs on rapid pushes.
- Environment-gated live integration tests: `OTTO_ANTHROPIC_API_KEY` for
  Anthropic, `OTTO_GEMINI_API_KEY` for Gemini, `OTTO_JINA_INTEGRATION=1`
  for the Jina smoke test against `example.com`.

### Changed

- `Otto.AI.Cli` no longer owns `PreferredProvider`, `parseProviderName`,
  `defaultModelFor`, or the `OTTO_PROVIDER` loader — those moved to
  `Otto.AI.Config` so configuration loading is symmetric and so non-CLI
  callers can reuse the preference logic.
- The `Otto.AI` umbrella module is now the canonical public entry point
  for the AI layer, exposing the `buildProvider` factory in addition to
  the re-exports.
- `Otto.Logging.bootstrapLogAction` now accepts an external
  `Network.HTTP.Client.Manager` instead of constructing its own, so the
  AI layer, the crawler, and the Discord webhook sink share a single
  connection pool and TLS session cache.
- `app/Main.hs` forces UTF-8 on `stdout` and `stderr` at startup so
  non-ASCII content from crawlers and LLMs doesn't die under the default
  C locale in minimal container images.

### Removed

- Hosting-provider references were removed from the repository (and
  from git history). The deployment target architecture is documented
  generically as `aarch64-linux`.
