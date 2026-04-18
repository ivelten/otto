-- |
-- Module      : Otto.AI.Config
-- Description : AI provider configuration and runtime provider selection.
--
-- This module owns two adjacent concerns:
--
-- * /Configuration:/ per-provider records ('AnthropicConfig',
--   'GeminiConfig') aggregated into 'AIConfig', and the environment
--   loader 'loadAIConfigFromEnv'. A provider is considered enabled only
--   when its API key is present; otherwise the corresponding field is
--   'Nothing' and the application continues without it.
--
-- * /Provider preference:/ the 'PreferredProvider' tag that indicates
--   which provider the runtime should use for a given call, its parser,
--   the @OTTO_PROVIDER@ environment reader, and the pure
--   'defaultModelFor' lookup.
--
-- The two live together because the CLI parser and the executable both
-- need the same preference logic, and duplicating the preference type
-- between @Otto.AI.Cli@ and a config module would be awkward.
module Otto.AI.Config
  ( -- * Configuration types
    AIConfig (..),
    AnthropicConfig (..),
    GeminiConfig (..),

    -- * Provider preference
    PreferredProvider (..),
    parseProviderName,
    defaultModelFor,

    -- * Environment loaders
    loadAIConfigFromEnv,
    loadPreferredProviderEnv,

    -- * Defaults
    defaultAnthropicBaseUrl,
    defaultAnthropicModel,
    defaultGeminiBaseUrl,
    defaultGeminiModel,
  )
where

import Data.Char (toLower)
import Data.Functor ((<&>))
import Data.Text (Text)
import Data.Text qualified as Text
import Otto.AI.Types (ModelId (..))
import System.Environment (lookupEnv)

-- | Top-level AI configuration.
--
-- Fields are optional: a 'Nothing' means the corresponding provider is
-- not configured and cannot be used. New providers extend this record
-- with additional @Maybe FooConfig@ fields.
data AIConfig = AIConfig
  { acAnthropic :: Maybe AnthropicConfig,
    acGemini :: Maybe GeminiConfig
  }
  deriving stock (Eq, Show)

-- | Configuration for the Anthropic provider.
data AnthropicConfig = AnthropicConfig
  { anthropicApiKey :: Text,
    anthropicBaseUrl :: Text,
    anthropicDefaultModel :: ModelId
  }
  deriving stock (Eq, Show)

-- | Configuration for the Gemini (Google Generative Language API)
-- provider.
data GeminiConfig = GeminiConfig
  { geminiApiKey :: Text,
    geminiBaseUrl :: Text,
    geminiDefaultModel :: ModelId
  }
  deriving stock (Eq, Show)

-- | Which provider the runtime should use for a given call. Set by a
-- command-line flag or by the @OTTO_PROVIDER@ environment variable (see
-- 'loadPreferredProviderEnv' and "Otto.AI.Cli.parseAskArgs"), resolved
-- at the entry-point layer.
data PreferredProvider
  = PreferAnthropic
  | PreferGemini
  deriving stock (Eq, Show)

-- | Default base URL for the Anthropic API.
defaultAnthropicBaseUrl :: Text
defaultAnthropicBaseUrl = "https://api.anthropic.com"

-- | Default model used when @OTTO_ANTHROPIC_DEFAULT_MODEL@ is not set.
defaultAnthropicModel :: ModelId
defaultAnthropicModel = ModelId "claude-sonnet-4-6"

-- | Default base URL for the Gemini API (Google AI Studio).
defaultGeminiBaseUrl :: Text
defaultGeminiBaseUrl = "https://generativelanguage.googleapis.com"

-- | Default model used when @OTTO_GEMINI_DEFAULT_MODEL@ is not set.
defaultGeminiModel :: ModelId
defaultGeminiModel = ModelId "gemini-2.5-pro"

