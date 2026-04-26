-- |
-- Module      : Otto.Catalog.RenderSpec
-- Description : Pure-path tests for "Otto.Catalog.Render".
--
-- Golden tests pin the canonical wire format of a catalog entry
-- (Markdown + YAML frontmatter) and a failure log line (single-line
-- JSON). Any change in field order, escaping, or whitespace shows up
-- as a diff.
--
-- The fixed timestamp 2026-04-18T01:23:45Z is used everywhere so the
-- output is byte-deterministic.
module Otto.Catalog.RenderSpec (tests) where

import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Otto.Catalog.Render (renderEntry, renderFailureLine)
import Otto.Catalog.Types (FailureRecord (..))
import Otto.Crawler.Types
  ( CrawlResult (..),
    CrawlerName (Jina),
    URL (..),
  )
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Golden (goldenVsString)

tests :: TestTree
tests =
  testGroup
    "catalog render"
    [ testGroup
        "entry"
        [ goldenEntry "full" fullEntry,
          goldenEntry "minimal" minimalEntry,
          goldenEntry "escaped" escapedEntry
        ],
      testGroup
        "failure line"
        [ goldenFailureLine "blocked" blockedFailure,
          goldenFailureLine "network-error" networkFailure
        ]
    ]

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 4 18) (secondsToDiffTime (1 * 3600 + 23 * 60 + 45))

goldenEntry :: String -> CrawlResult -> TestTree
goldenEntry name res =
  goldenVsString
    name
    ("test/golden/catalog/entry-" <> name <> ".md")
    (pure (toLBS (renderEntry res)))

goldenFailureLine :: String -> FailureRecord -> TestTree
goldenFailureLine name fr =
  goldenVsString
    name
    ("test/golden/catalog/failure-" <> name <> ".json")
    (pure (toLBS (renderFailureLine fixedTime fr <> "\n")))

toLBS :: Text -> ByteString
toLBS = LBS.fromStrict . TE.encodeUtf8

-- Entry fixtures

fullEntry :: CrawlResult
fullEntry =
  CrawlResult
    { crawledUrl = URL "https://example.com",
      crawledTitle = Just "Example Domain",
      crawledPublishedAt = Just "2025-01-15T10:00:00Z",
      crawledContent = "# Example Domain\n\nThis domain is for use in illustrative examples.\n",
      crawledCrawlerName = Jina,
      crawledAt = fixedTime
    }

minimalEntry :: CrawlResult
minimalEntry =
  CrawlResult
    { crawledUrl = URL "https://no-meta.example/article",
      crawledTitle = Nothing,
      crawledPublishedAt = Nothing,
      crawledContent = "bare body",
      crawledCrawlerName = Jina,
      crawledAt = fixedTime
    }

escapedEntry :: CrawlResult
escapedEntry =
  CrawlResult
    { crawledUrl = URL "https://blog.example/post",
      crawledTitle = Just "Sam \"Smith\" \\ Co.: A Story",
      crawledPublishedAt = Nothing,
      crawledContent = "content with \"quotes\" and a \\ backslash\n",
      crawledCrawlerName = Jina,
      crawledAt = fixedTime
    }

-- Failure fixtures

blockedFailure :: FailureRecord
blockedFailure =
  FailureRecord
    { frUrl = URL "https://quora.com/q/example",
      frErrorClass = "blocked",
      frMessage = "[Jina] target https://quora.com/q/example blocked with status 403: cloudflare challenge"
    }

networkFailure :: FailureRecord
networkFailure =
  FailureRecord
    { frUrl = URL "https://offline.example",
      frErrorClass = "network_error",
      frMessage = "[Jina] network error: ConnectionTimeout"
    }
