-- |
-- Module      : Main
-- Description : Top-level @tasty@ test runner for Otto.
--
-- Each module's tests live under @test/Otto/**/*Spec.hs@ and export a
-- @tests :: TestTree@ (or @IO TestTree@ when runtime decisions are needed,
-- e.g. the env-gated integration spec). This runner stitches them together
-- under the top-level @otto@ group.
module Main (main) where

import Otto.AI.AnthropicIntegrationSpec qualified as AnthropicIntegrationSpec
import Otto.AI.AnthropicSpec qualified as AnthropicSpec
import Otto.AI.MockSpec qualified as MockSpec
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main = do
  integrationTree <- AnthropicIntegrationSpec.tests
  defaultMain $
    testGroup
      "otto"
      [ MockSpec.tests,
        AnthropicSpec.tests,
        integrationTree
      ]
