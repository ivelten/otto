-- |
-- Module      : Otto.Feed.Error
-- Description : Typed errors raised by feed implementations.
--
-- 'FeedError' covers the failure modes of "fetch a feed URL, get back
-- a list of 'FeedItem'": low-level network trouble, non-2xx HTTP
-- responses, and bodies that don't parse as RSS / Atom.
--
-- The 'Show' instance is hand-written so messages are ready to print
-- or log directly. Response bodies are truncated to 500 bytes and
-- stripped of non-printable bytes before rendering, mirroring
-- "Otto.Crawler.Error".
module Otto.Feed.Error
  ( FeedError (..),
  )
where

import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.Char (chr, isPrint)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word8)
import Network.HTTP.Client (HttpException)
import Otto.Feed.Types (FeedName)

-- | Errors raised by any feed implementation.
data FeedError
  = -- | Low-level network / connection / TLS failure.
    FeedNetworkError FeedName HttpException
  | -- | The feed server returned a non-2xx status. Carries the
    -- truncated raw body.
    FeedHttpError FeedName Int ByteString
  | -- | The HTTP body was retrieved but did not parse as RSS / Atom.
    -- Carries the truncated raw body.
    FeedParseError FeedName ByteString
  | -- | Feed implementation cannot be used: invalid URL, required
    -- invariant violated, etc.
    FeedMisconfigured FeedName Text

-- | Hand-written 'Show' so error messages are directly printable /
-- loggable.
instance Show FeedError where
  show = \case
    FeedNetworkError name exn ->
      prefix name "network error: " <> show exn
    FeedHttpError name status body ->
      prefix name "HTTP " <> show status <> ": " <> renderBody body
    FeedParseError name body ->
      prefix name "could not parse body as RSS or Atom: " <> renderBody body
    FeedMisconfigured name msg ->
      prefix name "misconfigured: " <> Text.unpack msg

prefix :: FeedName -> String -> String
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
