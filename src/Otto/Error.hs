-- |
-- Module      : Otto.Error
-- Description : Top-level error type for Otto.
--
-- 'OttoError' is a closed union of per-module error sum types. As each module
-- (crawler, AI provider, database, …) is added, it contributes its own error
-- type and a constructor here. Callers then pattern-match on 'OttoError'
-- without losing specificity.
--
-- Every constructor's 'Show' instance renders a human-readable message ready
-- for logging or printing — no extra formatting layer is needed at call sites.
--
-- The type currently has no constructors: they are introduced on demand, never
-- speculatively.
module Otto.Error
  ( OttoError,
  )
where

-- | Top-level error type. Grows as modules are added.
data OttoError
  deriving stock (Show)
