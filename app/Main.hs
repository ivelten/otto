-- |
-- Module      : Main
-- Description : Entry point for the @otto@ executable.
module Main (main) where

import Colog (logInfo)
import Data.Text qualified as Text
import Otto.App (App, Env (..), liftLogAction, runApp)
import Otto.Logging (LoggingConfig (..), bootstrapLogAction)
import System.Environment (lookupEnv)

main :: IO ()
main = do
  webhookUrl <- fmap Text.pack <$> lookupEnv "OTTO_DISCORD_WEBHOOK_URL"
  ioLogAction <- bootstrapLogAction LoggingConfig {logDiscordWebhookUrl = webhookUrl}
  let env = Env {envLogAction = liftLogAction ioLogAction}
  runApp env ottoMain

ottoMain :: App ()
ottoMain = do
  logInfo "Otto is starting up."
  logInfo "Scaffold alive — no work scheduled yet."
