-- |
-- Module      : Otto.AI.Provider
-- Description : The AI provider abstraction.
--
-- A 'Provider' is a value — a record of functions — not a typeclass. Storing
-- the provider as data means multiple providers can coexist in a running
-- application (e.g. one for drafting, another for summarization), be swapped
-- at runtime, and be replaced with a mock in tests by setting a field.
--
-- Callers reach the configured provider via the 'HasAI' class on the
-- application environment, mirroring how 'Colog.HasLog' exposes the logger.
-- The 'generate' helper runs a 'Request' against whatever provider is in
-- scope.
module Otto.AI.Provider
  ( Provider (..),
    HasAI (..),
    generate,
    runAsk,
    disabledProvider,
  )
where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (MonadReader, asks)
import Data.Text (Text)
import Otto.AI.Error (ProviderError (..))
import Otto.AI.Types
  ( Message (..),
    ModelId,
    ProviderName,
    Request (..),
    Response,
    Role (User),
  )

-- | A provider implementation, held as a first-class value.
--
-- The 'pGenerate' action runs in plain 'IO' (not 'App') so providers can be
-- called from any 'MonadIO' context and tests can exercise them without
-- building an application environment.
data Provider = Provider
  { pName :: ProviderName,
    pGenerate :: Request -> IO (Either ProviderError Response)
  }

-- | Environments that expose an AI 'Provider'.
class HasAI env where
  getAI :: env -> Provider

-- | Run a 'Request' through the configured provider.
--
-- ==== __Example__
--
-- >>> let req = Request (ModelId "claude-sonnet-4-6") Nothing [Message User "Hi"] 512 Nothing
-- >>> generate req
generate ::
  (HasAI env, MonadReader env m, MonadIO m) =>
  Request ->
  m (Either ProviderError Response)
generate req = do
  provider <- asks getAI
  liftIO (pGenerate provider req)

-- | Convenience wrapper for the common "one-shot prompt, one answer" pattern.
--
-- Builds a minimal 'Request' with a single 'User' message, the given model,
-- and @max_tokens = 1024@, then dispatches it through 'generate'.
--
-- ==== __Example__
--
-- >>> runAsk (ModelId "claude-sonnet-4-6") "What is a Haskell monad?"
runAsk ::
  (HasAI env, MonadReader env m, MonadIO m) =>
  ModelId ->
  Text ->
  m (Either ProviderError Response)
runAsk model prompt =
  generate
    Request
      { reqModel = model,
        reqSystem = Nothing,
        reqMessages = [Message {msgRole = User, msgContent = prompt}],
        reqMaxTokens = 1024,
        reqTemperature = Nothing
      }

-- | A 'Provider' that rejects every request with 'ProviderMisconfigured'.
--
-- Useful as the default provider when no API key is configured: the
-- application still boots and non-AI work proceeds normally, but any attempt
-- to call the provider surfaces a clear configuration error instead of a
-- runtime crash.
disabledProvider :: ProviderName -> Text -> Provider
disabledProvider name reason =
  Provider
    { pName = name,
      pGenerate = \_ -> pure (Left (ProviderMisconfigured name reason))
    }
