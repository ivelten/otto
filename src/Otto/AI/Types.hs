-- |
-- Module      : Otto.AI.Types
-- Description : Vendor-neutral value types for AI provider requests and responses.
--
-- These types describe a text-completion exchange in a way that maps cleanly
-- onto every major provider (Anthropic, OpenAI, Gemini, Deepseek, …) without
-- leaking any vendor's wire format. Each provider module is responsible for
-- translating its own JSON to and from these types.
--
-- The surface is intentionally minimal: one @Request@ shape for text-in/text-out
-- completion, a structured @Response@ with usage metrics, and a @FinishReason@
-- that preserves raw provider reasons under 'StopOther' so callers never silently
-- lose information.
--
-- Multi-modal content, tool use, and streaming are deliberately out of scope
-- for the current version; when added, @msgContent@ becomes a list of content
-- blocks and the wire types grow accordingly.
module Otto.AI.Types
  ( ModelId (..),
    Role (..),
    Message (..),
    Request (..),
    Response (..),
    FinishReason (..),
    Usage (..),
    ProviderName (..),
  )
where

import Data.String (IsString)
import Data.Text (Text)

-- | Provider-specific model identifier (e.g. @"claude-sonnet-4-6"@,
-- @"gemini-2.5-pro"@). Kept as a newtype over 'Text' because each vendor ships
-- new models continuously and an enum would be stale by design.
newtype ModelId = ModelId {unModelId :: Text}
  deriving stock (Eq, Show)
  deriving newtype (IsString)

-- | Role of a conversation turn.
--
-- 'System' carries instructions / persona and is represented here as a
-- distinct role, but the wire format depends on the provider: Anthropic takes
-- it in a dedicated @system@ field ('Request.reqSystem'), OpenAI / Gemini
-- accept it as a message with @role: "system"@. Providers reject 'System' in
-- 'Request.reqMessages' to keep the invariant explicit.
data Role = System | User | Assistant
  deriving stock (Eq, Show)

-- | A single conversation turn.
data Message = Message
  { msgRole :: Role,
    msgContent :: Text
  }
  deriving stock (Eq, Show)

-- | A text-completion request, normalized across providers.
--
-- 'reqSystem' is kept separate from 'reqMessages' because most providers
-- treat the system prompt as a distinct concept; callers that want to pass
-- a persona should set it here rather than prepending a @System@ message.
--
-- 'reqMaxTokens' has no 'Maybe' because Anthropic requires it and callers
-- should pick a deliberate ceiling; 'reqTemperature' is optional since
-- @Nothing@ means "use the provider default".
data Request = Request
  { reqModel :: ModelId,
    reqSystem :: Maybe Text,
    reqMessages :: [Message],
    reqMaxTokens :: Int,
    reqTemperature :: Maybe Double
  }
  deriving stock (Eq, Show)

-- | Reason a completion stopped.
--
-- 'StopOther' carries the raw provider-reported reason as 'Text' so that
-- unexpected stop reasons surface in logs rather than being silently
-- collapsed into 'StopEndTurn'.
data FinishReason
  = StopEndTurn
  | StopMaxTokens
  | StopSequence
  | StopOther Text
  deriving stock (Eq, Show)

-- | Token accounting for a single completion.
data Usage = Usage
  { usageInputTokens :: Int,
    usageOutputTokens :: Int
  }
  deriving stock (Eq, Show)

-- | A completion response.
--
-- 'respModel' is the model the provider actually used — this may differ from
-- 'Request.reqModel' when a provider routes an alias (e.g. @claude-opus-4@) to
-- a concrete dated version. Preserving the echoed model matters for logs and
-- cost accounting.
data Response = Response
  { respText :: Text,
    respModel :: ModelId,
    respFinishReason :: FinishReason,
    respUsage :: Usage
  }
  deriving stock (Eq, Show)

-- | Human-readable identifier for a provider implementation, used for
-- diagnostic output ('Show' of 'Otto.AI.Error.ProviderError' prefixes with
-- this).
data ProviderName
  = Anthropic
  | Gemini
  | OpenAI
  | Deepseek
  | Mock
  deriving stock (Eq, Show)
