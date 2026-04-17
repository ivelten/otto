-- |
-- Module      : Otto.AI
-- Description : Umbrella module re-exporting Otto's AI abstraction.
--
-- This is the module most callers should import. It re-exports the
-- vendor-neutral value types, the provider abstraction (including the
-- 'HasAI' class and the 'generate' / 'runAsk' helpers), the configuration
-- types, and the 'ProviderError' type.
--
-- Provider implementations ('Otto.AI.Anthropic', 'Otto.AI.Mock') and the
-- low-level wire-format internals ('Otto.AI.Anthropic.Internal') are
-- intentionally /not/ re-exported — importers bring them in explicitly when
-- they need to construct a provider or inspect raw JSON.
module Otto.AI
  ( module Otto.AI.Types,
    module Otto.AI.Error,
    module Otto.AI.Provider,
    module Otto.AI.Config,
  )
where

import Otto.AI.Config
import Otto.AI.Error
import Otto.AI.Provider
import Otto.AI.Types
