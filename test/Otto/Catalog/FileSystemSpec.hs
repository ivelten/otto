-- |
-- Module      : Otto.Catalog.FileSystemSpec
-- Description : Round-trip tests for the filesystem catalog.
--
-- These tests touch the filesystem via 'withSystemTempDirectory', so
-- each case runs in an isolated, automatically cleaned-up directory.
-- They exercise the actual byte path: rendering happens in-process,
-- the catalog writes the file, the test reads it back and asserts on
-- the contents.
module Otto.Catalog.FileSystemSpec (tests) where

import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TE
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Otto.Catalog.Config (CatalogConfig (..))
import Otto.Catalog.FileSystem (mkFsCatalog)
import Otto.Catalog.Handle (Catalog (..))
import Otto.Catalog.Render (renderEntry)
import Otto.Catalog.Types
  ( CatalogEntry (..),
    FailureRecord (..),
    Slug (..),
    urlSlug,
  )
import Otto.Crawler.Types
  ( CrawlResult (..),
    CrawlerName (Jina),
    URL (..),
  )
import System.Directory (doesFileExist)
import System.FilePath ((<.>), (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "catalog filesystem"
    [ testCase "save writes a Markdown file at <dir>/<slug>.md" saveWritesFileTest,
      testCase "saved file content matches the renderer output" saveContentMatchesTest,
      testCase "save is idempotent on the same URL" saveIdempotentTest,
      testCase "save creates the catalog directory on demand" saveCreatesDirTest,
      testCase "recordFailure appends one JSON line to .failures.jsonl" recordFailureAppendsTest
    ]

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 4 18) (secondsToDiffTime (1 * 3600 + 23 * 60 + 45))

-- Always read catalog files as UTF-8, independent of the test machine's locale.
readUtf8 :: FilePath -> IO Text
readUtf8 path = TE.decodeUtf8 <$> BS.readFile path

sampleResult :: Text -> CrawlResult
sampleResult body =
  CrawlResult
    { crawledUrl = URL "https://example.com",
      crawledTitle = Just "Example Domain",
      crawledPublishedAt = Just "2025-01-15T10:00:00Z",
      crawledContent = body,
      crawledCrawlerName = Jina,
      crawledAt = fixedTime
    }

saveWritesFileTest :: Assertion
saveWritesFileTest = withSystemTempDirectory "otto-catalog-test" $ \tmp -> do
  let catalog = mkFsCatalog (CatalogConfig {catalogDir = tmp})
      res = sampleResult "# Example\n"
      expectedPath =
        tmp </> Text.unpack (unSlug (urlSlug (crawledUrl res))) <.> "md"
  result <- cSave catalog res
  case result of
    Left err -> assertFailure ("save failed: " <> show err)
    Right entry -> do
      entryPath entry @?= expectedPath
      entrySlug entry @?= urlSlug (crawledUrl res)
      exists <- doesFileExist (entryPath entry)
      assertBool "expected file to exist on disk" exists

saveContentMatchesTest :: Assertion
saveContentMatchesTest = withSystemTempDirectory "otto-catalog-test" $ \tmp -> do
  let catalog = mkFsCatalog (CatalogConfig {catalogDir = tmp})
      res = sampleResult "body content here\n"
  result <- cSave catalog res
  case result of
    Left err -> assertFailure ("save failed: " <> show err)
    Right entry -> do
      onDisk <- readUtf8 (entryPath entry)
      onDisk @?= renderEntry res
      onDisk @?= entryRendered entry

saveIdempotentTest :: Assertion
saveIdempotentTest = withSystemTempDirectory "otto-catalog-test" $ \tmp -> do
  let catalog = mkFsCatalog (CatalogConfig {catalogDir = tmp})
      first = sampleResult "first body\n"
      second = sampleResult "second body — overwritten\n"
  e1 <- cSave catalog first
  e2 <- cSave catalog second
  case (e1, e2) of
    (Right a, Right b) -> do
      entryPath a @?= entryPath b
      onDisk <- readUtf8 (entryPath b)
      onDisk @?= renderEntry second
    _ -> assertFailure ("expected two successful saves: " <> show e1 <> " / " <> show e2)

saveCreatesDirTest :: Assertion
saveCreatesDirTest = withSystemTempDirectory "otto-catalog-test" $ \tmp -> do
  let nested = tmp </> "deep" </> "nested" </> "catalog"
      catalog = mkFsCatalog (CatalogConfig {catalogDir = nested})
      res = sampleResult "x"
  result <- cSave catalog res
  case result of
    Left err -> assertFailure ("save failed: " <> show err)
    Right entry -> do
      exists <- doesFileExist (entryPath entry)
      assertBool "expected file to exist in the on-demand directory" exists

recordFailureAppendsTest :: Assertion
recordFailureAppendsTest = withSystemTempDirectory "otto-catalog-test" $ \tmp -> do
  let catalog = mkFsCatalog (CatalogConfig {catalogDir = tmp})
      fr1 =
        FailureRecord
          { frUrl = URL "https://blocked.example",
            frErrorClass = "blocked",
            frMessage = "403"
          }
      fr2 =
        FailureRecord
          { frUrl = URL "https://offline.example",
            frErrorClass = "network_error",
            frMessage = "timeout"
          }
      logPath = tmp </> ".failures.jsonl"
  r1 <- cRecordFailure catalog fr1
  r2 <- cRecordFailure catalog fr2
  case (r1, r2) of
    (Right (), Right ()) -> do
      contents <- readUtf8 logPath
      case Text.lines contents of
        [first, second] -> do
          assertBool
            ("expected first line to mention blocked.example, got: " <> Text.unpack first)
            ("blocked.example" `Text.isInfixOf` first)
          assertBool
            ("expected second line to mention offline.example, got: " <> Text.unpack second)
            ("offline.example" `Text.isInfixOf` second)
        other ->
          assertFailure
            ("expected exactly two failure lines, got: " <> show other)
    _ ->
      assertFailure
        ("expected two successful failure records: " <> show r1 <> " / " <> show r2)
