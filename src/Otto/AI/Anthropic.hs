-- |
-- Module      : Otto.AI.Anthropic
-- Description : Anthropic (Claude) provider implementation.
--
-- Speaks Anthropic's Messages API (@POST /v1/messages@). This module only
-- handles the HTTP flow — authentication headers, status-code mapping,
-- and wrapping network exceptions as typed 'ProviderError's. The pure JSON
-- builders and decoders live in "Otto.AI.Anthropic.Internal" so they can
-- be tested in isolation.
--
-- Retries, streaming, tool use, and multi-modal content are out of scope.
-- Retries will come later as a separate @withRetry@ combinator wrapping any
-- 'Provider'; the provider contract stays single-shot.
module Otto.AI.Anthropic
  ( mkAnthropicProvider,
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
import Otto.AI.Anthropic.Internal
  ( buildRequestBody,
    decodeErrorMessage,
    decodeResponseBody,
  )
import Otto.AI.Config (AnthropicConfig (..))
import Otto.AI.Error (ProviderError (..))
import Otto.AI.Provider (Provider (..))
import Otto.AI.Types (ProviderName (Anthropic), Request, Response)

-- | Construct an Anthropic 'Provider' bound to the given HTTP 'Manager' and
-- configuration. The manager is shared across calls so TLS sessions and
-- connections are reused.
mkAnthropicProvider :: HTTP.Manager -> AnthropicConfig -> Provider
mkAnthropicProvider manager cfg =
  Provider
    { pName = Anthropic,
      pGenerate = runAnthropic manager cfg
    }

runAnthropic ::
  HTTP.Manager ->
  AnthropicConfig ->
  Request ->
  IO (Either ProviderError Response)
runAnthropic manager cfg req = case buildRequestBody cfg req of
  Left err -> pure (Left err)
  Right body -> do
    attempt <- try (sendRequest manager cfg body)
    pure $ case attempt of
      Left exn -> Left (ProviderNetworkError Anthropic exn)
      Right httpResp -> handleResponse httpResp

sendRequest ::
  HTTP.Manager ->
  AnthropicConfig ->
  ByteString ->
  IO (HTTP.Response ByteString)
sendRequest manager cfg body = do
  base <- HTTP.parseRequest (Text.unpack (anthropicBaseUrl cfg <> "/v1/messages"))
  let req =
        base
          { HTTP.method = "POST",
            HTTP.requestBody = HTTP.RequestBodyLBS body,
            HTTP.requestHeaders =
              [ ("x-api-key", Text.encodeUtf8 (anthropicApiKey cfg)),
                ("anthropic-version", "2023-06-01"),
                ("content-type", "application/json")
              ]
          }
  HTTP.httpLbs req manager

handleResponse :: HTTP.Response ByteString -> Either ProviderError Response
handleResponse resp = case statusCode (HTTP.responseStatus resp) of
  200 -> decodeResponseBody (HTTP.responseBody resp)
  401 -> Left (authError resp)
  403 -> Left (authError resp)
  429 -> Left (rateLimitError resp)
  status -> Left (ProviderHttpError Anthropic status (HTTP.responseBody resp))

authError :: HTTP.Response ByteString -> ProviderError
authError resp =
  ProviderAuthError Anthropic (decodeErrorMessage (HTTP.responseBody resp))

rateLimitError :: HTTP.Response ByteString -> ProviderError
rateLimitError resp =
  ProviderRateLimitError Anthropic (parseRetryAfter (HTTP.responseHeaders resp))

parseRetryAfter :: [(HeaderName, BS.ByteString)] -> Maybe Int
parseRetryAfter headers = do
  raw <- lookup (CI.mk "Retry-After") headers
  case reads (BSC.unpack raw) of
    [(n, "")] -> Just n
    _ -> Nothing
