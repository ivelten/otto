-- |
-- Module      : Otto.Crawler.Handle
-- Description : The crawler abstraction.
--
-- A 'Crawler' is a value — a record of functions — not a typeclass,
-- mirroring 'Otto.AI.Provider.Provider'. Callers reach the configured
-- crawler via the 'HasCrawler' class on the application environment,
-- and run a 'CrawlRequest' via the 'fetch' helper.
module Otto.Crawler.Handle
  ( Crawler (..),
    HasCrawler (..),
    fetch,
    disabledCrawler,
  )
where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (MonadReader, asks)
import Data.Text (Text)
import Otto.Crawler.Error (CrawlerError (..))
import Otto.Crawler.Types
  ( CrawlRequest,
    CrawlResult,
    CrawlerName,
  )

-- | A crawler implementation, held as a first-class value.
--
-- The 'cFetch' action runs in plain 'IO' (not 'App') so crawlers can
-- be called from any 'MonadIO' context and tests can exercise them
-- without building an application environment.
data Crawler = Crawler
  { cName :: CrawlerName,
    cFetch :: CrawlRequest -> IO (Either CrawlerError CrawlResult)
  }

-- | Environments that expose a 'Crawler'.
class HasCrawler env where
  getCrawler :: env -> Crawler

-- | Run a 'CrawlRequest' through the configured crawler.
--
-- ==== __Example__
--
-- >>> fetch (CrawlRequest (URL "https://example.com"))
fetch ::
  (HasCrawler env, MonadReader env m, MonadIO m) =>
  CrawlRequest ->
  m (Either CrawlerError CrawlResult)
fetch req = do
  crawler <- asks getCrawler
  liftIO (cFetch crawler req)

-- | A 'Crawler' that rejects every request with 'CrawlerMisconfigured'.
--
-- Useful as a fallback when no crawler can be configured: the
-- application still boots and non-crawl work proceeds, but any fetch
-- attempt surfaces a clear configuration error.
disabledCrawler :: CrawlerName -> Text -> Crawler
disabledCrawler name reason =
  Crawler
    { cName = name,
      cFetch = \_ -> pure (Left (CrawlerMisconfigured name reason))
    }
