-- |
-- Module      : Otto.Error
-- Description : Top-level error type for Otto.
--
-- 'OttoError' is a closed union of per-module error sum types. Every
-- constructor wraps a module-local error (e.g. 'ProviderError' from
-- "Otto.AI.Error") so callers pattern-match on 'OttoError' without
-- losing specificity. As new modules are added, each contributes its
-- own error type and a constructor here — never speculatively.
--
-- Every constructor's 'Show' instance renders a human-readable
-- message ready for logging or printing; no additional formatting
-- layer is needed at call sites.
module Otto.Error
  ( OttoError (..),
  )
where

import Otto.AI.Error (ProviderError)
import Otto.Crawler.Error (CrawlerError)

-- | Top-level error type. Grows as modules are added.
data OttoError
  = -- | A failure surfaced by an AI provider (network, API, decode,
    -- auth, rate limit, or misconfiguration). See "Otto.AI.Error".
    AIError ProviderError
  | -- | A failure surfaced by a crawler implementation (network,
    -- blocked target, auth, rate limit, or misconfiguration). See
    -- "Otto.Crawler.Error".
    CrawlError CrawlerError
  deriving stock (Show)
