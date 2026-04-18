-- |
-- Module      : Otto.Crawler.JinaIntegrationSpec
-- Description : Live smoke test for the Jina Reader crawler.
--
-- Hits the real @r.jina.ai@ endpoint when
-- @OTTO_JINA_INTEGRATION=1@ is set; otherwise contributes an empty
-- (skipped) test group so the suite stays green without network.
--
-- The test is opt-in rather than auto-detected by @OTTO_JINA_API_KEY@
-- presence because Jina works anonymously — we don't want every CI
-- run to make network calls by default.
module Otto.Crawler.JinaIntegrationSpec (tests) where

import Data.Text qualified as Text
import Network.HTTP.Client.TLS (newTlsManager)
import Otto.Crawler.Config
  ( JinaConfig (..),
    defaultJinaBaseUrl,
  )
import Otto.Crawler.Handle (Crawler (..))
import Otto.Crawler.Jina (mkJinaCrawler)
import Otto.Crawler.Types (CrawlRequest (..), CrawlResult (..), URL (..))
import System.Environment (lookupEnv)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase)

tests :: IO TestTree
tests = do
  mIntegration <- lookupEnv "OTTO_JINA_INTEGRATION"
  pure $ case mIntegration of
    Nothing ->
      testGroup
        "jina integration (skipped: OTTO_JINA_INTEGRATION not set)"
        []
    Just _ ->
      testGroup
        "jina integration"
        [testCase "example.com returns Markdown with known title" exampleDotComTest]

exampleDotComTest :: Assertion
exampleDotComTest = do
  manager <- newTlsManager
  mKey <- lookupEnv "OTTO_JINA_API_KEY"
  let cfg =
        JinaConfig
          { jinaApiKey = Text.pack <$> mKey,
            jinaBaseUrl = defaultJinaBaseUrl,
            jinaEngine = Nothing
          }
      crawler = mkJinaCrawler manager cfg
      req = CrawlRequest {crawlUrl = URL "https://example.com"}
  result <- cFetch crawler req
  case result of
    Left err -> assertFailure ("crawler returned error: " <> show err)
    Right res -> do
      assertBool
        ( "expected title to contain 'Example', got: "
            <> show (crawledTitle res)
        )
        (maybe False (Text.isInfixOf "Example") (crawledTitle res))
      assertBool
        "body should be non-empty"
        (not (Text.null (crawledContent res)))
