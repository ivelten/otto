-- |
-- Module      : Main
-- Description : Entry point for the @otto@ executable.
--
-- Dispatches on the first command-line argument:
--
-- * no arguments → startup probe (logs a couple of 'Colog.logInfo'
--   lines and exits).
-- * @ask [--provider NAME | -p NAME] PROMPT@ → sends PROMPT through
--   the selected AI provider and prints the response to stdout.
-- * @crawl URL@ → fetches URL through the configured crawler and
--   prints the extracted Markdown to stdout.
-- * @research URL@ → fetches URL and persists it to the catalog;
--   crawl failures are appended to the catalog's failure log.
-- * @--help@ / @-h@ → prints usage.
--
-- Provider-selection precedence for @ask@: the @--provider@/@-p@
-- flag wins; otherwise the @OTTO_PROVIDER@ env variable applies;
-- otherwise @anthropic@. The corresponding @*_API_KEY@ must also be
-- set.
module Main (main) where

import Colog (logInfo)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text
import Network.HTTP.Client.TLS (newTlsManager)
import Otto.AI
  ( AIConfig,
    ModelId,
    PreferredProvider (..),
    Response (..),
    buildProvider,
    defaultModelFor,
    loadAIConfigFromEnv,
    loadPreferredProviderEnv,
    runAsk,
  )
import Otto.AI.Cli
  ( AskOptions (..),
    missingKeyMessage,
    parseAskArgs,
  )
import Otto.App (App, Env (..), liftLogAction, runApp)
import Otto.Catalog
  ( CatalogEntry (..),
    buildCatalog,
    crawlerErrorToFailure,
    loadCatalogConfigFromEnv,
    recordFailure,
    save,
  )
import Otto.Crawler
  ( CrawlRequest (..),
    CrawlResult (..),
    URL (..),
    buildCrawler,
    fetch,
    loadCrawlerConfigFromEnv,
  )
import Otto.Logging (LoggingConfig (..), bootstrapLogAction)
import System.Environment (getArgs, lookupEnv)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, hSetEncoding, stderr, stdout, utf8)

main :: IO ()
main = do
  -- Crawled content regularly contains non-ASCII (em dashes, accented
  -- characters, non-Latin scripts). Force UTF-8 on the standard
  -- streams so output doesn't die on the default C locale in
  -- minimal container images.
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8
  args <- getArgs
  case args of
    [] -> runDefault
    ["--help"] -> printUsage
    ["-h"] -> printUsage
    ("ask" : rest) -> runAskCmd rest
    ("crawl" : rest) -> runCrawlCmd rest
    ("research" : rest) -> runResearchCmd rest
    _ -> do
      hPutStrLn stderr ("unknown arguments: " <> unwords args)
      printUsage
      exitFailure

printUsage :: IO ()
printUsage =
  mapM_
    putStrLn
    [ "usage:",
      "  otto                                   run the default startup routine",
      "  otto ask [--provider NAME] PROMPT...   send PROMPT through the selected AI provider",
      "  otto crawl URL                         fetch URL as canonical Markdown (stdout only)",
      "  otto research URL                      fetch URL and save it to the catalog",
      "  otto --help | -h                       show this message",
      "",
      "provider-selection precedence for `ask`:",
      "  --provider / -p flag > OTTO_PROVIDER env var > anthropic (default)",
      "  valid provider names: anthropic | gemini",
      "",
      "environment:",
      "  OTTO_PROVIDER              anthropic (default) | gemini",
      "  OTTO_ANTHROPIC_API_KEY     required when the Anthropic provider is used",
      "  OTTO_GEMINI_API_KEY        required when the Gemini provider is used",
      "  OTTO_JINA_API_KEY          optional; enables Jina's authenticated tier",
      "  OTTO_JINA_ENGINE           optional; direct (default) | browser",
      "  OTTO_CATALOG_DIR           optional; root for the research catalog (default: ./catalog)",
      "  OTTO_DISCORD_WEBHOOK_URL   optional; Warning+ logs posted there"
    ]

runDefault :: IO ()
runDefault = do
  cfg <- loadAIConfigFromEnv
  pref <- resolvePreferred Nothing
  env <- buildEnv cfg pref
  runApp env ottoMain

ottoMain :: App ()
ottoMain = do
  logInfo "Otto is starting up."
  logInfo "Scaffold alive — no work scheduled yet."

runAskCmd :: [String] -> IO ()
runAskCmd args = case parseAskArgs args of
  Left err -> do
    hPutStrLn stderr ("otto ask: " <> err)
    exitFailure
  Right opts
    | null (askPromptWords opts) -> do
        hPutStrLn stderr "usage: otto ask [--provider NAME] PROMPT..."
        exitFailure
    | otherwise -> dispatchFromOptions opts

