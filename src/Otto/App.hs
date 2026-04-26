-- |
-- Module      : Otto.App
-- Description : Application monad and shared environment.
--
-- 'App' is the monad every long-running Otto operation runs in: a
-- 'ReaderT' over 'IO' carrying the shared 'Env'. The outer stack is
-- intentionally flat — no @ExceptT@ on top of 'IO' — because
-- @ExceptT e IO@ does not compose safely with
-- 'Control.Concurrent.Async' primitives. Error handling is done via
-- @Either@ and @ExceptT@ /inside/ local pipelines (see "Otto.Error"),
-- not on the outer stack.
module Otto.App
  ( App (..),
    Env (..),
    runApp,
    liftLogAction,
  )
where

import Colog (HasLog (..), LogAction (..), Message)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (MonadReader, ReaderT (..))
import Otto.AI.Provider (HasAI (..), Provider)
import Otto.Catalog.Handle (Catalog, HasCatalog (..))
import Otto.Crawler.Handle (Crawler, HasCrawler (..))

-- | Shared application environment.
--
-- New capabilities (database pool, HTTP manager, configuration, …)
-- are added here as additional fields. Every module that needs
-- shared state reads it from 'Env' via 'MonadReader' and, where
-- appropriate, a capability typeclass (see 'HasLog', 'HasAI',
-- 'HasCrawler').
data Env = Env
  { -- | Composed log sink. Populated during bootstrap in
    -- "Otto.Logging".
    envLogAction :: LogAction App Message,
    -- | Configured AI provider. Use the disabled provider from
    -- "Otto.AI.Provider" when no API key is available.
    envAI :: Provider,
    -- | Configured crawler. Use the disabled crawler from
    -- "Otto.Crawler.Handle" when no crawler is available.
    envCrawler :: Crawler,
    -- | Configured catalog. Use the disabled catalog from
    -- "Otto.Catalog.Handle" when no backend is available.
    envCatalog :: Catalog
  }

-- | The application monad.
--
-- 'ReaderT' pattern: a newtype over @ReaderT Env IO@ so that every
-- effectful operation has implicit access to 'Env' while the stack
-- stays shallow and concurrency-safe.
newtype App a = App {unApp :: ReaderT Env IO a}
  deriving newtype
    ( Functor,
      Applicative,
      Monad,
      MonadIO,
      MonadReader Env
    )

instance HasLog Env Message App where
  getLogAction = envLogAction
  setLogAction newLogAction env = env {envLogAction = newLogAction}

instance HasAI Env where
  getAI = envAI

instance HasCrawler Env where
  getCrawler = envCrawler

instance HasCatalog Env where
  getCatalog = envCatalog

-- | Run an 'App' computation with the given environment.
--
-- ==== __Example__
--
-- >>> runApp env (pure ())
runApp :: Env -> App a -> IO a
runApp env action = runReaderT (unApp action) env

-- | Lift a 'LogAction' bound to 'IO' into the 'App' monad.
--
-- The log sinks produced by "Otto.Logging" live in 'IO'; 'Env'
-- stores one in 'App'. This helper bridges the two.
liftLogAction :: LogAction IO a -> LogAction App a
liftLogAction (LogAction f) = LogAction (liftIO . f)
