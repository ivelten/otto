-- |
-- Module      : Otto.Feed.Handle
-- Description : The feed abstraction.
--
-- A 'Feeds' value is a record of functions, mirroring
-- 'Otto.Crawler.Handle.Crawler' and 'Otto.Catalog.Handle.Catalog'.
-- Callers reach the configured feed implementation via the 'HasFeeds'
-- class on the application environment, and run requests through the
-- 'loadFeed' helper.
module Otto.Feed.Handle
  ( Feeds (..),
    HasFeeds (..),
    loadFeed,
    disabledFeeds,
  )
where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (MonadReader, asks)
import Data.Text (Text)
import Otto.Crawler.Types (URL)
import Otto.Feed.Error (FeedError (..))
import Otto.Feed.Types (FeedItem, FeedName)

-- | A feed implementation, held as a first-class value.
--
-- The 'fLoad' action runs in plain 'IO' so feeds can be called from
-- any 'MonadIO' context and tests can exercise them without building
-- an application environment.
data Feeds = Feeds
  { fName :: FeedName,
    -- | Fetch a feed URL and return its items in document order. The
    -- recency filter and per-item crawling happen at the pipeline
    -- layer, not here.
    fLoad :: URL -> IO (Either FeedError [FeedItem])
  }

-- | Environments that expose a 'Feeds'.
class HasFeeds env where
  getFeeds :: env -> Feeds

-- | Load a feed through the configured implementation.
--
-- ==== __Example__
--
-- >>> loadFeed (URL "https://example.com/feed.xml")
loadFeed ::
  (HasFeeds env, MonadReader env m, MonadIO m) =>
  URL ->
  m (Either FeedError [FeedItem])
loadFeed url = do
  feeds <- asks getFeeds
  liftIO (fLoad feeds url)

-- | A 'Feeds' that rejects every request with 'FeedMisconfigured'.
--
-- Useful as a fallback when no feed backend can be configured: the
-- application still boots and non-feed work proceeds, but any load
-- attempt surfaces a clear configuration error.
disabledFeeds :: FeedName -> Text -> Feeds
disabledFeeds name reason =
  Feeds
    { fName = name,
      fLoad = \_ -> pure (Left (FeedMisconfigured name reason))
    }
