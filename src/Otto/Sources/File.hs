-- |
-- Module      : Otto.Sources.File
-- Description : YAML-backed loader for the sources registry.
--
-- The loader reads the file pointed at by the 'SourcesConfig', decodes
-- it via the 'FromJSON' instance on 'SourcesFile', and returns the
-- list of 'Source' entries. Both I/O failures and parse failures are
-- surfaced as 'SourcesError' values; exceptions are caught at the
-- boundary so the caller can run the loader inside an @Either@
-- pipeline without worrying about exception interleaving.
module Otto.Sources.File
  ( loadSources,
  )
where

import Control.Exception (IOException, try)
import Data.Text qualified as Text
import Data.Yaml qualified as Yaml
import Otto.Sources.Config (SourcesConfig (..))
import Otto.Sources.Error (SourcesError (..))
import Otto.Sources.Types (Source, SourcesFile (..))

-- | Load and decode the sources registry from disk.
--
-- ==== __Example__
--
-- >>> loadSources (SourcesConfig "config/sources.yaml")
-- Right [...]
loadSources :: SourcesConfig -> IO (Either SourcesError [Source])
loadSources cfg = do
  let path = sourcesPath cfg
  result <- try @IOException (Yaml.decodeFileEither path)
  pure $ case result of
    Left exn -> Left (SourcesIOError path exn)
    Right (Left parseExn) ->
      Left (SourcesParseError path (Text.pack (Yaml.prettyPrintParseException parseExn)))
    Right (Right (sf :: SourcesFile)) -> Right (sfSources sf)
