-- |
-- Module      : Otto.Catalog.Config
-- Description : Environment-driven configuration for the catalog.
--
-- Today the catalog is filesystem-backed, parameterized by a single
-- directory. Future backends (PostgreSQL, S3, …) will extend this
-- record with their own fields without breaking existing callers.
module Otto.Catalog.Config
  ( CatalogConfig (..),
    loadCatalogConfigFromEnv,
    defaultCatalogDir,
  )
where

import Data.Maybe (fromMaybe)
import System.Environment (lookupEnv)

-- | Aggregated catalog configuration. A single field today, more
-- when additional backends arrive.
newtype CatalogConfig = CatalogConfig
  { -- | Root directory under which the filesystem catalog writes
    -- entries (@<dir>/<slug>.md@) and the failure log
    -- (@<dir>/.failures.jsonl@).
    catalogDir :: FilePath
  }
  deriving stock (Eq, Show)

-- | Default catalog directory ('@./catalog/@').
defaultCatalogDir :: FilePath
defaultCatalogDir = "catalog"

-- | Read catalog configuration from environment variables.
--
-- * @OTTO_CATALOG_DIR@ — root directory for the catalog. Defaults to
--   'defaultCatalogDir'.
loadCatalogConfigFromEnv :: IO CatalogConfig
loadCatalogConfigFromEnv = do
  mDir <- lookupEnv "OTTO_CATALOG_DIR"
  pure CatalogConfig {catalogDir = fromMaybe defaultCatalogDir mDir}
