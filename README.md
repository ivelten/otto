# otto

Personal automation bot written in Haskell. First task: managing a personal
blog and website by researching content, drafting posts, and proposing
review-ready work to the owner. See [CLAUDE.md](CLAUDE.md) for architecture,
tech stack, and repository conventions.

## Requirements

- [Docker](https://www.docker.com/products/docker-desktop)
- [VS Code](https://code.visualstudio.com/) with the
  [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)

The development environment ships in a devcontainer carrying GHC 9.10.3,
Cabal 3.12.1.0, HLS, Ormolu, Hoogle, and the rest of the Haskell toolchain.
The underlying image is
[ivelten/haskell-devcontainer](https://github.com/ivelten/haskell-devcontainer).

## Quickstart

Open the repository in VS Code and choose **Reopen in Container**
(or run `./open-devcontainer.sh` from the terminal). Once inside the
container:

```bash
cabal update
cabal build all
cabal test
cabal run otto
```

## Configuration

Otto reads configuration from environment variables. For local development,
put them in a `.envrc` at the repository root (loaded automatically by
`direnv`).

- `OTTO_DISCORD_WEBHOOK_URL` — when set, `Warning+` log entries are also
  posted to this Discord webhook. When unset, stdout only.

## Layout

```text
.
├── src/Otto/        Library modules (App monad, error types, logging, …)
├── app/             Executable entry point
├── test/            tasty test suite
├── otto.cabal       Single-package manifest
├── cabal.project
├── CLAUDE.md        Architecture, tech stack, repository conventions
└── README.md
```

## License

BSD-3-Clause. See [LICENSE](LICENSE).
