-- |
-- Module      : Otto.AI.AnthropicIntegrationSpec
-- Description : Live smoke test for the Anthropic provider.
--
-- Hits the real Anthropic API when @OTTO_ANTHROPIC_API_KEY@ is present in
-- the environment; otherwise contributes an empty (skipped) test group so
-- CI without a key stays green.
--
-- The 'tests' value is 'IO' because the decision whether to run the live
-- test is made at test-tree construction time (reading the environment);
-- the top-level test runner in "Main" awaits this 'IO' once during
-- assembly and doesn't re-evaluate it.
module Otto.AI.AnthropicIntegrationSpec (tests) where

import Data.Text (Text)
import Data.Text qualified as Text
import Network.HTTP.Client.TLS (newTlsManager)
import Otto.AI.Anthropic (mkAnthropicProvider)
import Otto.AI.Config
  ( AnthropicConfig (..),
    defaultAnthropicBaseUrl,
    defaultAnthropicModel,
  )
import Otto.AI.Provider (Provider (..))
import Otto.AI.Types
  ( Message (..),
    Request (..),
    Response (..),
    Role (..),
    Usage (..),
  )
import System.Environment (lookupEnv)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase)

-- | Build the integration test tree by inspecting the environment.
tests :: IO TestTree
tests = do
  mKey <- lookupEnv "OTTO_ANTHROPIC_API_KEY"
  pure $ case mKey of
    Nothing ->
      testGroup
        "anthropic integration (skipped: OTTO_ANTHROPIC_API_KEY not set)"
        []
    Just key ->
      testGroup
        "anthropic integration"
        [testCase "pong smoke test" (pongTest (Text.pack key))]

pongTest :: Text -> Assertion
pongTest key = do
  manager <- newTlsManager
  let cfg =
        AnthropicConfig
          { anthropicApiKey = key,
            anthropicBaseUrl = defaultAnthropicBaseUrl,
            anthropicDefaultModel = defaultAnthropicModel
          }
      provider = mkAnthropicProvider manager cfg
      req =
        Request
          { reqModel = defaultAnthropicModel,
            reqSystem = Nothing,
            reqMessages = [Message {msgRole = User, msgContent = "Say only the word pong."}],
            reqMaxTokens = 50,
            reqTemperature = Nothing
          }
  result <- pGenerate provider req
  case result of
    Left err -> assertFailure ("provider returned error: " <> show err)
    Right resp -> do
      assertBool
        ("response should contain 'pong', got: " <> Text.unpack (respText resp))
        ("pong" `Text.isInfixOf` Text.toLower (respText resp))
      assertBool
        "outputTokens should be > 0"
        (usageOutputTokens (respUsage resp) > 0)
