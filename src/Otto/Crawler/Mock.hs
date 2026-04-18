-- |
-- Module      : Otto.Crawler.Mock
-- Description : In-memory mock crawler for tests.
--
-- Mirrors 'Otto.AI.Mock': a 'MockCrawlerHandle' wraps two 'IORef's —
-- a FIFO queue of canned responses, and a log of captured requests.
-- Tests build a mock, swap it into the environment, exercise the
-- code, then assert on the captured requests.
--
-- When the response queue is exhausted, the mock returns
-- 'CrawlerMisconfigured' so failures are deterministic and visible.
module Otto.Crawler.Mock
  ( MockCrawlerHandle,
    newMockCrawler,
    mkMockCrawler,
    takeCapturedCrawlRequests,
    peekCapturedCrawlRequests,
    remainingCrawlResponses,
  )
where

import Data.IORef
  ( IORef,
    atomicModifyIORef',
    newIORef,
    readIORef,
  )
import Otto.Crawler.Error (CrawlerError (..))
import Otto.Crawler.Handle (Crawler (..))
import Otto.Crawler.Types
  ( CrawlRequest,
    CrawlResult,
    CrawlerName (Mock),
  )

-- | Opaque handle to a mock crawler's queued responses and captured
-- requests.
data MockCrawlerHandle = MockCrawlerHandle
  { mchResponses :: IORef [Either CrawlerError CrawlResult],
    mchCaptured :: IORef [CrawlRequest]
  }

-- | Create a new mock handle seeded with a queue of canned responses,
-- and the 'Crawler' that consumes them.
newMockCrawler ::
  [Either CrawlerError CrawlResult] ->
  IO (MockCrawlerHandle, Crawler)
newMockCrawler responses = do
  handle <- MockCrawlerHandle <$> newIORef responses <*> newIORef []
  pure (handle, mkMockCrawler handle)

-- | Build a 'Crawler' that consumes the given 'MockCrawlerHandle'.
mkMockCrawler :: MockCrawlerHandle -> Crawler
mkMockCrawler handle =
  Crawler
    { cName = Mock,
      cFetch = \req -> do
        atomicModifyIORef' (mchCaptured handle) (\xs -> (xs <> [req], ()))
        atomicModifyIORef' (mchResponses handle) $ \case
          [] -> ([], Left (CrawlerMisconfigured Mock "mock queue exhausted"))
          (r : rest) -> (rest, r)
    }

-- | Return the captured requests in call order and clear the log.
takeCapturedCrawlRequests :: MockCrawlerHandle -> IO [CrawlRequest]
takeCapturedCrawlRequests handle =
  atomicModifyIORef' (mchCaptured handle) (\xs -> ([], xs))

-- | Return the captured requests without clearing the log.
peekCapturedCrawlRequests :: MockCrawlerHandle -> IO [CrawlRequest]
peekCapturedCrawlRequests = readIORef . mchCaptured

-- | Number of canned responses still in the queue.
remainingCrawlResponses :: MockCrawlerHandle -> IO Int
remainingCrawlResponses = fmap length . readIORef . mchResponses
