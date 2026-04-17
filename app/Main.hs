-- |
-- Module      : Main
-- Description : Entry point for the @otto@ executable.
--
-- Dispatches on the first command-line argument:
--
-- * no arguments → startup probe (logs a couple of 'Colog.logInfo' lines
--   and exits).
-- * @ask PROMPT@ → sends PROMPT through the configured AI provider and
--   prints the response to stdout.
-- * @--help@ / @-h@ → prints usage.
module Main (main) where

import Colog (logInfo)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text
import Network.HTTP.Client (Manager)
import Network.HTTP.Client.TLS (newTlsManager)
import Otto.AI
  ( AIConfig (..),
    AnthropicConfig (..),
    Provider,
    Response (..),
    disabledProvider,
    loadAIConfigFromEnv,
    runAsk,
  )
import Otto.AI.Anthropic (mkAnthropicProvider)
import Otto.AI.Types (ProviderName (Anthropic))
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
      "  otto                run the default startup routine",
      "  otto ask PROMPT...  send PROMPT to the configured AI provider",
      "  otto --help | -h    show this message"
    ]

runDefault :: IO ()
runDefault = do
  env <- buildEnv
  runApp env ottoMain

ottoMain :: App ()
ottoMain = do
  logInfo "Otto is starting up."
  logInfo "Scaffold alive — no work scheduled yet."

runAskCmd :: [String] -> IO ()
runAskCmd [] = do
  hPutStrLn stderr "usage: otto ask PROMPT..."
  exitFailure
runAskCmd rest = do
  cfg <- loadAIConfigFromEnv
  case acAnthropic cfg of
    Nothing -> missingKey
    Just anthropic -> dispatchAsk anthropic (Text.pack (unwords rest))

missingKey :: IO ()
missingKey = do
  hPutStrLn
    stderr
    "OTTO_ANTHROPIC_API_KEY is not set; cannot call `otto ask`."
  exitFailure

dispatchAsk :: AnthropicConfig -> Text.Text -> IO ()
dispatchAsk anthropic prompt = do
  env <- buildEnv
  result <- runApp env (runAsk (anthropicDefaultModel anthropic) prompt)
  case result of
    Left err -> do
      hPutStrLn stderr (show err)
      exitFailure
    Right resp -> Text.putStrLn (respText resp)

buildEnv :: IO Env
buildEnv = do
  manager <- newTlsManager
  aiConfig <- loadAIConfigFromEnv
  webhookUrl <- fmap Text.pack <$> lookupEnv "OTTO_DISCORD_WEBHOOK_URL"
  ioLogAction <-
    bootstrapLogAction manager LoggingConfig {logDiscordWebhookUrl = webhookUrl}
  pure
    Env
      { envLogAction = liftLogAction ioLogAction,
        envAI = buildProvider manager aiConfig
      }

buildProvider :: Manager -> AIConfig -> Provider
buildProvider manager cfg = case acAnthropic cfg of
  Just anthropic -> mkAnthropicProvider manager anthropic
  Nothing -> disabledProvider Anthropic "OTTO_ANTHROPIC_API_KEY is not set"
