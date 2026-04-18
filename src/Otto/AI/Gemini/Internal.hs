-- |
-- Module      : Otto.AI.Gemini.Internal
-- Description : Pure request-body builder and response decoder for Gemini.
--
-- Translates between Otto's vendor-neutral types (in "Otto.AI.Types") and
-- Google's Generative Language API @generateContent@ wire format. Split
-- from "Otto.AI.Gemini" so tests can pin the JSON shape without touching
-- the network.
--
-- Key differences from Anthropic that this module hides from callers:
--
-- * Assistant turns use @role: "model"@, not @"assistant"@.
-- * Messages are wrapped in @contents[].parts[].text@ instead of a flat
--   string body.
-- * The system prompt goes into @systemInstruction.parts@ rather than a
--   top-level @system@ field.
-- * @maxOutputTokens@ / @temperature@ live under @generationConfig@.
-- * Finish reasons are SCREAMING_SNAKE_CASE (@STOP@, @MAX_TOKENS@, …).
module Otto.AI.Gemini.Internal
  ( buildRequestBody,
    decodeResponseBody,
    decodeErrorMessage,
    translateFinishReason,
  )
where

import Data.Aeson (FromJSON (..), withObject, (.:), (.:?))
import Data.Aeson qualified as Aeson
import Data.Aeson.Encoding qualified as AE
import Data.ByteString.Lazy (ByteString)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Otto.AI.Config (GeminiConfig)
import Otto.AI.Error (ProviderError (..))
import Otto.AI.Types
  ( FinishReason (..),
    Message (..),
    ModelId (..),
    ProviderName (Gemini),
    Request (..),
    Response (..),
    Role (..),
    Usage (..),
  )

-- | Serialize a vendor-neutral 'Request' into the JSON body Gemini's
-- @generateContent@ endpoint expects. The target model is part of the
-- URL (see "Otto.AI.Gemini"), not the body, so 'reqModel' is not
-- encoded here.
--
-- Fails fast with 'ProviderMisconfigured' if the caller places a 'System'
-- role into 'reqMessages': Gemini has a dedicated @systemInstruction@
-- field and silently remapping would mask a caller bug.
buildRequestBody :: GeminiConfig -> Request -> Either ProviderError ByteString
buildRequestBody _cfg req
  | any ((== System) . msgRole) (reqMessages req) =
      Left
        ( ProviderMisconfigured
            Gemini
            "System role must be set via reqSystem, not included in reqMessages"
        )
  | otherwise = Right (AE.encodingToLazyByteString (encodeRequest req))

encodeRequest :: Request -> Aeson.Encoding
encodeRequest req =
  AE.pairs $
    mconcat
      [ maybe mempty (AE.pair "systemInstruction" . encodeSystemInstruction) (reqSystem req),
        AE.pair "contents" (AE.list encodeMessage (reqMessages req)),
        AE.pair "generationConfig" (encodeGenerationConfig req)
      ]

encodeSystemInstruction :: Text -> Aeson.Encoding
encodeSystemInstruction text =
  AE.pairs $ AE.pair "parts" (AE.list encodeTextPart [text])

encodeTextPart :: Text -> Aeson.Encoding
encodeTextPart text = AE.pairs $ AE.pair "text" (AE.text text)

encodeMessage :: Message -> Aeson.Encoding
encodeMessage m =
  AE.pairs $
    AE.pair "role" (AE.text (roleToWire (msgRole m)))
      <> AE.pair "parts" (AE.list encodeTextPart [msgContent m])

encodeGenerationConfig :: Request -> Aeson.Encoding
encodeGenerationConfig req =
  AE.pairs $
    AE.pair "maxOutputTokens" (AE.int (reqMaxTokens req))
      <> maybe mempty (AE.pair "temperature" . AE.double) (reqTemperature req)

roleToWire :: Role -> Text
roleToWire = \case
  User -> "user"
  Assistant -> "model"
  System -> "system" -- rejected in buildRequestBody

-- | Decode a Gemini @generateContent@ success body into a vendor-neutral
-- 'Response'. Non-text parts (inline data, function calls, …) are
-- rejected with 'ProviderDecodeError' until multi-modal output is
-- supported.
decodeResponseBody :: ByteString -> Either ProviderError Response
decodeResponseBody body = case Aeson.eitherDecode body of
  Left err -> Left (ProviderDecodeError Gemini (Text.pack err) body)
  Right wresp -> fromWireResponse body wresp

