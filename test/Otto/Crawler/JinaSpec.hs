-- |
-- Module      : Otto.Crawler.JinaSpec
-- Description : Unit tests for the Jina Reader response parser.
--
-- Exercises 'parseJinaResponse' and 'extractBlocked' against
-- hand-crafted responses that reproduce Jina Reader's documented
-- formats (happy path, missing metadata, target-site block).
module Otto.Crawler.JinaSpec (tests) where

import Data.ByteString.Lazy (ByteString)
import Data.Text qualified as Text
import Otto.Crawler.Jina.Internal
  ( ParsedJina (..),
    extractBlocked,
    parseJinaResponse,
  )
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "jina parser"
    [ testCase "parses happy-path response" parseHappyTest,
      testCase "parses response with published time" parsePublishedTest,
      testCase "parses response with single warning and no body" parseBlockedTest,
      testCase "extractBlocked finds target-side block" extractBlockedHitTest,
      testCase "extractBlocked ignores non-block warnings" extractBlockedMissTest,
      testCase "body without marker falls into headers (empty body)" parseNoMarkerTest
    ]

-- Fixtures

happyBody :: ByteString
happyBody =
  "Title: Example Domain\n\
  \URL Source: https://example.com\n\
  \Markdown Content:\n\
  \# Example Domain\n\
  \\n\
  \This domain is for use in illustrative examples in documents.\n"

publishedBody :: ByteString
publishedBody =
  "Title: Something Interesting\n\
  \URL Source: https://blog.example/post\n\
  \Published Time: 2025-01-15T10:00:00Z\n\
  \Markdown Content:\n\
  \Body text here.\n"

blockedBody :: ByteString
blockedBody =
  "Title: Just a moment...\n\
  \URL Source: http://www.quora.com/whatever\n\
  \Warning: Target URL returned error 403: Forbidden\n\
  \Warning: This page maybe requiring CAPTCHA, please make sure you are authorized to access this page.\n\
  \Markdown Content:\n\
  \## Performing security verification\n"

noMarkerBody :: ByteString
noMarkerBody =
  "Title: Only Metadata\n\
  \URL Source: https://example.com\n"

-- Tests

parseHappyTest :: Assertion
parseHappyTest = do
  let parsed = parseJinaResponse happyBody
  pjTitle parsed @?= Just "Example Domain"
  pjSourceUrl parsed @?= Just "https://example.com"
  pjPublishedTime parsed @?= Nothing
  pjWarnings parsed @?= []
  assertBool
    "body should contain heading"
    ("# Example Domain" `Text.isInfixOf` pjBody parsed)
  assertBool
    "body should contain illustrative text"
    ("illustrative examples" `Text.isInfixOf` pjBody parsed)

parsePublishedTest :: Assertion
parsePublishedTest = do
  let parsed = parseJinaResponse publishedBody
  pjTitle parsed @?= Just "Something Interesting"
  pjPublishedTime parsed @?= Just "2025-01-15T10:00:00Z"
  pjBody parsed @?= "Body text here."

parseBlockedTest :: Assertion
parseBlockedTest = do
  let parsed = parseJinaResponse blockedBody
  pjTitle parsed @?= Just "Just a moment..."
  length (pjWarnings parsed) @?= 2
  case pjWarnings parsed of
    (firstWarning : _) ->
      assertBool
        "first warning should mention 'Target URL returned error 403'"
        ("403" `Text.isInfixOf` firstWarning)
    [] -> fail "expected at least one warning after length check"

extractBlockedHitTest :: Assertion
extractBlockedHitTest = do
  let parsed = parseJinaResponse blockedBody
  case extractBlocked (pjWarnings parsed) of
    Just (status, reason) -> do
      status @?= 403
      reason @?= "Forbidden"
    Nothing -> fail "expected Just (403, ...) but got Nothing"

extractBlockedMissTest :: Assertion
extractBlockedMissTest =
  extractBlocked ["Some unrelated warning", "Another thing"] @?= Nothing

parseNoMarkerTest :: Assertion
parseNoMarkerTest = do
  let parsed = parseJinaResponse noMarkerBody
  pjTitle parsed @?= Just "Only Metadata"
  pjBody parsed @?= ""
