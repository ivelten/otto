-- |
-- Module      : Otto.Crawler.Config
-- Description : Environment-driven configuration for crawlers.
--
-- Jina Reader is the only crawler today and it works without
-- credentials (anonymous tier). The API key, base URL, and engine
-- choice are all optional overrides read from the environment so that
-- upgrading to a paid key in the future is a zero-code change.
module Otto.Crawler.Config
  ( CrawlerConfig (..),
    JinaConfig (..),
    JinaEngine (..),
    loadCrawlerConfigFromEnv,
    parseJinaEngine,
    defaultJinaBaseUrl,
  )
where

import Data.Char (toLower)
import Data.Text (Text)
import Data.Text qualified as Text
import System.Environment (lookupEnv)

-- | Aggregated crawler configuration. Today this carries only
-- 'JinaConfig'; new crawlers extend the record with additional
-- fields.
newtype CrawlerConfig = CrawlerConfig
  { ccJina :: JinaConfig
  }
  deriving stock (Eq, Show)

-- | Configuration for the Jina Reader crawler.
--
-- 'jinaApiKey' is 'Nothing' for the anonymous free tier and 'Just' a
-- bearer token to authenticate when the user upgrades.
data JinaConfig = JinaConfig
  { jinaApiKey :: Maybe Text,
    jinaBaseUrl :: Text,
    jinaEngine :: Maybe JinaEngine
  }
  deriving stock (Eq, Show)

-- | Jina's @X-Engine@ header. 'JinaBrowser' costs more credits on
-- paid tiers but renders JavaScript server-side; 'JinaDirect' uses
-- Jina's fast-path static fetch.
data JinaEngine = JinaDirect | JinaBrowser
  deriving stock (Eq, Show)

-- | Default base URL for Jina Reader.
defaultJinaBaseUrl :: Text
defaultJinaBaseUrl = "https://r.jina.ai"

-- | Parse a Jina engine name (case-insensitive). 'Left' enumerates
-- the accepted values.
parseJinaEngine :: String -> Either String JinaEngine
parseJinaEngine s = case map toLower s of
  "direct" -> Right JinaDirect
  "browser" -> Right JinaBrowser
  other ->
    Left
      ("unknown Jina engine: '" <> other <> "' (expected: direct | browser)")

-- | Read crawler configuration from environment variables.
--
-- * @OTTO_JINA_API_KEY@ — optional; anonymous when unset.
-- * @OTTO_JINA_BASE_URL@ — default 'defaultJinaBaseUrl'.
-- * @OTTO_JINA_ENGINE@ — @direct@ (default) or @browser@. Invalid
--   values are silently ignored so a typo doesn't block the daily
--   crawl; callers that want strict validation should inspect
--   'jinaEngine' after loading.
loadCrawlerConfigFromEnv :: IO CrawlerConfig
loadCrawlerConfigFromEnv = do
  jina <- loadJinaConfig
  pure CrawlerConfig {ccJina = jina}

loadJinaConfig :: IO JinaConfig
loadJinaConfig = do
  mKey <- lookupEnv "OTTO_JINA_API_KEY"
  mBase <- lookupEnv "OTTO_JINA_BASE_URL"
  mEngine <- lookupEnv "OTTO_JINA_ENGINE"
  pure
    JinaConfig
      { jinaApiKey = Text.pack <$> mKey,
        jinaBaseUrl = maybe defaultJinaBaseUrl Text.pack mBase,
        jinaEngine = mEngine >>= parseEngineSilent
      }
  where
    parseEngineSilent s = case parseJinaEngine s of
      Left _ -> Nothing
      Right e -> Just e
