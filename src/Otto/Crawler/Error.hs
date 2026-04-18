-- |
-- Module      : Otto.Crawler.Error
-- Description : Typed errors raised by crawler implementations.
--
-- 'CrawlerError' is the single error type every crawler returns. Its
-- constructors cover the failure modes callers care about: network
-- trouble, non-2xx HTTP responses, target sites that block bots,
-- malformed bodies, auth problems, rate limiting, and
-- misconfiguration.
--
-- 'CrawlerBlocked' is modeled as an error rather than a
-- success-with-status: the crawler itself worked correctly but the
-- /target/ refused to deliver content, and railway-oriented callers
-- want to pattern-match on that without an extra layer.
--
-- The 'Show' instance is hand-written (not derived) so messages are
-- ready to print or log. Response bodies are truncated to 500 bytes
-- and stripped of non-printable bytes before rendering.
module Otto.Crawler.Error
  ( CrawlerError (..),
  )
where

import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.Char (chr, isPrint)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word8)
import Network.HTTP.Client (HttpException)
import Otto.Crawler.Types (CrawlerName, URL (..))

-- | Errors raised by any crawler implementation.
data CrawlerError
  = -- | Low-level network / connection / TLS failure.
    CrawlerNetworkError CrawlerName HttpException
  | -- | The crawler service (not the target) returned a non-2xx status
    -- that isn't specifically classified below. Carries the raw body
    -- for diagnostics.
    CrawlerHttpError CrawlerName Int ByteString
  | -- | The crawler worked but the /target/ URL refused (403 + CAPTCHA
    -- page, Cloudflare challenge, etc.). Carries the target URL, the
    -- upstream status, and a human-readable reason.
    CrawlerBlocked CrawlerName URL Int Text
  | -- | The crawler returned a well-formed HTTP response but its body
    -- didn't match the expected envelope. Carries the parse error and
    -- the raw body.
    CrawlerDecodeError CrawlerName Text ByteString
  | -- | 401 or 403 from the crawler service — our credentials are
    -- invalid (not the target's fault). Carries the service's
    -- message when available.
    CrawlerAuthError CrawlerName Text
  | -- | 429 from the crawler service. Optional @Retry-After@ in
    -- seconds when the service sent one.
    CrawlerRateLimitError CrawlerName (Maybe Int)
  | -- | Crawler cannot be used: base URL invalid, required invariant
    -- violated by the caller, etc.
    CrawlerMisconfigured CrawlerName Text

-- | Hand-written 'Show' so error messages are directly printable /
-- loggable. Body 'ByteString's are truncated to 500 bytes and
-- non-printable bytes are escaped.
instance Show CrawlerError where
  show = \case
    CrawlerNetworkError name exn ->
      prefix name "network error: " <> show exn
    CrawlerHttpError name status body ->
      prefix name "HTTP "
        <> show status
        <> ": "
        <> renderBody body
    CrawlerBlocked name url status reason ->
      prefix name "target "
        <> Text.unpack (unURL url)
        <> " blocked with status "
        <> show status
        <> ": "
        <> Text.unpack reason
    CrawlerDecodeError name msg body ->
      prefix name "decode error: "
        <> Text.unpack msg
        <> " | body: "
        <> renderBody body
    CrawlerAuthError name msg ->
      prefix name "auth error: " <> Text.unpack msg
    CrawlerRateLimitError name retryAfter ->
      prefix name "rate limited"
        <> case retryAfter of
          Nothing -> ""
          Just s -> " (retry after " <> show s <> "s)"
    CrawlerMisconfigured name msg ->
      prefix name "misconfigured: " <> Text.unpack msg

prefix :: CrawlerName -> String -> String
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
