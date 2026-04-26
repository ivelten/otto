-- |
-- Module      : Otto.Sources.Types
-- Description : Vendor-neutral value types for research sources.
--
-- A 'Source' pairs a free-form 'Topic' label with a list of seed URLs
-- (RSS / Atom feeds today). The shape mirrors the on-disk YAML
-- format described in @config/sources.yaml@; the 'FromJSON' instances
-- are written to that shape directly.
--
-- Topics are stable identifiers that flow through to the catalog and
-- the draft generator — keep them snake-case-ish, no spaces.
module Otto.Sources.Types
  ( Topic (..),
    Source (..),
    SourcesFile (..),
  )
where

import Data.Aeson (FromJSON (..), withObject, (.:))
import Data.String (IsString)
import Data.Text (Text)
import Otto.Crawler.Types (URL (..))

-- | A free-form topic label. Maps to a blog category.
newtype Topic = Topic {unTopic :: Text}
  deriving stock (Eq, Show)
  deriving newtype (IsString)

-- | One topic and the seed URLs that feed it.
data Source = Source
  { sourceTopic :: Topic,
    sourceSeeds :: [URL]
  }
  deriving stock (Eq, Show)

-- | The top-level shape of @config/sources.yaml@: a single @sources@
-- key holding the list of 'Source' entries. Surfacing this as a named
-- type (rather than decoding to @[Source]@ directly) keeps the YAML
-- file extensible — new top-level keys won't force a breaking change
-- in existing decoders.
newtype SourcesFile = SourcesFile {sfSources :: [Source]}
  deriving stock (Eq, Show)

instance FromJSON Topic where
  parseJSON v = Topic <$> parseJSON v

instance FromJSON Source where
  parseJSON = withObject "Source" $ \o -> do
    topic <- o .: "topic"
    seeds <- o .: "seeds"
    pure
      Source
        { sourceTopic = topic,
          sourceSeeds = URL <$> seeds
        }

instance FromJSON SourcesFile where
  parseJSON = withObject "SourcesFile" $ \o -> do
    srcs <- o .: "sources"
    pure SourcesFile {sfSources = srcs}
