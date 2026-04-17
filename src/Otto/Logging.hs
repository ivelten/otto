-- |
-- Module      : Otto.Logging
-- Description : Bootstrap of the composed application logger.
--
-- Otto writes logs to two destinations in production:
--
-- 1. __stdout__, captured by @systemd-journald@ on the Hetzner host. Receives
--    every severity. Query with @journalctl -u otto@.
-- 2. __Discord webhook__, filtered to @Warning@ and above — loud alerts where
--    the owner already is, without flooding the channel with routine traffic.
--
-- 'bootstrapLogAction' returns the composition of both sinks. The Discord
-- sink is only included when a webhook URL is configured; otherwise the
-- application logs to stdout alone (the local/development default).
--
-- The library choice ('co-log') is independent of destinations: adding
-- another sink (Grafana Cloud, Loki, a file, …) is just composing another
-- 'LogAction' into the pipeline — no change to application code.
module Otto.Logging
  ( LoggingConfig (..),
    bootstrapLogAction,
  )
where

import Colog
  ( LogAction (..),
    Message,
    Msg (..),
    Severity (..),
    cfilter,
    richMessageAction,
  )
import Control.Exception (SomeException, try)
import Control.Monad (void)
import Data.Aeson (encode, object, (.=))
import Data.Text (Text)
import Data.Text qualified as Text
import Network.HTTP.Client
  ( Manager,
    RequestBody (..),
    httpLbs,
    method,
    parseRequest,
    requestBody,
    requestHeaders,
  )
import Network.HTTP.Client.TLS (newTlsManager)

-- | Static configuration consumed by 'bootstrapLogAction'.
data LoggingConfig = LoggingConfig
  { -- | When 'Just', a @Warning+@-filtered Discord sink is composed into the
    -- 'LogAction'. When 'Nothing', only the stdout sink is active (the
    -- local development default).
    logDiscordWebhookUrl :: Maybe Text
  }

-- | Build the composed 'LogAction' used by the running application.
--
-- The stdout sink is always present. A Discord sink is added when
-- 'logDiscordWebhookUrl' is set; Discord delivery failures are swallowed
-- so that logging can never bring down the application.
bootstrapLogAction :: LoggingConfig -> IO (LogAction IO Message)
bootstrapLogAction cfg = case logDiscordWebhookUrl cfg of
  Nothing -> pure richMessageAction
  Just url -> do
    manager <- newTlsManager
    pure (richMessageAction <> discordSink manager url)
  where
    discordSink :: Manager -> Text -> LogAction IO Message
    discordSink mgr url =
      cfilter (\msg -> msg.msgSeverity >= Warning) (postDiscord mgr url)

-- | A 'LogAction' that posts messages to a Discord webhook.
--
-- The payload follows the minimal Discord webhook schema
-- (@{"content": "<formatted message>"}@). Network, TLS, or parsing
-- errors are caught and discarded — logging must never raise.
postDiscord :: Manager -> Text -> LogAction IO Message
postDiscord manager url = LogAction $ \msg ->
  void . try @SomeException $ do
    req0 <- parseRequest (Text.unpack url)
    let body = encode $ object ["content" .= renderDiscord msg]
        req =
          req0
            { method = "POST",
              requestBody = RequestBodyLBS body,
              requestHeaders = [("Content-Type", "application/json")]
            }
    _ <- httpLbs req manager
    pure ()

-- | Format a 'Message' for a Discord webhook post.
renderDiscord :: Message -> Text
renderDiscord msg =
  "[" <> Text.pack (show msg.msgSeverity) <> "] " <> msg.msgText
