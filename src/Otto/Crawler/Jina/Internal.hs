-- |
-- Module      : Otto.Crawler.Jina.Internal
-- Description : Pure parser for Jina Reader responses.
--
-- Jina Reader returns a plain-text document with a small metadata
-- block followed by the Markdown body:
--
-- > Title: Example Domain
-- > URL Source: https://example.com
-- > Published Time: 2024-01-15T10:00:00Z
-- > Warning: Target URL returned error 403: Forbidden
-- >
-- > Markdown Content:
-- > # Example Domain
-- > …
--
-- This module extracts the fields we care about — title, source
-- URL, published time, warnings — and returns the body as a
-- standalone 'Text'. It also detects target-site blocks ("Warning:
-- Target URL returned error N:") and surfaces them as a parsed
-- ('Int', 'Text') so callers can decide to raise 'CrawlerBlocked'
-- instead of returning a useless result.
module Otto.Crawler.Jina.Internal
  ( ParsedJina (..),
    parseJinaResponse,
    extractBlocked,
  )
where

import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding (decodeUtf8With)
import Data.Text.Encoding.Error (lenientDecode)
import Text.Read (readMaybe)

-- | The fields we extract from a Jina Reader response.
data ParsedJina = ParsedJina
  { pjTitle :: Maybe Text,
    pjSourceUrl :: Maybe Text,
    pjPublishedTime :: Maybe Text,
    pjWarnings :: [Text],
    pjBody :: Text
  }
  deriving stock (Eq, Show)

-- | Parse a Jina Reader response body.
--
-- Always succeeds: the worst case is a document with no recognized
-- headers and the full body under 'pjBody'. Callers who need
-- stricter validation should inspect the fields.
parseJinaResponse :: ByteString -> ParsedJina
parseJinaResponse raw =
  let text = decodeUtf8With lenientDecode (LBS.toStrict raw)
      (headerLines, bodyLines) = splitAtMarkdownContent (Text.lines text)
      headers = mapMaybe parseHeader headerLines
      body = Text.strip (Text.intercalate "\n" bodyLines)
   in ParsedJina
        { pjTitle = lookupHeader "Title" headers,
          pjSourceUrl = lookupHeader "URL Source" headers,
          pjPublishedTime = lookupHeader "Published Time" headers,
          pjWarnings = lookupHeadersAll "Warning" headers,
          pjBody = body
        }

-- | If any of the warnings signal a target-side block ("Target URL
-- returned error N: …"), extract the upstream status code and the
-- reason text. Returns the first such warning found, or 'Nothing' if
-- none are block warnings.
extractBlocked :: [Text] -> Maybe (Int, Text)
extractBlocked = firstJust . map parseBlockWarning
  where
    firstJust = foldr (\m acc -> case m of Just x -> Just x; Nothing -> acc) Nothing

parseBlockWarning :: Text -> Maybe (Int, Text)
parseBlockWarning w = do
  rest <- Text.stripPrefix "Target URL returned error " w
  let (codeStr, after) = Text.breakOn ":" rest
  code <- readMaybe (Text.unpack (Text.strip codeStr))
  let reason = Text.strip (Text.drop 1 after)
  pure (code, reason)

-- Split the line list at the "Markdown Content:" marker. Lines
-- before the marker are headers; lines after are the body. If the
-- marker is absent, everything is treated as header and the body is
-- empty.
splitAtMarkdownContent :: [Text] -> ([Text], [Text])
splitAtMarkdownContent ls =
  case break isMarkdownContentMarker ls of
    (hs, []) -> (hs, [])
    (hs, _ : bs) -> (hs, bs)
  where
    isMarkdownContentMarker l =
      Text.isPrefixOf "Markdown Content:" (Text.stripStart l)

parseHeader :: Text -> Maybe (Text, Text)
parseHeader line
  | Text.null (Text.strip line) = Nothing
  | otherwise =
      let (key, rest) = Text.breakOn ":" line
       in if Text.null rest
            then Nothing
            else Just (Text.strip key, Text.strip (Text.drop 1 rest))

lookupHeader :: Text -> [(Text, Text)] -> Maybe Text
lookupHeader = lookup

lookupHeadersAll :: Text -> [(Text, Text)] -> [Text]
lookupHeadersAll k = map snd . filter ((== k) . fst)
