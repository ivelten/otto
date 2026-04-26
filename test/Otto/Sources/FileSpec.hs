-- |
-- Module      : Otto.Sources.FileSpec
-- Description : Unit tests for the YAML loader in
-- "Otto.Sources.File".
--
-- Two cases:
--
-- * a valid YAML registry round-trips through 'loadSources' and yields
--   the expected list of 'Source' values.
-- * a malformed YAML registry surfaces a 'SourcesParseError' carrying
--   the offending path.
module Otto.Sources.FileSpec (tests) where

import Otto.Crawler.Types (URL (..))
import Otto.Sources (Source (..), Topic (..))
import Otto.Sources.Config (SourcesConfig (..))
import Otto.Sources.Error (SourcesError (..))
import Otto.Sources.File (loadSources)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "sources file"
    [ testCase "valid YAML decodes to expected sources" validCase,
      testCase "missing topic surfaces a parse error" missingTopicCase
    ]

validCase :: IO ()
validCase = do
  result <- loadSources (SourcesConfig "test/golden/sources/valid.yaml")
  case result of
    Left err -> assertFailure ("expected Right, got: " <> show err)
    Right sources -> sources @?= expected
  where
    expected =
      [ Source
          { sourceTopic = Topic "topic-one",
            sourceSeeds =
              [ URL "https://example.com/feed.atom",
                URL "https://example.com/another-feed.xml"
              ]
          },
        Source
          { sourceTopic = Topic "topic-two",
            sourceSeeds = [URL "https://example.com/third-feed.rss"]
          }
      ]

missingTopicCase :: IO ()
missingTopicCase = do
  result <- loadSources (SourcesConfig "test/golden/sources/missing-topic.yaml")
  case result of
    Right ok -> assertFailure ("expected Left, got: " <> show ok)
    Left (SourcesParseError path _msg) ->
      path @?= "test/golden/sources/missing-topic.yaml"
    Left other ->
      assertFailure ("expected SourcesParseError, got: " <> show other)
