-- |
-- Module      : Otto.PipelineSpec
-- Description : Orchestration tests for "Otto.Pipeline".
--
-- Wires a mock 'Feeds' (canned responses), the existing mock
-- 'Crawler', and a temporary filesystem 'Catalog' into an 'App'
-- environment, then runs 'runDigest' and asserts on the resulting
-- 'PipelineReport' plus the on-disk side effects.
--
-- The pipeline delay is forced to 0 so the suite stays fast.
module Otto.PipelineSpec (tests) where

import Colog (LogAction (..))
import Data.ByteString.Lazy qualified as LBS
import Data.Time.Clock (UTCTime, addUTCTime, getCurrentTime)
import Otto.AI.Provider (disabledProvider)
import Otto.AI.Types (ProviderName (Anthropic))
import Otto.App (App, Env (..), runApp)
import Otto.Catalog (buildCatalog)
import Otto.Catalog.Config (CatalogConfig (..))
import Otto.Crawler.Error qualified as CrawlerError
import Otto.Crawler.Mock (newMockCrawler, takeCapturedCrawlRequests)
import Otto.Crawler.Types
  ( CrawlRequest (..),
    CrawlResult (..),
    URL (..),
  )
import Otto.Crawler.Types qualified as CrawlerTypes
import Otto.Feed.Error qualified as FeedError
import Otto.Feed.Handle (Feeds (..))
import Otto.Feed.Types (FeedItem (..))
import Otto.Feed.Types qualified as FeedTypes
import Otto.Pipeline
  ( PipelineConfig (..),
    PipelineReport (..),
    SourceReport (..),
    runDigest,
  )
import Otto.Sources (Source (..), Topic (..))
import System.Directory (doesFileExist)
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "pipeline digest"
    [ testCase "saves recent items, drops stale ones, records crawl failures" digestHappyPath,
      testCase "feed load failure increments srFeedsFailed" digestFeedFailure
    ]

silentLog :: LogAction App msg
silentLog = LogAction (\_ -> pure ())

fastConfig :: PipelineConfig
fastConfig =
  PipelineConfig
    { pipelineRecencyDays = 7,
      pipelineDelayMicros = 0
    }

mkFeeds :: [(URL, Either FeedError.FeedError [FeedItem])] -> Feeds
mkFeeds responses =
  Feeds
    { fName = FeedTypes.Mock,
      fLoad = \url -> case lookup url responses of
        Just r -> pure r
        Nothing -> pure (Right [])
    }

digestHappyPath :: Assertion
digestHappyPath = withSystemTempDirectory "otto-pipeline-test" $ \tmp -> do
  now <- getCurrentTime
  let recentT = addUTCTime (negate 86400) now
      staleT = addUTCTime (negate (15 * 86400)) now
      recentUrl = URL "https://example.com/recent"
      staleUrl = URL "https://example.com/stale"
      failingUrl = URL "https://example.com/blocked"
      datelessUrl = URL "https://example.com/dateless"
      feedUrl = URL "https://example.com/feed.xml"
  (mockHandle, mockCrawler) <-
    newMockCrawler
      [ Right (sampleCrawlResult recentUrl now),
        Left (sampleCrawlError failingUrl),
        Right (sampleCrawlResult datelessUrl now)
      ]
  let feeds =
        mkFeeds
          [ ( feedUrl,
              Right
                [ FeedItem {fiUrl = recentUrl, fiTitle = Just "Recent", fiPublishedAt = Just recentT},
                  FeedItem {fiUrl = staleUrl, fiTitle = Just "Stale", fiPublishedAt = Just staleT},
                  FeedItem {fiUrl = failingUrl, fiTitle = Just "Blocked", fiPublishedAt = Just recentT},
                  FeedItem {fiUrl = datelessUrl, fiTitle = Nothing, fiPublishedAt = Nothing}
                ]
            )
          ]
      catalog = buildCatalog (CatalogConfig {catalogDir = tmp})
      env =
        Env
          { envLogAction = silentLog,
            envAI = disabledProvider Anthropic "test",
            envCrawler = mockCrawler,
            envCatalog = catalog,
            envFeeds = feeds
          }
      sources = [Source {sourceTopic = Topic "test", sourceSeeds = [feedUrl]}]
  report <- runApp env (runDigest fastConfig sources)
  prItemsConsidered report @?= 3
  prItemsSaved report @?= 2
  prItemsFailed report @?= 1
  case prSources report of
    [sr] -> do
      srTopic sr @?= Topic "test"
      srFeedsLoaded sr @?= 1
      srFeedsFailed sr @?= 0
      srItemsConsidered sr @?= 3
      srItemsSaved sr @?= 2
      srItemsFailed sr @?= 1
    other -> assertFailure ("expected one source report, got: " <> show other)
  captured <- takeCapturedCrawlRequests mockHandle
  map crawlUrl captured @?= [recentUrl, failingUrl, datelessUrl]
  failureLogExists <- doesFileExist (tmp <> "/.failures.jsonl")
  assertBool "expected .failures.jsonl to exist" failureLogExists

digestFeedFailure :: Assertion
digestFeedFailure = withSystemTempDirectory "otto-pipeline-test" $ \tmp -> do
  let feedUrl = URL "https://example.com/broken-feed.xml"
  (_, mockCrawler) <- newMockCrawler []
  let catalog = buildCatalog (CatalogConfig {catalogDir = tmp})
      feeds =
        Feeds
          { fName = FeedTypes.Mock,
            fLoad = \_ ->
              pure
                ( Left
                    ( FeedError.FeedParseError
                        FeedTypes.Mock
                        (LBS.fromStrict "not a real feed")
                    )
                )
          }
      env =
        Env
          { envLogAction = silentLog,
            envAI = disabledProvider Anthropic "test",
            envCrawler = mockCrawler,
            envCatalog = catalog,
            envFeeds = feeds
          }
      sources = [Source {sourceTopic = Topic "broken", sourceSeeds = [feedUrl]}]
  report <- runApp env (runDigest fastConfig sources)
  prItemsConsidered report @?= 0
  prItemsSaved report @?= 0
  prItemsFailed report @?= 0
  case prSources report of
    [sr] -> do
      srFeedsLoaded sr @?= 0
      srFeedsFailed sr @?= 1
    other -> assertFailure ("expected one source report, got: " <> show other)

sampleCrawlResult :: URL -> UTCTime -> CrawlResult
sampleCrawlResult url at =
  CrawlResult
    { crawledUrl = url,
      crawledTitle = Just "Sample",
      crawledPublishedAt = Just "2026-04-22T10:00:00Z",
      crawledContent = "# sample\nbody\n",
      crawledCrawlerName = CrawlerTypes.Mock,
      crawledAt = at
    }

sampleCrawlError :: URL -> CrawlerError.CrawlerError
sampleCrawlError url =
  CrawlerError.CrawlerBlocked CrawlerTypes.Mock url 403 "test block"
