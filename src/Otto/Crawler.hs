-- |
-- Module      : Otto.Crawler
-- Description : Public high-level crawler API — types, abstraction,
-- configuration, and the crawler factory.
--
-- Most callers should import this module. It re-exports the
-- vendor-neutral value types, the 'Crawler' abstraction (including
-- the 'HasCrawler' class and the 'fetch' helper), configuration
-- types, and the 'CrawlerError' type, and it provides 'buildCrawler'
-- — the factory that turns a 'CrawlerConfig' into a concrete
-- 'Crawler'.
--
-- Concrete implementations ('Otto.Crawler.Jina', 'Otto.Crawler.Mock')
-- and the low-level response parser ('Otto.Crawler.Jina.Internal')
-- are intentionally /not/ re-exported — importers bring them in
-- explicitly when they need to construct a crawler directly or
-- inspect raw responses.
module Otto.Crawler
  ( module Otto.Crawler.Types,
    module Otto.Crawler.Error,
    module Otto.Crawler.Handle,
    module Otto.Crawler.Config,
    buildCrawler,
  )
where

import Network.HTTP.Client (Manager)
import Otto.Crawler.Config
import Otto.Crawler.Error
import Otto.Crawler.Handle
import Otto.Crawler.Jina (mkJinaCrawler)
import Otto.Crawler.Types

-- | Build the configured 'Crawler' from the application's crawler
-- configuration. Today this always returns a Jina Reader crawler
-- (anonymous when no API key is configured). When a second crawler
-- is added, this function learns to pick between them via a
-- 'PreferredCrawler' argument.
--
-- The 'Manager' is passed through so connection pools and TLS
-- sessions are shared across callers.
buildCrawler :: Manager -> CrawlerConfig -> Crawler
buildCrawler manager cfg = mkJinaCrawler manager (ccJina cfg)
