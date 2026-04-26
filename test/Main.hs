-- |
-- Module      : Main
-- Description : Top-level @tasty@ test runner for Otto.
--
-- Each module's tests live under @test/Otto/**/*Spec.hs@ and export
-- a @tests :: TestTree@ (or @IO TestTree@ when runtime decisions are
-- needed, e.g. the env-gated integration specs). This runner
-- stitches them together under the top-level @otto@ group.
module Main (main) where

import Otto.AI.AnthropicIntegrationSpec qualified as AnthropicIntegrationSpec
import Otto.AI.AnthropicSpec qualified as AnthropicSpec
import Otto.AI.CliSpec qualified as CliSpec
import Otto.AI.GeminiIntegrationSpec qualified as GeminiIntegrationSpec
import Otto.AI.GeminiSpec qualified as GeminiSpec
import Otto.AI.MockSpec qualified as AIMockSpec
import Otto.Catalog.FileSystemSpec qualified as CatalogFileSystemSpec
import Otto.Catalog.RenderSpec qualified as CatalogRenderSpec
import Otto.Catalog.SlugSpec qualified as CatalogSlugSpec
import Otto.Crawler.JinaIntegrationSpec qualified as JinaIntegrationSpec
import Otto.Crawler.JinaSpec qualified as JinaSpec
import Otto.Crawler.MockSpec qualified as CrawlerMockSpec
import Otto.Feed.HttpSpec qualified as FeedHttpSpec
import Otto.PipelineSpec qualified as PipelineSpec
import Otto.Sources.FileSpec qualified as SourcesFileSpec
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main = do
  anthropicIntegration <- AnthropicIntegrationSpec.tests
  geminiIntegration <- GeminiIntegrationSpec.tests
  jinaIntegration <- JinaIntegrationSpec.tests
  defaultMain $
    testGroup
      "otto"
      [ AIMockSpec.tests,
        CliSpec.tests,
        AnthropicSpec.tests,
        anthropicIntegration,
        GeminiSpec.tests,
        geminiIntegration,
        CrawlerMockSpec.tests,
        JinaSpec.tests,
        jinaIntegration,
        CatalogSlugSpec.tests,
        CatalogRenderSpec.tests,
        CatalogFileSystemSpec.tests,
        SourcesFileSpec.tests,
        FeedHttpSpec.tests,
        PipelineSpec.tests
      ]
