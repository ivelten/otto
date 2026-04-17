-- |
-- Module      : Otto.AI.Anthropic.Internal
-- Description : Pure request-body builder and response decoder for Anthropic.
--
-- This module is the seam between Otto's vendor-neutral types
-- (in "Otto.AI.Types") and Anthropic's Messages API wire format. It is kept
-- separate from "Otto.AI.Anthropic" so tests can hit the pure functions
-- directly — no HTTP, no @Manager@, no environment — and pin the JSON shape
-- with golden fixtures.
--
-- The JSON is emitted via 'Data.Aeson.Encoding', which preserves field order
-- deterministically; golden-test diffs remain meaningful across runs.
module Otto.AI.Anthropic.Internal
  ( buildRequestBody,
    decodeResponseBody,
    decodeErrorMessage,
    translateStopReason,
  )
where

import Data.Aeson (FromJSON (..), withObject, (.:), (.:?))
import Data.Aeson qualified as Aeson
import Data.Aeson.Encoding qualified as AE
import Data.ByteString.Lazy (ByteString)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Otto.AI.Config (AnthropicConfig)
import Otto.AI.Error (ProviderError (..))
import Otto.AI.Types
  ( FinishReason (..),
    Message (..),
    ModelId (..),
    ProviderName (Anthropic),
    Request (..),
    Response (..),
    Role (..),
    Usage (..),
  )

-- | Serialize a vendor-neutral 'Request' into the JSON body Anthropic's
-- @POST /v1/messages@ expects.
--
-- Fails fast with 'ProviderMisconfigured' if the caller put a 'System' role
-- into 'reqMessages': Anthropic has a dedicated top-level @system@ field and
-- silently remapping would mask a logic error in the caller.
buildRequestBody :: AnthropicConfig -> Request -> Either ProviderError ByteString
buildRequestBody _cfg req
  | any ((== System) . msgRole) (reqMessages req) =
      Left
        ( ProviderMisconfigured
            Anthropic
            "System role must be set via reqSystem, not included in reqMessages"
        )
  | otherwise = Right (AE.encodingToLazyByteString (encodeRequest req))

encodeRequest :: Request -> Aeson.Encoding
encodeRequest req =
  AE.pairs $
    mconcat
      [ AE.pair "model" (AE.text (unModelId (reqModel req))),
        AE.pair "max_tokens" (AE.int (reqMaxTokens req)),
        maybe mempty (AE.pair "system" . AE.text) (reqSystem req),
        maybe mempty (AE.pair "temperature" . AE.double) (reqTemperature req),
        AE.pair "messages" (AE.list encodeMessage (reqMessages req))
      ]

encodeMessage :: Message -> Aeson.Encoding
encodeMessage m =
  AE.pairs $
    AE.pair "role" (AE.text (roleToWire (msgRole m)))
      <> AE.pair "content" (AE.text (msgContent m))

roleToWire :: Role -> Text
roleToWire = \case
  User -> "user"
  Assistant -> "assistant"
  System -> "system" -- rejected earlier in buildRequestBody

-- | Decode an Anthropic @/v1/messages@ successful response body into a
-- vendor-neutral 'Response'. Non-text content blocks are rejected with
-- 'ProviderDecodeError' until multi-modal output is supported.
decodeResponseBody :: ByteString -> Either ProviderError Response
decodeResponseBody body = case Aeson.eitherDecode body of
  Left err -> Left (ProviderDecodeError Anthropic (Text.pack err) body)
  Right wresp -> fromWireResponse body wresp

fromWireResponse :: ByteString -> WireResponse -> Either ProviderError Response
fromWireResponse body wresp = do
  text <- extractText body (wrespContent wresp)
  pure
    Response
      { respText = text,
        respModel = ModelId (wrespModel wresp),
        respFinishReason = translateStopReason (wrespStopReason wresp),
        respUsage =
          Usage
            { usageInputTokens = wuInput (wrespUsage wresp),
              usageOutputTokens = wuOutput (wrespUsage wresp)
            }
      }

extractText :: ByteString -> [WireContent] -> Either ProviderError Text
extractText body blocks =
  case [ty | WireContentOther ty <- blocks] of
    [] -> Right (Text.concat [t | WireContentText t <- blocks])
    (ty : _) ->
      Left
        ( ProviderDecodeError
            Anthropic
            ("unsupported content block type: " <> ty)
            body
        )

-- | Map Anthropic's @stop_reason@ (or its absence) into 'FinishReason'.
-- Unknown reasons are preserved under 'StopOther' rather than silently
-- collapsed to 'StopEndTurn'.
translateStopReason :: Maybe Text -> FinishReason
translateStopReason = \case
  Nothing -> StopOther "<missing>"
  Just "end_turn" -> StopEndTurn
  Just "max_tokens" -> StopMaxTokens
  Just "stop_sequence" -> StopSequence
  Just other -> StopOther other

-- | Best-effort extraction of a human-readable message from an Anthropic
-- error response body. Returns a placeholder if the body doesn't match the
-- documented error schema.
decodeErrorMessage :: ByteString -> Text
decodeErrorMessage body =
  fromMaybe "unparseable error body" $
    case Aeson.eitherDecode body of
      Left _ -> Nothing
      Right we -> Just (weMessage we)

-- Wire types — kept private to this module.

data WireResponse = WireResponse
  { wrespContent :: [WireContent],
    wrespModel :: Text,
    wrespStopReason :: Maybe Text,
    wrespUsage :: WireUsage
  }

data WireContent
  = WireContentText Text
  | WireContentOther Text

data WireUsage = WireUsage
  { wuInput :: Int,
    wuOutput :: Int
  }

newtype WireError = WireError {weMessage :: Text}

instance FromJSON WireResponse where
  parseJSON = withObject "AnthropicResponse" $ \o ->
    WireResponse
      <$> o .: "content"
      <*> o .: "model"
      <*> o .:? "stop_reason"
      <*> o .: "usage"

instance FromJSON WireContent where
  parseJSON = withObject "AnthropicContentBlock" $ \o -> do
    ty <- o .: "type"
    case (ty :: Text) of
      "text" -> WireContentText <$> o .: "text"
      other -> pure (WireContentOther other)

instance FromJSON WireUsage where
  parseJSON = withObject "AnthropicUsage" $ \o ->
    WireUsage
      <$> o .: "input_tokens"
      <*> o .: "output_tokens"

instance FromJSON WireError where
  parseJSON = withObject "AnthropicError" $ \o -> do
    errObj <- o .: "error"
    WireError <$> errObj .: "message"
