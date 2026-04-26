-- |
-- Module      : Otto.Catalog.Error
-- Description : Typed errors raised by catalog implementations.
--
-- 'CatalogError' is the single error type every catalog backend
-- returns. The constructors cover the failure modes that matter to
-- callers: filesystem trouble (wrapped 'IOException') and
-- misconfiguration. JSON encoding errors do not appear because the
-- catalog never decodes user input — it only writes.
--
-- The 'Show' instance is hand-written so messages are ready to print
-- or log directly. The 'IOException' is rendered via its own 'Show'
-- which is already readable.
module Otto.Catalog.Error
  ( CatalogError (..),
  )
where

import Control.Exception (IOException)
import Data.Text (Text)
import Data.Text qualified as Text
import Otto.Catalog.Types (CatalogName)

-- | Errors raised by any catalog implementation.
data CatalogError
  = -- | Filesystem read/write failed. Carries the offending path and
    -- the underlying exception.
    CatalogIOError CatalogName FilePath IOException
  | -- | Catalog cannot be used: required invariant violated by the
    -- caller, backend not reachable, etc.
    CatalogMisconfigured CatalogName Text

-- | Hand-written 'Show' so error messages are directly printable /
-- loggable.
instance Show CatalogError where
  show = \case
    CatalogIOError name path exn ->
      prefix name "I/O error at " <> path <> ": " <> show exn
    CatalogMisconfigured name msg ->
      prefix name "misconfigured: " <> Text.unpack msg

prefix :: CatalogName -> String -> String
prefix name tag = "[" <> show name <> "] " <> tag