fromWireResponse :: ByteString -> WireResponse -> Either ProviderError Response
fromWireResponse body wresp = do
  candidate <- takeFirstCandidate body (wrespCandidates wresp)
  textOut <- extractText body (wcParts (wcContent candidate))
  pure
    Response
      { respText = textOut,
        respModel = ModelId (wrespModelVersion wresp),
        respFinishReason = translateFinishReason (wcFinishReason candidate),
        respUsage =
          Usage
            { usageInputTokens = wumPromptTokenCount (wrespUsageMetadata wresp),
              usageOutputTokens = wumCandidatesTokenCount (wrespUsageMetadata wresp)
            }
      }

takeFirstCandidate ::
  ByteString -> [WireCandidate] -> Either ProviderError WireCandidate
takeFirstCandidate body = \case
  [] -> Left (ProviderDecodeError Gemini "no candidates in response" body)
  (c : _) -> Right c

extractText :: ByteString -> [WirePart] -> Either ProviderError Text
extractText body parts =
  if any isOther parts
    then
      Left
        ( ProviderDecodeError
            Gemini
            "unsupported non-text part in candidate content"
            body
        )
    else Right (Text.concat [t | WirePartText t <- parts])
  where
    isOther WirePartOther = True
    isOther _ = False

-- | Map Gemini's @finishReason@ (or its absence) into 'FinishReason'.
-- Unknown reasons are preserved under 'StopOther' rather than silently
-- collapsed.
translateFinishReason :: Maybe Text -> FinishReason
translateFinishReason = \case
  Nothing -> StopOther "<missing>"
  Just "STOP" -> StopEndTurn
  Just "MAX_TOKENS" -> StopMaxTokens
  Just "STOP_SEQUENCE" -> StopSequence
  Just other -> StopOther other

-- | Best-effort extraction of a human-readable message from a Gemini
-- error response body. Google's error shape (@error.message@) matches
-- Anthropic's, but the decoder is kept per-provider to avoid coupling.
decodeErrorMessage :: ByteString -> Text
decodeErrorMessage body =
  fromMaybe "unparseable error body" $
    case Aeson.eitherDecode body of
      Left _ -> Nothing
      Right we -> Just (weMessage we)

-- Wire types — kept private to this module.

data WireResponse = WireResponse
  { wrespCandidates :: [WireCandidate],
    wrespUsageMetadata :: WireUsageMetadata,
    wrespModelVersion :: Text
  }

data WireCandidate = WireCandidate
  { wcContent :: WireContent,
    wcFinishReason :: Maybe Text
  }

newtype WireContent = WireContent {wcParts :: [WirePart]}

data WirePart = WirePartText Text | WirePartOther

data WireUsageMetadata = WireUsageMetadata
  { wumPromptTokenCount :: Int,
    wumCandidatesTokenCount :: Int
  }

newtype WireError = WireError {weMessage :: Text}

instance FromJSON WireResponse where
  parseJSON = withObject "GeminiResponse" $ \o ->
    WireResponse
      <$> o .: "candidates"
      <*> o .: "usageMetadata"
      <*> o .: "modelVersion"

instance FromJSON WireCandidate where
  parseJSON = withObject "GeminiCandidate" $ \o ->
    WireCandidate
      <$> o .: "content"
      <*> o .:? "finishReason"

instance FromJSON WireContent where
  parseJSON = withObject "GeminiContent" $ \o ->
    WireContent <$> o .: "parts"

instance FromJSON WirePart where
  parseJSON = withObject "GeminiPart" $ \o -> do
    mText <- o .:? "text"
    pure $ case mText of
      Just t -> WirePartText t
      Nothing -> WirePartOther

instance FromJSON WireUsageMetadata where
  parseJSON = withObject "GeminiUsageMetadata" $ \o ->
    WireUsageMetadata
      <$> o .: "promptTokenCount"
      <*> o .: "candidatesTokenCount"

instance FromJSON WireError where
  parseJSON = withObject "GeminiError" $ \o -> do
    errObj <- o .: "error"
    WireError <$> errObj .: "message"
