-- |
-- Module      : Otto.Crawler.Types
-- Description : Vendor-neutral value types for URL fetching.
--
-- These types describe "fetch a URL, get back canonical Markdown" in a
-- way that maps cleanly onto any crawler implementation (Jina Reader,
-- a local headless browser, a plain HTTP fetch + heuristic extractor,
-- …). Each implementation translates between its own protocol and
-- these types.
--
-- The surface is intentionally minimal: one 'CrawlRequest' with the
-- target 'URL' and a 'CrawlResult' with the extracted Markdown plus a
-- small set of provenance fields. Per-request hints (preferred engine,
-- locale, …) will be added here when a second crawler needs them.
module Otto.Crawler.Types
  ( URL (..),
    CrawlRequest (..),
    CrawlResult (..),
    CrawlerName (..),
  )
where

import Data.String (IsString)
import Data.Text (Text)
import Data.Time.Clock (UTCTime)

-- | A target URL to crawl. Kept as a newtype over 'Text' so it travels
-- type-safely; validation happens at the HTTP boundary.
newtype URL = URL {unURL :: Text}
  deriving stock (Eq, Show)
  deriving newtype (IsString)

-- | Parameters for a single fetch.
--
-- Minimal by design — per-request hints (engine override, locale, …)
-- grow this record when a concrete need appears.
newtype CrawlRequest = CrawlRequest
  { crawlUrl :: URL
  }
  deriving stock (Eq, Show)

-- | The successful outcome of a crawl: Markdown content plus the
-- metadata the crawler was able to infer.
data CrawlResult = CrawlResult
  { crawledUrl :: URL,
    -- | Page title when the crawler could extract one.
    crawledTitle :: Maybe Text,
    -- | Publication timestamp as the crawler reported it, in the
    -- crawler's own format (ISO-8601 for Jina). Kept as 'Text' until
    -- we have a concrete need to parse.
    crawledPublishedAt :: Maybe Text,
    -- | Canonical Markdown body.
    crawledContent :: Text,
    -- | Which implementation produced this result.
    crawledCrawlerName :: CrawlerName,
    -- | Wall-clock time at which the crawl finished. Useful for
    -- staleness detection in the catalog.
    crawledAt :: UTCTime
  }
  deriving stock (Eq, Show)

-- | Identifier for a concrete crawler implementation, used in
-- diagnostic output ('Show' of 'Otto.Crawler.Error.CrawlerError'
-- prefixes with this).
data CrawlerName
  = Jina
  | Mock
  deriving stock (Eq, Show)
