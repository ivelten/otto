-- |
-- Module      : Otto.Feed.Types
-- Description : Vendor-neutral value types for RSS / Atom feeds.
--
-- A 'FeedItem' is the small projection of a feed entry that the
-- pipeline cares about: the link to crawl, an optional title for
-- diagnostics, and an optional publication timestamp for the recency
-- filter.
--
-- The full structured 'Text.Feed.Types.Feed' value from the @feed@
-- package never leaves the parser — keeping the surface narrow makes
-- swapping the implementation (sitemap, JSON Feed, …) trivial later.
module Otto.Feed.Types
  ( FeedItem (..),
    FeedName (..),
  )
where

import Data.Text (Text)
import Data.Time.Clock (UTCTime)
import Otto.Crawler.Types (URL)

-- | A single entry pulled from a feed.
data FeedItem = FeedItem
  { -- | The link to the actual content (this is what the crawler will
    -- fetch). Items whose feed entry has no link are skipped during
    -- parsing.
    fiUrl :: URL,
    -- | Item title when the feed exposes one.
    fiTitle :: Maybe Text,
    -- | Publication timestamp parsed from RFC 822 (RSS) or RFC 3339
    -- (Atom). 'Nothing' when the feed omits it or the value fails to
    -- parse — the recency filter treats those as "unknown date".
    fiPublishedAt :: Maybe UTCTime
  }
  deriving stock (Eq, Show)

-- | Identifier for a concrete feed implementation, used in
-- diagnostic output ('Show' of 'Otto.Feed.Error.FeedError' prefixes
-- with this).
data FeedName
  = Http
  | Mock
  deriving stock (Eq, Show)
