-- |
-- Module      : Otto.Catalog.FileSystem
-- Description : Filesystem-backed implementation of 'Catalog'.
--
-- Layout under 'catalogDir':
--
-- @
-- \<dir\>\/\<slug\>.md       -- one Markdown file per saved 'CrawlResult'
-- \<dir\>\/.failures.jsonl   -- append-only crawl failure log
-- @
--
-- Save is idempotent on the URL: 'urlSlug' is deterministic, so
-- re-saving the same URL overwrites the existing file. The directory
-- is created on demand for both operations so the caller never has
-- to pre-provision it.
module Otto.Catalog.FileSystem
  ( mkFsCatalog,
  )
where

import Control.Exception (IOException, try)
import Data.ByteString qualified as BS
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TE
import Data.Time.Clock (getCurrentTime)
import Otto.Catalog.Config (CatalogConfig (..))
import Otto.Catalog.Error (CatalogError (..))
import Otto.Catalog.Handle (Catalog (..))
import Otto.Catalog.Render (renderEntry, renderFailureLine)
import Otto.Catalog.Types
  ( CatalogEntry (..),
    CatalogName (FileSystem),
    FailureRecord,
    Slug (..),
    urlSlug,
  )
import Otto.Crawler.Types (CrawlResult (..))
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((<.>), (</>))

-- | Build a filesystem-backed 'Catalog' from a 'CatalogConfig'.
mkFsCatalog :: CatalogConfig -> Catalog
mkFsCatalog cfg =
  Catalog
    { cName = FileSystem,
      cSave = saveImpl cfg,
      cRecordFailure = recordFailureImpl cfg
    }

saveImpl :: CatalogConfig -> CrawlResult -> IO (Either CatalogError CatalogEntry)
saveImpl cfg res = do
  let dir = catalogDir cfg
      slug = urlSlug (crawledUrl res)
      path = dir </> Text.unpack (unSlug slug) <.> "md"
      rendered = renderEntry res
  result <- try @IOException $ do
    createDirectoryIfMissing True dir
    BS.writeFile path (TE.encodeUtf8 rendered)
  pure $ case result of
    Left exn -> Left (CatalogIOError FileSystem path exn)
    Right () ->
      Right
        CatalogEntry
          { entryPath = path,
            entrySlug = slug,
            entrySourceUrl = crawledUrl res,
            entryRendered = rendered
          }

recordFailureImpl :: CatalogConfig -> FailureRecord -> IO (Either CatalogError ())
recordFailureImpl cfg fr = do
  let dir = catalogDir cfg
      path = dir </> ".failures.jsonl"
  ts <- getCurrentTime
  let line = renderFailureLine ts fr <> "\n"
  result <- try @IOException $ do
    createDirectoryIfMissing True dir
    BS.appendFile path (TE.encodeUtf8 line)
  pure $ case result of
    Left exn -> Left (CatalogIOError FileSystem path exn)
    Right () -> Right ()
