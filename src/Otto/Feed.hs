-- |
-- Module      : Otto.Feed
-- Description : Public high-level feed API — types, abstraction,
-- errors, and the feed factory.
--
-- Most callers should import this module. It re-exports the
-- vendor-neutral value types ('FeedItem', 'FeedName'), the 'Feeds'
-- abstraction (including the 'HasFeeds' class and the 'loadFeed'
-- helper), and the 'FeedError' type. It also exposes 'buildFeeds' —
-- the factory that turns a 'Manager' into a concrete 'Feeds'.
--
-- Concrete implementations ('Otto.Feed.Http') are intentionally /not/
-- re-exported — importers bring them in explicitly when they need to
-- construct a feeds handle directly or wire up a mock.
module Otto.Feed
  ( module Otto.Feed.Types,
    module Otto.Feed.Error,
    module Otto.Feed.Handle,
    buildFeeds,
  )
where

import Network.HTTP.Client (Manager)
import Otto.Feed.Error
import Otto.Feed.Handle
import Otto.Feed.Http (mkHttpFeeds)
import Otto.Feed.Types

-- | Build the configured 'Feeds' value. Today this always returns the
-- HTTP + @feed@-package implementation. When a second backend is
-- added (sitemap, JSON Feed, …), this function learns to pick between
-- them.
--
-- The 'Manager' is passed through so connection pools and TLS
-- sessions are shared across callers.
buildFeeds :: Manager -> Feeds
buildFeeds = mkHttpFeeds
