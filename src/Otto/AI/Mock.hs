-- |
-- Module      : Otto.AI.Mock
-- Description : In-memory mock provider for tests.
--
-- A 'MockHandle' wraps two 'IORef's: a queue of canned responses (one is
-- popped per call) and a log of captured requests (appended in call order).
-- Tests build a mock, swap it into the application environment, exercise the
-- code under test, then assert on what was captured.
--
-- When the response queue is exhausted, the mock returns a
-- 'ProviderMisconfigured' error — failures are deterministic and visible
-- rather than hanging or returning arbitrary defaults.
module Otto.AI.Mock
  ( MockHandle,
    newMock,
    mkMockProvider,
    takeCapturedRequests,
    peekCapturedRequests,
    remainingResponses,
  )
where

import Data.IORef
  ( IORef,
    atomicModifyIORef',
    newIORef,
    readIORef,
  )
import Otto.AI.Error (ProviderError (..))
import Otto.AI.Provider (Provider (..))
import Otto.AI.Types (ProviderName (Mock), Request, Response)

-- | Opaque handle to a mock provider's queued responses and captured requests.
data MockHandle = MockHandle
  { mhResponses :: IORef [Either ProviderError Response],
    mhCaptured :: IORef [Request]
  }

-- | Create a new mock handle seeded with a queue of canned responses, and the
-- 'Provider' that consumes them. The head of the queue is returned on the
-- first call.
newMock :: [Either ProviderError Response] -> IO (MockHandle, Provider)
newMock responses = do
  handle <- MockHandle <$> newIORef responses <*> newIORef []
  pure (handle, mkMockProvider handle)

-- | Build a 'Provider' that consumes the given 'MockHandle'.
--
-- Exposed separately from 'newMock' so tests can build one handle and vend
-- multiple providers from it (uncommon, but occasionally useful for
-- composition experiments).
mkMockProvider :: MockHandle -> Provider
mkMockProvider handle =
  Provider
    { pName = Mock,
      pGenerate = \req -> do
        atomicModifyIORef' (mhCaptured handle) (\xs -> (xs <> [req], ()))
        atomicModifyIORef' (mhResponses handle) $ \case
          [] -> ([], Left (ProviderMisconfigured Mock "mock queue exhausted"))
          (r : rest) -> (rest, r)
    }

-- | Return the captured requests in call order and clear the log.
takeCapturedRequests :: MockHandle -> IO [Request]
takeCapturedRequests handle =
  atomicModifyIORef' (mhCaptured handle) (\xs -> ([], xs))

-- | Return the captured requests without clearing the log.
peekCapturedRequests :: MockHandle -> IO [Request]
peekCapturedRequests = readIORef . mhCaptured

-- | Number of canned responses still in the queue.
remainingResponses :: MockHandle -> IO Int
remainingResponses = fmap length . readIORef . mhResponses
