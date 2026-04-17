-- |
-- Module      : Otto.AI.Config
-- Description : Environment-driven configuration for AI providers.
--
-- Each provider's configuration is read from environment variables at
-- bootstrap. A provider is considered enabled only when its API key is
-- present; otherwise the corresponding field in 'AIConfig' is 'Nothing' and
-- the application continues without it (see 'Otto.AI.Provider.disabledProvider'
-- for the default fallback).
module Otto.AI.Config
  ( AIConfig (..),
    AnthropicConfig (..),
    loadAIConfigFromEnv,
    defaultAnthropicBaseUrl,
    defaultAnthropicModel,
  )
where

import Data.Functor ((<&>))
import Data.Text (Text)
import Data.Text qualified as Text
import Otto.AI.Types (ModelId (..))
import System.Environment (lookupEnv)

-- | Top-level AI configuration.
--
-- Fields are optional: a 'Nothing' means the corresponding provider is not
-- configured and cannot be used. New providers extend this record with
-- additional @Maybe FooConfig@ fields.
data AIConfig = AIConfig
  { acAnthropic :: Maybe AnthropicConfig
  }
  deriving stock (Eq, Show)

-- | Configuration for the Anthropic provider.
data AnthropicConfig = AnthropicConfig
  { anthropicApiKey :: Text,
    anthropicBaseUrl :: Text,
    anthropicDefaultModel :: ModelId
  }
  deriving stock (Eq, Show)

-- | Default base URL for the Anthropic API.
defaultAnthropicBaseUrl :: Text
defaultAnthropicBaseUrl = "https://api.anthropic.com"

-- | Default model used when @OTTO_ANTHROPIC_DEFAULT_MODEL@ is not set.
defaultAnthropicModel :: ModelId
defaultAnthropicModel = ModelId "claude-sonnet-4-6"

-- | Read AI configuration from environment variables.
--
-- Anthropic is enabled when @OTTO_ANTHROPIC_API_KEY@ is set. @BASE_URL@ and
-- @DEFAULT_MODEL@ fall back to 'defaultAnthropicBaseUrl' and
-- 'defaultAnthropicModel' respectively.
loadAIConfigFromEnv :: IO AIConfig
loadAIConfigFromEnv = do
  mKey <- lookupEnv "OTTO_ANTHROPIC_API_KEY"
  mBase <- lookupEnv "OTTO_ANTHROPIC_BASE_URL"
  mModel <- lookupEnv "OTTO_ANTHROPIC_DEFAULT_MODEL"
  let anthropic =
        mKey <&> \key ->
          AnthropicConfig
            { anthropicApiKey = Text.pack key,
              anthropicBaseUrl = maybe defaultAnthropicBaseUrl Text.pack mBase,
              anthropicDefaultModel =
                maybe defaultAnthropicModel (ModelId . Text.pack) mModel
            }
  pure AIConfig {acAnthropic = anthropic}