dispatchFromOptions :: AskOptions -> IO ()
dispatchFromOptions opts = do
  cfg <- loadAIConfigFromEnv
  pref <- resolvePreferred (askProviderOverride opts)
  case defaultModelFor cfg pref of
    Nothing -> do
      hPutStrLn stderr (missingKeyMessage pref)
      exitFailure
    Just model -> do
      env <- buildEnv cfg pref
      dispatchAsk env model (Text.pack (unwords (askPromptWords opts)))

dispatchAsk :: Env -> ModelId -> Text -> IO ()
dispatchAsk env model prompt = do
  result <- runApp env (runAsk model prompt)
  case result of
    Left err -> do
      hPutStrLn stderr (show err)
      exitFailure
    Right resp -> Text.putStrLn (respText resp)

runCrawlCmd :: [String] -> IO ()
runCrawlCmd [] = do
  hPutStrLn stderr "usage: otto crawl URL"
  exitFailure
runCrawlCmd [url] = dispatchCrawl (URL (Text.pack url))
runCrawlCmd extra = do
  hPutStrLn
    stderr
    ("otto crawl: expected exactly one URL, got " <> show (length extra))
  exitFailure

dispatchCrawl :: URL -> IO ()
dispatchCrawl url = do
  cfg <- loadAIConfigFromEnv
  pref <- resolvePreferred Nothing
  env <- buildEnv cfg pref
  result <- runApp env (fetch CrawlRequest {crawlUrl = url})
  case result of
    Left err -> do
      hPutStrLn stderr (show err)
      exitFailure
    Right res -> Text.putStrLn (crawledContent res)

runResearchCmd :: [String] -> IO ()
runResearchCmd [] = do
  hPutStrLn stderr "usage: otto research URL"
  exitFailure
runResearchCmd [url] = dispatchResearch (URL (Text.pack url))
runResearchCmd extra = do
  hPutStrLn
    stderr
    ("otto research: expected exactly one URL, got " <> show (length extra))
  exitFailure

-- | Fetch a URL, persist a successful crawl to the catalog, or
-- append a failure record on a crawl error. The crawl error is also
-- printed to stderr for visibility, but exit code 0 means the
-- failure record was written successfully — the catalog command
-- treats every outcome as bookkeeping.
dispatchResearch :: URL -> IO ()
dispatchResearch url = do
  cfg <- loadAIConfigFromEnv
  pref <- resolvePreferred Nothing
  env <- buildEnv cfg pref
  result <- runApp env (fetch CrawlRequest {crawlUrl = url})
  case result of
    Left err -> do
      hPutStrLn stderr (show err)
      logged <- runApp env (recordFailure (crawlerErrorToFailure url err))
      case logged of
        Left e -> do
          hPutStrLn stderr ("failed to record crawl failure: " <> show e)
          exitFailure
        Right () -> exitFailure
    Right res -> do
      saved <- runApp env (save res)
      case saved of
        Left e -> do
          hPutStrLn stderr (show e)
          exitFailure
        Right entry -> putStrLn ("saved: " <> entryPath entry)

-- | Resolve the preferred provider: the command-line override wins,
-- otherwise the @OTTO_PROVIDER@ env variable, otherwise
-- 'PreferAnthropic'. An unrecognized env variable value produces a
-- stderr warning and falls back to the default.
resolvePreferred :: Maybe PreferredProvider -> IO PreferredProvider
resolvePreferred = \case
  Just p -> pure p
  Nothing -> do
    envResult <- loadPreferredProviderEnv
    case envResult of
      Nothing -> pure PreferAnthropic
      Just (Right p) -> pure p
      Just (Left err) -> do
        hPutStrLn
          stderr
          ("warning: " <> err <> "; falling back to anthropic.")
        pure PreferAnthropic

buildEnv :: AIConfig -> PreferredProvider -> IO Env
buildEnv aiCfg pref = do
  manager <- newTlsManager
  crawlerCfg <- loadCrawlerConfigFromEnv
  catalogCfg <- loadCatalogConfigFromEnv
  webhookUrl <- fmap Text.pack <$> lookupEnv "OTTO_DISCORD_WEBHOOK_URL"
  ioLogAction <-
    bootstrapLogAction manager LoggingConfig {logDiscordWebhookUrl = webhookUrl}
  pure
    Env
      { envLogAction = liftLogAction ioLogAction,
        envAI = buildProvider manager aiCfg pref,
        envCrawler = buildCrawler manager crawlerCfg,
        envCatalog = buildCatalog catalogCfg
      }
