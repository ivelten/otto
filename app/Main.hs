-- |
-- Module      : Main
-- Description : Entry point for the @otto@ executable.
--
-- Dispatches on the first command-line argument:
--
-- * no arguments → startup probe (logs a couple of 'Colog.logInfo' lines
--   and exits).
-- * @ask [--provider NAME | -p NAME] PROMPT@ → sends PROMPT through the
--   selected AI provider and prints the response to stdout.
-- * @--help@ / @-h@ → prints usage.
--
-- Provider-selection precedence for @ask@: the @--provider@/@-p@ flag
-- wins; otherwise the @OTTO_PROVIDER@ env variable applies; otherwise
-- @anthropic@. The corresponding @*_API_KEY@ must also be set.
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
import Otto.Logging (LoggingConfig (..), bootstrapLogAction)
import System.Environment (getArgs, lookupEnv)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

main :: IO ()
main = do
  args <- getArgs
  case args of
    [] -> runDefault
    ["--help"] -> printUsage
    ["-h"] -> printUsage
    ("ask" : rest) -> runAskCmd rest
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
      "  otto ask [--provider NAME] PROMPT...   send PROMPT through the selected provider",
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
buildEnv cfg pref = do
  manager <- newTlsManager
  webhookUrl <- fmap Text.pack <$> lookupEnv "OTTO_DISCORD_WEBHOOK_URL"
  ioLogAction <-
    bootstrapLogAction manager LoggingConfig {logDiscordWebhookUrl = webhookUrl}
  pure
    Env
      { envLogAction = liftLogAction ioLogAction,
        envAI = buildProvider manager cfg pref
      }
