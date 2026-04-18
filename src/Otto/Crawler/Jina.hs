-- |
-- Module      : Otto.Crawler.Jina
-- Description : Jina Reader crawler implementation.
--
-- Speaks Jina Reader's @r.jina.ai@ endpoint: a single @GET@ against
-- @{baseUrl}\/{targetUrl}@ returns a plain-text document whose body
-- is canonical Markdown. Authentication is optional — the anonymous
-- tier works without any header — so 'JinaConfig.jinaApiKey' is a
-- 'Maybe'.
--
-- Target-site blocks (CAPTCHA, 403, Cloudflare challenges) are
-- reported by Jina as @Warning@ headers in its response. This module
-- parses those and surfaces them as 'CrawlerBlocked' rather than
-- returning a useless "security verification" page as if it were
-- real content.
module Otto.Crawler.Jina
  ( mkJinaCrawler,
  )
where

import Control.Exception (try)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BSC
import Data.ByteString.Lazy (ByteString)
import Data.CaseInsensitive qualified as CI
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Time.Clock (UTCTime, getCurrentTime)
import Network.HTTP.Client qualified as HTTP
import Network.HTTP.Types.Header (HeaderName)
import Network.HTTP.Types.Status (statusCode)
import Otto.Crawler.Config (JinaConfig (..), JinaEngine (..))
import Otto.Crawler.Error (CrawlerError (..))
import Otto.Crawler.Handle (Crawler (..))
import Otto.Crawler.Jina.Internal
  ( ParsedJina (..),
    extractBlocked,
    parseJinaResponse,
  )
import Otto.Crawler.Types
  ( CrawlRequest (..),
    CrawlResult (..),
    CrawlerName (Jina),
    URL (..),
  )

-- | Construct a Jina Reader crawler bound to the given HTTP
-- 'Manager' and configuration.
mkJinaCrawler :: HTTP.Manager -> JinaConfig -> Crawler
mkJinaCrawler manager cfg =
  Crawler
    { cName = Jina,
      cFetch = runJina manager cfg
    }

runJina ::
  HTTP.Manager ->
  JinaConfig ->
  CrawlRequest ->
  IO (Either CrawlerError CrawlResult)
runJina manager cfg req = do
  attempt <- try (sendRequest manager cfg req)
  case attempt of
    Left exn -> pure (Left (CrawlerNetworkError Jina exn))
    Right httpResp -> do
      now <- getCurrentTime
      pure (handleResponse req now httpResp)

sendRequest ::
  HTTP.Manager ->
  JinaConfig ->
  CrawlRequest ->
  IO (HTTP.Response ByteString)
sendRequest manager cfg req = do
  let url = jinaBaseUrl cfg <> "/" <> unURL (crawlUrl req)
  base <- HTTP.parseRequest (Text.unpack url)
  let httpReq =
        base
          { HTTP.method = "GET",
            HTTP.requestHeaders = requestHeaders cfg
          }
  HTTP.httpLbs httpReq manager

requestHeaders :: JinaConfig -> [(HeaderName, BS.ByteString)]
requestHeaders cfg =
  authHeader (jinaApiKey cfg)
    <> engineHeader (jinaEngine cfg)
  where
    authHeader Nothing = []
    authHeader (Just key) =
      [("Authorization", "Bearer " <> Text.encodeUtf8 key)]

    engineHeader Nothing = []
    engineHeader (Just JinaDirect) = [("X-Engine", "direct")]
    engineHeader (Just JinaBrowser) = [("X-Engine", "browser")]

handleResponse ::
  CrawlRequest ->
  -- | Now — captured once per fetch so the timestamp is stable.
  UTCTime ->
  HTTP.Response ByteString ->
  Either CrawlerError CrawlResult
handleResponse req now resp = case statusCode (HTTP.responseStatus resp) of
  200 -> interpretBody req now (HTTP.responseBody resp)
  401 -> Left (CrawlerAuthError Jina (Text.pack "Jina returned 401 — check OTTO_JINA_API_KEY"))
  403 -> Left (CrawlerAuthError Jina (Text.pack "Jina returned 403 — check OTTO_JINA_API_KEY"))
  429 -> Left (CrawlerRateLimitError Jina (parseRetryAfter (HTTP.responseHeaders resp)))
  status -> Left (CrawlerHttpError Jina status (HTTP.responseBody resp))

interpretBody ::
  CrawlRequest ->
  UTCTime ->
  ByteString ->
  Either CrawlerError CrawlResult
interpretBody req now body =
  let parsed = parseJinaResponse body
   in case extractBlocked (pjWarnings parsed) of
        Just (status, reason) ->
          Left (CrawlerBlocked Jina (targetUrl parsed req) status reason)
        Nothing ->
          Right
            CrawlResult
              { crawledUrl = crawlUrl req,
                crawledTitle = pjTitle parsed,
                crawledPublishedAt = pjPublishedTime parsed,
                crawledContent = pjBody parsed,
                crawledCrawlerName = Jina,
                crawledAt = now
              }

-- | Prefer the target URL that Jina echoed (which may be a
-- redirect-follow result) over the one we asked for.
targetUrl :: ParsedJina -> CrawlRequest -> URL
targetUrl parsed req = case pjSourceUrl parsed of
  Just src -> URL src
  Nothing -> crawlUrl req

parseRetryAfter :: [(HeaderName, BS.ByteString)] -> Maybe Int
parseRetryAfter headers = do
  raw <- lookup (CI.mk "Retry-After") headers
  case reads (BSC.unpack raw) of
    [(n, "")] -> Just n
    _ -> Nothing
