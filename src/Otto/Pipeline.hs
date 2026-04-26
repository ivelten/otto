-- |
-- Module      : Otto.Pipeline
-- Description : Research-ingestion pipeline (the @otto digest@
-- command).
--
-- 'runDigest' is the top-level orchestrator behind @otto digest@. It
-- performs:
--
-- 1. load the sources registry from disk,
-- 2. for each topic / seed, fetch the feed and parse its items,
-- 3. filter items to the last 'pipelineRecencyDays' days,
-- 4. crawl every surviving item through the configured 'Crawler',
-- 5. persist successes to the 'Catalog' and append failures to the
--    failure log.
--
-- This is the network-bound, /writer/ half of Otto. The future
-- synthesis half (@otto weekly@: catalog → weekly digest / post
-- draft) is a separate orchestrator that lives in this module
-- alongside 'runDigest' once it lands.
--
-- The traversal is sequential by design — ingestion latency is not
-- the bottleneck, and a single thread plus a small inter-request
-- delay keeps Otto polite to upstream feed servers and the Jina
-- Reader API. When concurrency turns out to matter, this module is
-- the natural place to introduce 'Control.Concurrent.Async'
-- primitives.
module Otto.Pipeline
  ( PipelineConfig (..),
    PipelineReport (..),
    SourceReport (..),
    defaultPipelineConfig,
    runDigest,
  )
where

import Colog (logError, logInfo, logWarning)
import Control.Concurrent (threadDelay)
import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time.Clock
  ( NominalDiffTime,
    UTCTime,
    addUTCTime,
    getCurrentTime,
  )
import Otto.App (App)
import Otto.Catalog
  ( CatalogEntry (..),
    crawlerErrorToFailure,
    recordFailure,
    save,
  )
import Otto.Crawler (CrawlRequest (..), URL (..), fetch)
import Otto.Feed (FeedItem (..), loadFeed)
import Otto.Sources (Source (..), Topic (..))

-- | Tunable pipeline behaviour. Defaults match the cadence described
-- in CLAUDE.md (a weekly post fed by a roughly weekly digest run).
data PipelineConfig = PipelineConfig
  { -- | Items older than this many days are dropped before the crawl.
    -- Items with no publication date are kept (we don't know enough
    -- to filter them out).
    pipelineRecencyDays :: Int,
    -- | Microseconds to sleep between consecutive crawls. A small
    -- delay keeps Otto polite to upstream and avoids tripping Jina
    -- Reader's free-tier rate limit.
    pipelineDelayMicros :: Int
  }
  deriving stock (Eq, Show)

-- | Default pipeline configuration: 7-day recency window, 1s between
-- crawls. Matches what 'runDigest' assumes when no explicit config
-- is supplied by the caller.
defaultPipelineConfig :: PipelineConfig
defaultPipelineConfig =
  PipelineConfig
    { pipelineRecencyDays = 7,
      pipelineDelayMicros = 1_000_000
    }

-- | Aggregated outcome of a pipeline run.
data PipelineReport = PipelineReport
  { -- | Per-source breakdown, one entry per topic.
    prSources :: [SourceReport],
    -- | Total feed entries that survived the recency filter and
    -- entered the crawl phase.
    prItemsConsidered :: Int,
    -- | Feed entries successfully crawled and saved.
    prItemsSaved :: Int,
    -- | Feed entries whose crawl failed (recorded in the catalog
    -- failure log).
    prItemsFailed :: Int
  }
  deriving stock (Eq, Show)

-- | Per-source slice of 'PipelineReport'.
data SourceReport = SourceReport
  { srTopic :: Topic,
    -- | Number of seed feeds successfully fetched and parsed.
    srFeedsLoaded :: Int,
    -- | Number of seed feeds that failed to load (network, HTTP,
    -- parse).
    srFeedsFailed :: Int,
    -- | Items considered for crawling after the recency filter.
    srItemsConsidered :: Int,
    -- | Items successfully crawled and saved.
    srItemsSaved :: Int,
    -- | Items whose crawl failed (recorded in the failure log).
    srItemsFailed :: Int
  }
  deriving stock (Eq, Show)

emptySourceReport :: Topic -> SourceReport
emptySourceReport topic =
  SourceReport
    { srTopic = topic,
      srFeedsLoaded = 0,
      srFeedsFailed = 0,
      srItemsConsidered = 0,
      srItemsSaved = 0,
      srItemsFailed = 0
    }

-- | Execute the digest pipeline against an in-memory list of sources.
--
-- The sources are usually loaded from @config/sources.yaml@ in
-- "Main"; passing them in explicitly keeps this module agnostic to
-- where they came from and makes testing trivial.
runDigest :: PipelineConfig -> [Source] -> App PipelineReport
runDigest cfg sources = do
  now <- liftIO getCurrentTime
  let cutoff = recencyCutoff cfg now
  logInfo $
    "digest: starting; topics="
      <> tshow (length sources)
      <> ", recencyDays="
      <> tshow (pipelineRecencyDays cfg)
  reports <- traverse (runSource cfg cutoff) sources
  let report = aggregate reports
  logInfo $
    "digest: done; considered="
      <> tshow (prItemsConsidered report)
      <> ", saved="
      <> tshow (prItemsSaved report)
      <> ", failed="
      <> tshow (prItemsFailed report)
  pure report

