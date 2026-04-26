-- |
-- Module      : Otto.Catalog.Handle
-- Description : The catalog abstraction.
--
-- A 'Catalog' is a value — a record of functions — not a typeclass,
-- mirroring 'Otto.Crawler.Handle.Crawler' and
-- 'Otto.AI.Provider.Provider'. Callers reach the configured catalog
-- via the 'HasCatalog' class on the application environment, and run
-- operations through the 'save' / 'recordFailure' helpers.
module Otto.Catalog.Handle
  ( Catalog (..),
    HasCatalog (..),
    save,
    recordFailure,
    disabledCatalog,
  )
where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (MonadReader, asks)
import Data.Text (Text)
import Otto.Catalog.Error (CatalogError (..))
import Otto.Catalog.Types
  ( CatalogEntry,
    CatalogName,
    FailureRecord,
  )
import Otto.Crawler.Types (CrawlResult)

-- | A catalog implementation, held as a first-class value.
--
-- Both actions run in plain 'IO' (not 'App') so catalogs can be
-- called from any 'MonadIO' context and tests can exercise them
-- without building an application environment.
data Catalog = Catalog
  { cName :: CatalogName,
    -- | Persist a successful 'CrawlResult'. The implementation
    -- decides the storage format (filesystem today). Idempotent on
    -- the URL: re-saving the same URL overwrites the prior entry.
    cSave :: CrawlResult -> IO (Either CatalogError CatalogEntry),
    -- | Append a 'FailureRecord' to the failure log. The
    -- implementation supplies the timestamp.
    cRecordFailure :: FailureRecord -> IO (Either CatalogError ())
  }

-- | Environments that expose a 'Catalog'.
class HasCatalog env where
  getCatalog :: env -> Catalog

-- | Persist a 'CrawlResult' through the configured catalog.
--
-- ==== __Example__
--
-- >>> save crawlResult
save ::
  (HasCatalog env, MonadReader env m, MonadIO m) =>
  CrawlResult ->
  m (Either CatalogError CatalogEntry)
save res = do
  catalog <- asks getCatalog
  liftIO (cSave catalog res)

-- | Record a crawl failure through the configured catalog.
--
-- ==== __Example__
--
-- >>> recordFailure failureRecord
recordFailure ::
  (HasCatalog env, MonadReader env m, MonadIO m) =>
  FailureRecord ->
  m (Either CatalogError ())
recordFailure fr = do
  catalog <- asks getCatalog
  liftIO (cRecordFailure catalog fr)

-- | A 'Catalog' that rejects every operation with
-- 'CatalogMisconfigured'.
--
-- Useful as a fallback when no backend can be configured: the
-- application still boots and non-catalog work proceeds, but any
-- save attempt surfaces a clear configuration error.
disabledCatalog :: CatalogName -> Text -> Catalog
disabledCatalog name reason =
  Catalog
    { cName = name,
      cSave = \_ -> pure (Left (CatalogMisconfigured name reason)),
      cRecordFailure = \_ -> pure (Left (CatalogMisconfigured name reason))
    }
