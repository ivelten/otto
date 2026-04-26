-- |
-- Module      : Otto.Catalog.SlugSpec
-- Description : Determinism, uniqueness, and stability of 'urlSlug'.
--
-- The catalog filename is derived from the URL via 'urlSlug', so a
-- regression in the hash function would silently rewrite every
-- existing entry to a new path. The golden tests pin the FNV-1a
-- output for representative URLs; the HUnit cases guarantee the
-- function is deterministic on its input and discriminating between
-- different URLs.
module Otto.Catalog.SlugSpec (tests) where

import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TE
import Otto.Catalog.Types (Slug (..), urlSlug)
import Otto.Crawler.Types (URL (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit (Assertion, assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "catalog slug"
    [ testCase "is deterministic on the same URL" deterministicTest,
      testCase "discriminates between different URLs" uniquenessTest,
      goldenSlug "example-com" "https://example.com",
      goldenSlug "with-path" "https://example.com/path/to/resource",
      goldenSlug "with-query" "https://example.com/p?q=hello&n=1"
    ]

deterministicTest :: Assertion
deterministicTest =
  urlSlug (URL "https://example.com") @?= urlSlug (URL "https://example.com")

uniquenessTest :: Assertion
uniquenessTest =
  assertBool
    "expected distinct slugs for distinct URLs"
    (urlSlug (URL "https://a.example") /= urlSlug (URL "https://b.example"))

goldenSlug :: String -> String -> TestTree
goldenSlug name url =
  goldenVsString
    name
    ("test/golden/catalog/slug-" <> name <> ".txt")
    (pure (toLBS (unSlug (urlSlug (URL (Text.pack url))) <> "\n")))

toLBS :: Text.Text -> ByteString
toLBS = LBS.fromStrict . TE.encodeUtf8
