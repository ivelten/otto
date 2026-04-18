-- |
-- Module      : Otto.AI
-- Description : Public high-level AI API — types, provider abstraction,
-- configuration, and the provider factory.
--
-- This is the module most callers should import. It re-exports the
-- vendor-neutral value types, the provider abstraction (including the
-- 'HasAI' class and the 'generate' / 'runAsk' helpers), configuration
-- types, and the 'ProviderError' type — and provides 'buildProvider',
-- the factory that turns an 'AIConfig' plus a 'PreferredProvider' into
-- a concrete 'Provider'.
--
-- Provider implementations ('Otto.AI.Anthropic', 'Otto.AI.Mock',
-- 'Otto.AI.Gemini') and the low-level wire-format internals
-- ('Otto.AI.Anthropic.Internal', 'Otto.AI.Gemini.Internal') are
-- intentionally /not/ re-exported — importers bring them in explicitly
-- when they need to construct a provider directly or inspect raw JSON.
module Otto.AI
  ( module Otto.AI.Types,
    module Otto.AI.Error,
    module Otto.AI.Provider,
    module Otto.AI.Config,
    buildProvider,
  )
where

import Network.HTTP.Client (Manager)
import Otto.AI.Anthropic (mkAnthropicProvider)
import Otto.AI.Config
import Otto.AI.Error
import Otto.AI.Gemini (mkGeminiProvider)
import Otto.AI.Provider
import Otto.AI.Types

-- | Build a concrete 'Provider' from the application's AI configuration
-- and the preferred provider for this call.
--
-- When the preferred provider is not configured (no API key), the
-- returned value is 'disabledProvider' — the application still runs,
-- but any attempt to invoke the provider surfaces a clear
-- 'ProviderMisconfigured' error instead of a runtime crash.
--
-- The 'Manager' is passed through to the concrete implementation so
-- connection pools and TLS sessions are shared across callers.
buildProvider :: Manager -> AIConfig -> PreferredProvider -> Provider
buildProvider manager cfg = \case
  PreferAnthropic -> case acAnthropic cfg of
    Just anthropic -> mkAnthropicProvider manager anthropic
    Nothing -> disabledProvider Anthropic "OTTO_ANTHROPIC_API_KEY is not set"
  PreferGemini -> case acGemini cfg of
    Just gemini -> mkGeminiProvider manager gemini
    Nothing -> disabledProvider Gemini "OTTO_GEMINI_API_KEY is not set"
