# otto

Personal automation bot written in Haskell. Researches content across the
web, extracts it as canonical Markdown, and calls LLMs to summarize and
draft posts. See [CLAUDE.md](CLAUDE.md) for architecture, tech stack, and
repository conventions; see [CHANGELOG.md](CHANGELOG.md) for what has
landed.

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
- `otto --help` / `otto -h` — prints usage and the list of recognized
  environment variables.

Examples:

```bash
# Ask Claude
OTTO_ANTHROPIC_API_KEY=... cabal run -v0 otto -- ask "Explain monads briefly."

# Ask Gemini via the flag
OTTO_GEMINI_API_KEY=... cabal run -v0 otto -- ask --provider gemini "Explain monads briefly."

# Crawl a page to stdout (works anonymously on Jina's free tier)
cabal run -v0 otto -- crawl https://example.com > example.md
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
│   ├── Crawler/              # Crawler abstraction + Jina Reader impl + Mock
│   ├── App.hs                # Application monad, Env, HasLog/HasAI/HasCrawler instances
│   ├── Error.hs              # OttoError union (AIError | CrawlError)
│   └── Logging.hs            # co-log bootstrap (stdout + optional Discord)
├── app/Main.hs               # Executable entry point + CLI dispatch
├── test/
│   ├── Main.hs               # tasty runner
│   ├── Otto/                 # Spec modules mirroring src/Otto
│   └── golden/               # Golden fixtures (Anthropic / Gemini JSON bodies)
├── .github/workflows/ci.yml  # ARM64 build + test on push / PR
├── otto.cabal                # Single-package manifest
├── cabal.project
├── CLAUDE.md                 # Architecture, tech stack, repository conventions
├── CHANGELOG.md              # What landed, Keep-a-Changelog style
└── README.md
```

## License

BSD-3-Clause. See [LICENSE](LICENSE).
