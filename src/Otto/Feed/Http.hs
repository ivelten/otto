-- |
-- Module      : Otto.Feed.Http
-- Description : HTTP + @feed@ package implementation of 'Feeds'.
--
-- 'mkHttpFeeds' returns a 'Feeds' that fetches the URL with
-- @http-client@, then hands the body to "Text.Feed.Import" for
-- RSS / Atom parsing. Items without a link are dropped at the parser
-- boundary; the recency filter and per-item crawling are the
-- pipeline's job.
--
-- The HTTP request shares the application's 'Manager' so connection
-- pools and TLS sessions are reused across feeds and the crawler.
module Otto.Feed.Http
  ( mkHttpFeeds,
    parseFeedBytes,
  )
where

import Control.Exception (try)
import Data.ByteString.Lazy (ByteString)
import Data.Maybe (mapMaybe)
import Data.Text qualified as Text
import Network.HTTP.Client
  ( Manager,
    Request (..),
    Response (..),
    httpLbs,
    parseRequest,
  )
import Network.HTTP.Client qualified as HTTP
import Network.HTTP.Types.Status (statusCode)
import Otto.Crawler.Types (URL (..))
import Otto.Feed.Error (FeedError (..))
import Otto.Feed.Handle (Feeds (..))
import Otto.Feed.Types (FeedItem (..), FeedName (Http))
import Text.Feed.Import (parseFeedSource)
import Text.Feed.Query
  ( feedItems,
    getItemLink,
    getItemPublishDate,
    getItemTitle,
  )
import Text.Feed.Types qualified as Feed

-- | Build an HTTP-backed 'Feeds' value.
mkHttpFeeds :: Manager -> Feeds
mkHttpFeeds manager =
  Feeds
    { fName = Http,
      fLoad = httpFLoad manager
    }

httpFLoad :: Manager -> URL -> IO (Either FeedError [FeedItem])
httpFLoad manager url = do
  bodyOrErr <- fetchBytes manager url
  pure $ case bodyOrErr of
    Left err -> Left err
    Right body -> parseFeedBytes body

fetchBytes :: Manager -> URL -> IO (Either FeedError ByteString)
fetchBytes manager (URL url) = do
  result <- try @HTTP.HttpException $ do
    req <- parseRequest (Text.unpack url)
    let req' = req {requestHeaders = userAgent : requestHeaders req}
    httpLbs req' manager
  pure $ case result of
    Left exn -> Left (FeedNetworkError Http exn)
    Right resp ->
      let status = statusCode (responseStatus resp)
          body = responseBody resp
       in if status >= 200 && status < 300
            then Right body
            else Left (FeedHttpError Http status body)
  where
    -- Identify ourselves so polite servers can rate-limit deliberately.
    userAgent = ("User-Agent", "otto/0.1 (+https://github.com/ivelten/otto)")

-- | Parse a feed body (RSS 1.0, RSS 2.0, or Atom) into our
-- vendor-neutral 'FeedItem' projection.
--
-- Pure: shared by the production HTTP loader and the test suite. Items
-- without a link are silently dropped — they're useless to the
-- pipeline since there is nothing to crawl.
parseFeedBytes :: ByteString -> Either FeedError [FeedItem]
parseFeedBytes body =
  case parseFeedSource body of
    Nothing -> Left (FeedParseError Http body)
    Just feed -> Right (mapMaybe itemToFeedItem (feedItems feed))

itemToFeedItem :: Feed.Item -> Maybe FeedItem
itemToFeedItem item = case getItemLink item of
  Nothing -> Nothing
  Just link ->
    Just
      FeedItem
        { fiUrl = URL link,
          fiTitle = getItemTitle item,
          fiPublishedAt = case getItemPublishDate item of
            Just (Just t) -> Just t
            _ -> Nothing
        }
