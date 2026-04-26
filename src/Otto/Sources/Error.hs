-- |
-- Module      : Otto.Sources.Error
-- Description : Typed errors for sources loading.
--
-- The sources registry is a YAML file on disk. The two failure modes
-- a caller cares about are: the file is unreadable (missing,
-- permission, …) or the file is unparseable. Both carry the path so
-- diagnostics point at the right thing.
module Otto.Sources.Error
  ( SourcesError (..),
  )
where

import Control.Exception (IOException)
import Data.Text (Text)
import Data.Text qualified as Text

-- | Errors raised while loading the sources registry.
data SourcesError
  = -- | Reading the YAML file failed (missing, permission denied, …).
    SourcesIOError FilePath IOException
  | -- | The YAML file was read but could not be parsed into a list
    -- of 'Otto.Sources.Types.Source'.
    SourcesParseError FilePath Text

-- | Hand-written 'Show' so error messages are directly printable /
-- loggable.
instance Show SourcesError where
  show = \case
    SourcesIOError path exn ->
      "[Sources] I/O error reading " <> path <> ": " <> show exn
    SourcesParseError path msg ->
      "[Sources] parse error in " <> path <> ": " <> Text.unpack msg
