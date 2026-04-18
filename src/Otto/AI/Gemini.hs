-- |
-- Module      : Otto.AI.Gemini
-- Description : Gemini (Google Generative Language API) provider.
--
-- Speaks Google's @generateContent@ endpoint on the v1beta surface
-- (@POST /v1beta/models/{model}:generateContent@). Only handles the HTTP
-- flow — authentication, status-code mapping, exception wrapping — the
-- pure JSON builders and decoders live in "Otto.AI.Gemini.Internal".
--
-- Auth uses the @x-goog-api-key@ header rather than the @?key=@ query
-- parameter so API keys never appear in URLs (logs, proxies, history).
module Otto.AI.Gemini
  ( mkGeminiProvider,
  )
where

import Control.Exception (try)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BSC
import Data.ByteString.Lazy (ByteString)
import Data.CaseInsensitive qualified as CI
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Network.HTTP.Client qualified as HTTP
import Network.HTTP.Types.Header (HeaderName)
import Network.HTTP.Types.Status (statusCode)
import Otto.AI.Config (GeminiConfig (..))
import Otto.AI.Error (ProviderError (..))
import Otto.AI.Gemini.Internal
  ( buildRequestBody,
    decodeErrorMessage,
    decodeResponseBody,
  )
import Otto.AI.Provider (Provider (..))
import Otto.AI.Types (ModelId (..), ProviderName (Gemini), Request (..), Response)

-- | Construct a Gemini 'Provider' bound to the given HTTP 'Manager' and
-- configuration. The manager is shared across calls so TLS sessions and
-- connections are reused.
mkGeminiProvider :: HTTP.Manager -> GeminiConfig -> Provider
mkGeminiProvider manager cfg =
  Provider
    { pName = Gemini,
      pGenerate = runGemini manager cfg
    }

runGemini ::
  HTTP.Manager ->
  GeminiConfig ->
  Request ->
  IO (Either ProviderError Response)
runGemini manager cfg req = case buildRequestBody cfg req of
  Left err -> pure (Left err)
  Right body -> do
    attempt <- try (sendRequest manager cfg req body)
    pure $ case attempt of
      Left exn -> Left (ProviderNetworkError Gemini exn)
      Right httpResp -> handleResponse httpResp

sendRequest ::
  HTTP.Manager ->
  GeminiConfig ->
  Request ->
  ByteString ->
  IO (HTTP.Response ByteString)
sendRequest manager cfg req body = do
  let url =
        geminiBaseUrl cfg
          <> "/v1beta/models/"
          <> unModelId (reqModel req)
          <> ":generateContent"
  base <- HTTP.parseRequest (Text.unpack url)
  let httpReq =
        base
          { HTTP.method = "POST",
            HTTP.requestBody = HTTP.RequestBodyLBS body,
            HTTP.requestHeaders =
              [ ("x-goog-api-key", Text.encodeUtf8 (geminiApiKey cfg)),
                ("content-type", "application/json")
              ]
          }
  HTTP.httpLbs httpReq manager

handleResponse :: HTTP.Response ByteString -> Either ProviderError Response
handleResponse resp = case statusCode (HTTP.responseStatus resp) of
  200 -> decodeResponseBody (HTTP.responseBody resp)
  401 -> Left (authError resp)
  403 -> Left (authError resp)
  429 -> Left (rateLimitError resp)
  status -> Left (ProviderHttpError Gemini status (HTTP.responseBody resp))

authError :: HTTP.Response ByteString -> ProviderError
authError resp =
  ProviderAuthError Gemini (decodeErrorMessage (HTTP.responseBody resp))

rateLimitError :: HTTP.Response ByteString -> ProviderError
rateLimitError resp =
  ProviderRateLimitError Gemini (parseRetryAfter (HTTP.responseHeaders resp))

parseRetryAfter :: [(HeaderName, BS.ByteString)] -> Maybe Int
parseRetryAfter headers = do
  raw <- lookup (CI.mk "Retry-After") headers
  case reads (BSC.unpack raw) of
    [(n, "")] -> Just n
    _ -> Nothing
