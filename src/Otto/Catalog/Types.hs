-- |
-- Module      : Otto.Catalog.Types
-- Description : Vendor-neutral value types for the research catalog.
--
-- The catalog is the persistent home of every successfully crawled
-- page, plus an append-only log of crawl failures. These types
-- describe its surface in a way that maps cleanly onto any backend —
-- the filesystem implementation today, PostgreSQL or S3 tomorrow.
--
-- 'Slug' is the stable, deterministic identifier derived from a 'URL':
-- re-crawling the same URL produces the same slug and therefore
-- overwrites the same catalog entry, making the save operation
-- idempotent without bookkeeping.
module Otto.Catalog.Types
  ( Slug (..),
    urlSlug,
    CatalogEntry (..),
    FailureRecord (..),
    CatalogName (..),
  )
where

import Data.Bits (xor)
import Data.ByteString qualified as BS
import Data.String (IsString)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TE
import Data.Word (Word64, Word8)
import Numeric (showHex)
import Otto.Crawler.Types (URL (..))

-- | A stable, deterministic identifier for a 'URL' in the catalog.
--
-- Sixteen lowercase hex characters (64 bits of FNV-1a). Stable across
-- runs and GHC versions, so re-crawling a URL writes to the same
-- file. Collisions are statistically negligible at personal scale
-- (50% odds at ~2^32 distinct URLs).
newtype Slug = Slug {unSlug :: Text}
  deriving stock (Eq, Show)
  deriving newtype (IsString)

-- | Deterministic slug for a 'URL'.
--
-- ==== __Example__
--
-- >>> urlSlug (URL "https://example.com")
-- Slug {unSlug = "..."}
urlSlug :: URL -> Slug
urlSlug (URL u) = Slug (toHex16 (fnv1a64 (TE.encodeUtf8 u)))

-- | A successfully persisted catalog entry.
--
-- The renderer's output is carried alongside the path so callers and
-- tests can inspect the canonical form without re-reading the file.
data CatalogEntry = CatalogEntry
  { entryPath :: FilePath,
    entrySlug :: Slug,
    entrySourceUrl :: URL,
    entryRendered :: Text
  }
  deriving stock (Eq, Show)

-- | A crawl failure ready to be appended to the failure log.
--
-- 'frErrorClass' is a short, machine-friendly tag (e.g. @"blocked"@,
-- @"network_error"@) so weekly reports stay easy to aggregate; the
-- full diagnostic message lives in 'frMessage'.
data FailureRecord = FailureRecord
  { frUrl :: URL,
    frErrorClass :: Text,
    frMessage :: Text
  }
  deriving stock (Eq, Show)

-- | Identifier for a concrete catalog implementation, used in
-- diagnostic output ('Show' of 'Otto.Catalog.Error.CatalogError'
-- prefixes with this).
data CatalogName
  = FileSystem
  | Mock
  deriving stock (Eq, Show)

-- FNV-1a 64-bit. Stable, fast, non-cryptographic. Adequate for
-- catalog slugging at personal scale.
fnv1a64 :: BS.ByteString -> Word64
fnv1a64 = BS.foldl' step 0xcbf29ce484222325
  where
    step :: Word64 -> Word8 -> Word64
    step h b = (h `xor` fromIntegral b) * 0x100000001b3

toHex16 :: Word64 -> Text
toHex16 w =
  let hex = showHex w ""
      padded = replicate (16 - length hex) '0' <> hex
   in Text.pack padded
