-- |
-- Module      : Otto.Sources.Config
-- Description : Environment-driven configuration for the sources
-- registry.
--
-- The sources registry is a single YAML file on disk. The config
-- carries its path; the loader in "Otto.Sources.File" reads and
-- decodes it.
module Otto.Sources.Config
  ( SourcesConfig (..),
    loadSourcesConfigFromEnv,
    defaultSourcesPath,
  )
where

import Data.Maybe (fromMaybe)
import System.Environment (lookupEnv)

-- | Aggregated sources configuration. A single field today; future
-- options (e.g. include/exclude topics) extend this record.
newtype SourcesConfig = SourcesConfig
  { -- | Path to the YAML file holding the registry of topics and
    -- seed feeds.
    sourcesPath :: FilePath
  }
  deriving stock (Eq, Show)

-- | Default sources file path (@./config/sources.yaml@).
defaultSourcesPath :: FilePath
defaultSourcesPath = "config/sources.yaml"

-- | Read sources configuration from environment variables.
--
-- * @OTTO_SOURCES_PATH@ — path to the YAML registry. Defaults to
--   'defaultSourcesPath'.
loadSourcesConfigFromEnv :: IO SourcesConfig
loadSourcesConfigFromEnv = do
  mPath <- lookupEnv "OTTO_SOURCES_PATH"
  pure SourcesConfig {sourcesPath = fromMaybe defaultSourcesPath mPath}
