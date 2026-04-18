-- |
-- Module      : Otto.Crawler.MockSpec
-- Description : Unit tests for "Otto.Crawler.Mock".
--
-- Mirrors the mock provider tests: request capture order, FIFO
-- response popping, and deterministic error on queue exhaustion.
module Otto.Crawler.MockSpec (tests) where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..))
import Otto.Crawler.Error (CrawlerError (..))
import Otto.Crawler.Handle (Crawler (..))
import Otto.Crawler.Mock (newMockCrawler, takeCapturedCrawlRequests)
import Otto.Crawler.Types
  ( CrawlRequest (..),
    CrawlResult (..),
    CrawlerName (Mock),
    URL (..),
  )
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "mock crawler"
    [ testCase "captures requests in call order" captureOrderTest,
      testCase "returns canned responses in FIFO order" fifoTest,
      testCase "returns CrawlerMisconfigured when queue is exhausted" exhaustTest
    ]

sampleRequest :: Text -> CrawlRequest
sampleRequest u = CrawlRequest {crawlUrl = URL u}

sampleResponse :: Text -> CrawlResult
sampleResponse markdown =
  CrawlResult
    { crawledUrl = URL "https://example.com",
      crawledTitle = Just "Example",
      crawledPublishedAt = Nothing,
      crawledContent = markdown,
      crawledCrawlerName = Mock,
      crawledAt = UTCTime (fromGregorian 2026 1 1) 0
    }

captureOrderTest :: Assertion
captureOrderTest = do
  (handle, crawler) <-
    newMockCrawler
      [ Right (sampleResponse "r1"),
        Right (sampleResponse "r2")
      ]
  _ <- cFetch crawler (sampleRequest "https://a.example")
  _ <- cFetch crawler (sampleRequest "https://b.example")
  captured <- takeCapturedCrawlRequests handle
  captured @?= [sampleRequest "https://a.example", sampleRequest "https://b.example"]

fifoTest :: Assertion
fifoTest = do
  (_, crawler) <-
    newMockCrawler
      [ Right (sampleResponse "r1"),
        Right (sampleResponse "r2")
      ]
  r1 <- cFetch crawler (sampleRequest "https://x.example")
  r2 <- cFetch crawler (sampleRequest "https://y.example")
  case (r1, r2) of
    (Right a, Right b) -> do
      crawledContent a @?= "r1"
      crawledContent b @?= "r2"
    _ ->
      assertFailure
        ( "expected two successful results, got: "
            <> show r1
            <> " / "
            <> show r2
        )

exhaustTest :: Assertion
exhaustTest = do
  (_, crawler) <- newMockCrawler [Right (sampleResponse "only")]
  _ <- cFetch crawler (sampleRequest "https://1.example")
  r <- cFetch crawler (sampleRequest "https://2.example")
  case r of
    Left (CrawlerMisconfigured Mock msg) ->
      assertBool
        ("expected 'exhausted' in message: " <> Text.unpack msg)
        ("exhausted" `Text.isInfixOf` msg)
    other ->
      assertFailure
        ("expected CrawlerMisconfigured Mock, got: " <> show other)
