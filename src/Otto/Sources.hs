-- |
-- Module      : Otto.Sources
-- Description : Public high-level sources API — types, configuration,
-- errors, and the YAML loader.
--
-- Most callers should import this module. It re-exports the
-- vendor-neutral value types ('Source', 'Topic'), the configuration
-- (path of the YAML file), the 'SourcesError' type, and 'loadSources'
-- — the IO action that reads and decodes the registry.
--
-- The wire format lives in @config/sources.yaml@. See
-- "Otto.Sources.Types" for the schema.
module Otto.Sources
  ( module Otto.Sources.Types,
    module Otto.Sources.Config,
    module Otto.Sources.Error,
    loadSources,
  )
where

import Otto.Sources.Config
import Otto.Sources.Error
import Otto.Sources.File (loadSources)
import Otto.Sources.Types
