-- |
-- Module      : Otto.Feed.HttpSpec
-- Description : Pure-path tests for the RSS / Atom parser in
-- "Otto.Feed.Http".
--
-- Three cases:
--
-- * an RSS 2.0 sample yields the expected items, with linkless items
--   dropped.
-- * an Atom sample yields its entries with parsed publication
--   timestamps.
-- * arbitrary non-feed bytes surface a 'FeedParseError'.
module Otto.Feed.HttpSpec (tests) where

import Data.ByteString.Lazy qualified as LBS
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Otto.Crawler.Types (URL (..))
import Otto.Feed.Error (FeedError (..))
import Otto.Feed.Http (parseFeedBytes)
import Otto.Feed.Types (FeedItem (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "feed parser"
    [ testCase "RSS 2.0 yields items in document order, linkless dropped" rssCase,
      testCase "Atom yields entries with parsed published timestamps" atomCase,
      testCase "non-feed bytes surface a parse error" garbageCase
    ]

rssCase :: IO ()
rssCase = do
  body <- LBS.readFile "test/golden/feed/sample-rss.xml"
  case parseFeedBytes body of
    Left err -> assertFailure ("expected Right, got: " <> show err)
    Right items -> map fiUrl items @?= [URL "https://example.com/posts/recent", URL "https://example.com/posts/older"]

atomCase :: IO ()
atomCase = do
  body <- LBS.readFile "test/golden/feed/sample-atom.xml"
  case parseFeedBytes body of
    Left err -> assertFailure ("expected Right, got: " <> show err)
    Right items -> map fiPublishedAt items @?= [Just (utc 2026 4 22 10 0 0), Just (utc 2025 12 1 10 0 0)]

garbageCase :: IO ()
garbageCase = do
  body <- LBS.readFile "test/golden/feed/garbage.xml"
  case parseFeedBytes body of
    Right ok -> assertFailure ("expected Left, got: " <> show (length ok) <> " items")
    Left (FeedParseError _ _) -> pure ()
    Left other ->
      assertFailure ("expected FeedParseError, got: " <> show other)

utc :: Integer -> Int -> Int -> Int -> Int -> Int -> UTCTime
utc y m d hh mm ss =
  UTCTime
    (fromGregorian y m d)
    (secondsToDiffTime (fromIntegral (hh * 3600 + mm * 60 + ss)))