-- | Parse a provider name (case-insensitive). 'Left' lists the accepted
-- values so error messages don't go stale when a provider is added.
--
-- ==== __Examples__
--
-- >>> parseProviderName "Anthropic"
-- Right PreferAnthropic
--
-- >>> parseProviderName "llama"
-- Left "unknown provider: 'llama' (expected: anthropic | gemini)"
parseProviderName :: String -> Either String PreferredProvider
parseProviderName name = case map toLower name of
  "anthropic" -> Right PreferAnthropic
  "gemini" -> Right PreferGemini
  other ->
    Left
      ("unknown provider: '" <> other <> "' (expected: anthropic | gemini)")

-- | Return the default model configured for the chosen provider, or
-- 'Nothing' when that provider is not configured in 'AIConfig'.
defaultModelFor :: AIConfig -> PreferredProvider -> Maybe ModelId
defaultModelFor cfg = \case
  PreferAnthropic -> fmap anthropicDefaultModel (acAnthropic cfg)
  PreferGemini -> fmap geminiDefaultModel (acGemini cfg)

-- | Read AI configuration from environment variables.
--
-- Each provider is enabled when its @*_API_KEY@ is set; unset keys
-- leave the corresponding field as 'Nothing'.
--
-- * Anthropic: @OTTO_ANTHROPIC_API_KEY@, optional
--   @OTTO_ANTHROPIC_BASE_URL@ and @OTTO_ANTHROPIC_DEFAULT_MODEL@.
-- * Gemini: @OTTO_GEMINI_API_KEY@, optional @OTTO_GEMINI_BASE_URL@ and
--   @OTTO_GEMINI_DEFAULT_MODEL@.
--
-- See 'loadPreferredProviderEnv' for the separate @OTTO_PROVIDER@
-- selection variable.
loadAIConfigFromEnv :: IO AIConfig
loadAIConfigFromEnv = do
  anthropic <- loadAnthropic
  gemini <- loadGemini
  pure AIConfig {acAnthropic = anthropic, acGemini = gemini}

loadAnthropic :: IO (Maybe AnthropicConfig)
loadAnthropic = do
  mKey <- lookupEnv "OTTO_ANTHROPIC_API_KEY"
  mBase <- lookupEnv "OTTO_ANTHROPIC_BASE_URL"
  mModel <- lookupEnv "OTTO_ANTHROPIC_DEFAULT_MODEL"
  pure $
    mKey <&> \key ->
      AnthropicConfig
        { anthropicApiKey = Text.pack key,
          anthropicBaseUrl = maybe defaultAnthropicBaseUrl Text.pack mBase,
          anthropicDefaultModel =
            maybe defaultAnthropicModel (ModelId . Text.pack) mModel
        }

loadGemini :: IO (Maybe GeminiConfig)
loadGemini = do
  mKey <- lookupEnv "OTTO_GEMINI_API_KEY"
  mBase <- lookupEnv "OTTO_GEMINI_BASE_URL"
  mModel <- lookupEnv "OTTO_GEMINI_DEFAULT_MODEL"
  pure $
    mKey <&> \key ->
      GeminiConfig
        { geminiApiKey = Text.pack key,
          geminiBaseUrl = maybe defaultGeminiBaseUrl Text.pack mBase,
          geminiDefaultModel =
            maybe defaultGeminiModel (ModelId . Text.pack) mModel
        }

-- | Read @OTTO_PROVIDER@ from the environment.
--
-- * 'Nothing' — the env variable is unset.
-- * 'Just' ('Right' p) — it is set to a recognized value.
-- * 'Just' ('Left' err) — it is set but the value is not recognized.
--
-- Callers decide how to fall back (with or without a user-visible
-- warning); this loader stays pure with respect to output.
loadPreferredProviderEnv :: IO (Maybe (Either String PreferredProvider))
loadPreferredProviderEnv = do
  mVal <- lookupEnv "OTTO_PROVIDER"
  pure (fmap parseProviderName mVal)
