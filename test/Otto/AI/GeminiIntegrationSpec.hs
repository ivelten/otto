-- |
-- Module      : Otto.AI.GeminiIntegrationSpec
-- Description : Live smoke test for the Gemini provider.
--
-- Hits the real Google Generative Language API when
-- @OTTO_GEMINI_API_KEY@ is present; otherwise contributes an empty
-- (skipped) test group so the suite stays green without a key.
module Otto.AI.GeminiIntegrationSpec (tests) where

import Data.Text (Text)
import Data.Text qualified as Text
import Network.HTTP.Client.TLS (newTlsManager)
import Otto.AI.Config
  ( GeminiConfig (..),
    defaultGeminiBaseUrl,
    defaultGeminiModel,
  )
import Otto.AI.Gemini (mkGeminiProvider)
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

tests :: IO TestTree
tests = do
  mKey <- lookupEnv "OTTO_GEMINI_API_KEY"
  pure $ case mKey of
    Nothing ->
      testGroup
        "gemini integration (skipped: OTTO_GEMINI_API_KEY not set)"
        []
    Just key ->
      testGroup
        "gemini integration"
        [testCase "pong smoke test" (pongTest (Text.pack key))]

pongTest :: Text -> Assertion
pongTest key = do
  manager <- newTlsManager
  let cfg =
        GeminiConfig
          { geminiApiKey = key,
            geminiBaseUrl = defaultGeminiBaseUrl,
            geminiDefaultModel = defaultGeminiModel
          }
      provider = mkGeminiProvider manager cfg
      req =
        Request
          { reqModel = defaultGeminiModel,
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