recencyCutoff :: PipelineConfig -> UTCTime -> UTCTime
recencyCutoff cfg now =
  let secondsPerDay :: NominalDiffTime
      secondsPerDay = 86_400
      window = fromIntegral (pipelineRecencyDays cfg) * secondsPerDay
   in addUTCTime (negate window) now

runSource :: PipelineConfig -> UTCTime -> Source -> App SourceReport
runSource cfg cutoff src = do
  let topic = sourceTopic src
  logInfo $ "digest: topic=" <> unTopic topic <> "; seeds=" <> tshow (length (sourceSeeds src))
  feedResults <- traverse (runSeed cfg cutoff topic) (sourceSeeds src)
  pure (foldl' addFeedOutcome (emptySourceReport topic) feedResults)

-- | Outcome of processing a single feed seed.
data FeedOutcome = FeedOutcome
  { foLoaded :: !Bool,
    foConsidered :: !Int,
    foSaved :: !Int,
    foFailed :: !Int
  }

emptyFeedOutcome :: FeedOutcome
emptyFeedOutcome = FeedOutcome {foLoaded = False, foConsidered = 0, foSaved = 0, foFailed = 0}

runSeed :: PipelineConfig -> UTCTime -> Topic -> URL -> App FeedOutcome
runSeed cfg cutoff topic seed = do
  logInfo $ "digest: feed=" <> unURL seed
  feedResult <- loadFeed seed
  case feedResult of
    Left err -> do
      logWarning $
        "digest: feed load failed for " <> unURL seed <> ": " <> tshow err
      pure emptyFeedOutcome {foLoaded = False}
    Right items -> do
      let recent = filterRecent cutoff items
      logInfo $
        "digest: feed="
          <> unURL seed
          <> "; items="
          <> tshow (length items)
          <> ", recent="
          <> tshow (length recent)
      crawlResults <- traverse (runItem cfg topic) recent
      let outcome =
            foldl'
              addCrawlOutcome
              emptyFeedOutcome {foLoaded = True, foConsidered = length recent}
              crawlResults
      pure outcome

-- | Outcome of crawling a single feed item.
data CrawlOutcome = CrawledOk | CrawledFailed
  deriving stock (Eq, Show)

runItem :: PipelineConfig -> Topic -> FeedItem -> App CrawlOutcome
runItem cfg topic item = do
  let url = fiUrl item
  outcome <- crawlAndStore url
  liftIO (sleep cfg)
  pure outcome
  where
    crawlAndStore url = do
      logInfo $ "digest: crawling " <> unURL url <> " (topic=" <> unTopic topic <> ")"
      crawlResult <- fetch CrawlRequest {crawlUrl = url}
      case crawlResult of
        Left err -> do
          logWarning $ "digest: crawl failed for " <> unURL url <> ": " <> tshow err
          recorded <- recordFailure (crawlerErrorToFailure url err)
          case recorded of
            Left e ->
              logError $
                "digest: also failed to record failure for "
                  <> unURL url
                  <> ": "
                  <> tshow e
            Right () -> pure ()
          pure CrawledFailed
        Right res -> do
          saveResult <- save res
          case saveResult of
            Left e -> do
              logError $
                "digest: save failed for " <> unURL url <> ": " <> tshow e
              pure CrawledFailed
            Right entry -> do
              logInfo $ "digest: saved " <> Text.pack (entryPath entry)
              pure CrawledOk

sleep :: PipelineConfig -> IO ()
sleep cfg = when (pipelineDelayMicros cfg > 0) (threadDelay (pipelineDelayMicros cfg))

filterRecent :: UTCTime -> [FeedItem] -> [FeedItem]
filterRecent cutoff = filter keep
  where
    keep item = case fiPublishedAt item of
      Nothing -> True
      Just t -> t >= cutoff

addCrawlOutcome :: FeedOutcome -> CrawlOutcome -> FeedOutcome
addCrawlOutcome o = \case
  CrawledOk -> o {foSaved = foSaved o + 1}
  CrawledFailed -> o {foFailed = foFailed o + 1}

addFeedOutcome :: SourceReport -> FeedOutcome -> SourceReport
addFeedOutcome sr fo =
  sr
    { srFeedsLoaded = srFeedsLoaded sr + (if foLoaded fo then 1 else 0),
      srFeedsFailed = srFeedsFailed sr + (if foLoaded fo then 0 else 1),
      srItemsConsidered = srItemsConsidered sr + foConsidered fo,
      srItemsSaved = srItemsSaved sr + foSaved fo,
      srItemsFailed = srItemsFailed sr + foFailed fo
    }

aggregate :: [SourceReport] -> PipelineReport
aggregate srs =
  PipelineReport
    { prSources = srs,
      prItemsConsidered = sum (map srItemsConsidered srs),
      prItemsSaved = sum (map srItemsSaved srs),
      prItemsFailed = sum (map srItemsFailed srs)
    }

tshow :: (Show a) => a -> Text
tshow = Text.pack . show
