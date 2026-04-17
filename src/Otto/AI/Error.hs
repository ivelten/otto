-- |
-- Module      : Otto.AI.Error
-- Description : Typed errors raised by AI providers.
--
-- 'ProviderError' is the single error type every provider implementation
-- returns. Its constructors cover the failure modes that matter to callers:
-- network-level trouble, non-2xx HTTP responses, JSON decode failures,
-- auth/misconfiguration, and rate limiting.
--
-- The 'Show' instance is hand-written (not derived) so that error messages
-- are ready to print or log without any extra formatting layer at the call
-- site. Response bodies carried in constructors are truncated to 500 chars
-- and stripped of non-printable bytes before being rendered.
module Otto.AI.Error
  ( ProviderError (..),
  )
where

import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.Char (chr, isPrint)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word8)
import Network.HTTP.Client (HttpException)
import Otto.AI.Types (ProviderName)

-- | Errors raised by any AI provider implementation.
data ProviderError
  = -- | Low-level network / connection / TLS failure.
    ProviderNetworkError ProviderName HttpException
  | -- | The provider returned a non-2xx status that isn't specifically
    -- classified below. Carries the raw body for diagnostics.
    ProviderHttpError ProviderName Int ByteString
  | -- | The provider returned a well-formed HTTP response, but JSON decoding
    -- failed. Carries the aeson error and the raw body.
    ProviderDecodeError ProviderName Text ByteString
  | -- | 401 or 403 — authentication failed. Carries the provider-supplied
    -- error message when available.
    ProviderAuthError ProviderName Text
  | -- | 429 — rate limited. Optional @Retry-After@ in seconds, parsed from
    -- the response headers.
    ProviderRateLimitError ProviderName (Maybe Int)
  | -- | Provider cannot be used: API key missing, base URL invalid, required
    -- invariant violated by the caller, etc.
    ProviderMisconfigured ProviderName Text

-- | Hand-written 'Show' so error messages are directly printable / loggable.
-- Body 'ByteString's are truncated to 500 bytes and non-printable bytes are
-- escaped; @HttpException@'s own 'Show' is already readable and is reused.
instance Show ProviderError where
  show = \case
    ProviderNetworkError name exn ->
      prefix name "network error: " <> show exn
    ProviderHttpError name status body ->
      prefix name "HTTP "
        <> show status
        <> ": "
        <> renderBody body
    ProviderDecodeError name msg body ->
      prefix name "decode error: "
        <> Text.unpack msg
        <> " | body: "
        <> renderBody body
    ProviderAuthError name msg ->
      prefix name "auth error: " <> Text.unpack msg
    ProviderRateLimitError name retryAfter ->
      prefix name "rate limited"
        <> case retryAfter of
          Nothing -> ""
          Just s -> " (retry after " <> show s <> "s)"
    ProviderMisconfigured name msg ->
      prefix name "misconfigured: " <> Text.unpack msg

prefix :: ProviderName -> String -> String
prefix name tag = "[" <> show name <> "] " <> tag

renderBody :: ByteString -> String
renderBody body =
  let truncated = LBS.take 500 body
      printable = fmap sanitize (LBS.unpack truncated)
   in printable <> if LBS.length body > 500 then "… [truncated]" else ""

sanitize :: Word8 -> Char
sanitize b
  | isPrint c = c
  | otherwise = '.'
  where
    c = chr (fromIntegral b)
