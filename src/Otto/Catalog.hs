-- |
-- Module      : Otto.Catalog
-- Description : Public high-level catalog API — types, abstraction,
-- configuration, errors, and the catalog factory.
--
-- Most callers should import this module. It re-exports the
-- vendor-neutral value types, the 'Catalog' abstraction (including
-- the 'HasCatalog' class and the 'save' / 'recordFailure' helpers),
-- configuration, and the 'CatalogError' type. It also exposes
-- 'buildCatalog' — the factory that turns a 'CatalogConfig' into a
-- concrete 'Catalog' — and 'crawlerErrorToFailure', the canonical
-- conversion from a 'CrawlerError' into a 'FailureRecord' ready for
-- the failure log.
--
-- Concrete implementations ('Otto.Catalog.FileSystem') and the pure
-- renderer ('Otto.Catalog.Render') are intentionally /not/
-- re-exported — importers bring them in explicitly when they need to
-- construct a catalog directly or inspect the canonical wire format.
module Otto.Catalog
  ( module Otto.Catalog.Types,
    module Otto.Catalog.Error,
    module Otto.Catalog.Handle,
    module Otto.Catalog.Config,
    buildCatalog,
    crawlerErrorToFailure,
  )
where

import Data.Text qualified as Text
import Otto.Catalog.Config
import Otto.Catalog.Error
import Otto.Catalog.FileSystem (mkFsCatalog)
import Otto.Catalog.Handle
import Otto.Catalog.Types
import Otto.Crawler.Error (CrawlerError (..))
import Otto.Crawler.Types (URL)

-- | Build the configured 'Catalog' from the application's catalog
-- configuration. Today this always returns a filesystem catalog;
-- when a second backend (PostgreSQL, S3, …) is added, this function
-- learns to pick between them.
buildCatalog :: CatalogConfig -> Catalog
buildCatalog = mkFsCatalog

-- | Canonical conversion from a 'CrawlerError' to a 'FailureRecord'
-- suitable for the failure log. The original target URL is passed
-- explicitly because not every 'CrawlerError' carries it.
--
-- The error class is a short, stable, snake_case tag so the log is
-- easy to aggregate ('jq', @cut@, …); the human-readable rendering
-- of the error goes into 'frMessage'.
crawlerErrorToFailure :: URL -> CrawlerError -> FailureRecord
crawlerErrorToFailure url err =
  FailureRecord
    { frUrl = url,
      frErrorClass = errorClass err,
      frMessage = Text.pack (show err)
    }
  where
    errorClass = \case
      CrawlerNetworkError {} -> "network_error"
      CrawlerHttpError {} -> "http_error"
      CrawlerBlocked {} -> "blocked"
      CrawlerDecodeError {} -> "decode_error"
      CrawlerAuthError {} -> "auth_error"
      CrawlerRateLimitError {} -> "rate_limited"
      CrawlerMisconfigured {} -> "misconfigured"
