-- |
-- Module      : Otto.Catalog.Render
-- Description : Pure rendering of catalog entries and failure log lines.
--
-- All formatting decisions live here — YAML frontmatter for catalog
-- entries, JSON for the failure log — kept as pure 'Text' producers
-- so they can be golden-tested without touching the filesystem.
--
-- Rules baked into the renderer:
--
-- * Frontmatter values are always double-quoted with @\\@ and @"@
--   escaped, so titles or URLs containing @:@, @#@, or other YAML
--   metacharacters never produce ambiguous output.
-- * Unknown fields ('crawledTitle', 'crawledPublishedAt' when
--   'Nothing') are omitted entirely instead of being emitted as
--   @null@.
-- * Timestamps use a fixed second-precision ISO-8601 form ending in
--   @Z@ (e.g. @2026-04-18T01:23:45Z@), independent of the locale.
-- * Failure log lines are written manually rather than via 'aeson' so
--   the field order is fixed and the golden test pins the exact wire
--   format.
module Otto.Catalog.Render
  ( renderEntry,
    renderFailureLine,
    formatIso,
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time.Clock (UTCTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Numeric (showHex)
import Otto.Catalog.Types (FailureRecord (..))
import Otto.Crawler.Types (CrawlResult (..), URL (..))

-- | Render a 'CrawlResult' as a Markdown file with YAML frontmatter.
--
-- Output shape:
--
-- @
-- ---
-- source_url: \"https:\/\/example.com\"
-- title: \"Example Domain\"
-- published_at: \"2025-01-15T10:00:00Z\"
-- crawled_at: \"2026-04-18T01:23:45Z\"
-- crawler: \"Jina\"
-- ---
--
-- \<crawledContent body here\>
-- @
--
-- Optional metadata ('crawledTitle', 'crawledPublishedAt') is only
-- emitted when present. Output always ends with a single newline.
renderEntry :: CrawlResult -> Text
renderEntry res =
  Text.unlines headerLines <> ensureTrailingNewline (crawledContent res)
  where
    headerLines =
      ["---", kvLine "source_url" (unURL (crawledUrl res))]
        <> maybe [] (\t -> [kvLine "title" t]) (crawledTitle res)
        <> maybe [] (\p -> [kvLine "published_at" p]) (crawledPublishedAt res)
        <> [ kvLine "crawled_at" (formatIso (crawledAt res)),
             kvLine "crawler" (Text.pack (show (crawledCrawlerName res))),
             "---",
             ""
           ]

-- | Render a 'FailureRecord' as a single JSON line, without a trailing
-- newline. The caller appends @\\n@ when writing to JSONL.
--
-- Field order is fixed: @timestamp@, @source_url@, @error_class@,
-- @message@. Strings are JSON-escaped; control characters are emitted
-- as @\\uXXXX@.
renderFailureLine :: UTCTime -> FailureRecord -> Text
renderFailureLine ts fr =
  "{"
    <> field "timestamp" (formatIso ts)
    <> ","
    <> field "source_url" (unURL (frUrl fr))
    <> ","
    <> field "error_class" (frErrorClass fr)
    <> ","
    <> field "message" (frMessage fr)
    <> "}"
  where
    field k v = jsonString k <> ":" <> jsonString v

-- | Format a 'UTCTime' as second-precision ISO-8601 with the @Z@
-- timezone marker, e.g. @2026-04-18T01:23:45Z@.
formatIso :: UTCTime -> Text
formatIso = Text.pack . formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ"

ensureTrailingNewline :: Text -> Text
ensureTrailingNewline t
  | Text.null t = "\n"
  | Text.last t == '\n' = t
  | otherwise = t <> "\n"

kvLine :: Text -> Text -> Text
kvLine key value = key <> ": " <> yamlScalar value

yamlScalar :: Text -> Text
yamlScalar v = "\"" <> Text.concatMap escY v <> "\""
  where
    escY '\\' = "\\\\"
    escY '"' = "\\\""
    escY '\n' = "\\n"
    escY '\r' = "\\r"
    escY '\t' = "\\t"
    escY c = Text.singleton c

jsonString :: Text -> Text
jsonString t = "\"" <> Text.concatMap escJ t <> "\""
  where
    escJ '"' = "\\\""
    escJ '\\' = "\\\\"
    escJ '\n' = "\\n"
    escJ '\r' = "\\r"
    escJ '\t' = "\\t"
    escJ '\b' = "\\b"
    escJ '\f' = "\\f"
    escJ c
      | c < '\x20' = "\\u" <> hex4 (fromEnum c)
      | otherwise = Text.singleton c

hex4 :: Int -> Text
hex4 n =
  let h = showHex n ""
   in Text.pack (replicate (4 - length h) '0' <> h)
