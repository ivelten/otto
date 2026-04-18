-- |
-- Module      : Otto.AI.GeminiSpec
-- Description : Pure-path tests for the Gemini provider.
--
-- Mirrors "Otto.AI.AnthropicSpec": golden tests pin the request-body
-- wire format, HUnit tests exercise the response decoder across the
-- expected finish-reason mappings.
module Otto.AI.GeminiSpec (tests) where

import Data.ByteString.Lazy (ByteString)
import Otto.AI.Config
  ( GeminiConfig (..),
    defaultGeminiBaseUrl,
    defaultGeminiModel,
  )
import Otto.AI.Gemini.Internal (buildRequestBody, decodeResponseBody)
import Otto.AI.Types
  ( FinishReason (..),
    Message (..),
    ModelId (..),
    Request (..),
    Response (..),
    Role (..),
    Usage (..),
  )
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit (Assertion, assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "gemini"
    [ testGroup
        "request body (golden)"
        [ goldenRequest "simple-user" simpleUser,
          goldenRequest "with-system" withSystem,
          goldenRequest "with-temperature" withTemperature
        ],
      testGroup
        "response decode"
        [ testCase "STOP finish reason" decodeStopTest,
          testCase "MAX_TOKENS finish reason" decodeMaxTokensTest,
          testCase "SAFETY finish reason preserved" decodeSafetyTest,
          testCase "missing finish reason surfaces as StopOther <missing>" decodeMissingTest
        ]
    ]

testConfig :: GeminiConfig
testConfig =
  GeminiConfig
    { geminiApiKey = "unused-in-pure-path",
      geminiBaseUrl = defaultGeminiBaseUrl,
      geminiDefaultModel = defaultGeminiModel
    }

goldenRequest :: String -> Request -> TestTree
goldenRequest name req =
  goldenVsString
    name
    ("test/golden/gemini/request-" <> name <> ".json")
    $ case buildRequestBody testConfig req of
      Left err -> error (show err)
      Right body -> pure (body <> "\n")

-- Request fixtures

simpleUser :: Request
simpleUser =
  Request
    { reqModel = ModelId "gemini-2.5-pro",
      reqSystem = Nothing,
      reqMessages = [Message {msgRole = User, msgContent = "Hello, Otto."}],
      reqMaxTokens = 1024,
      reqTemperature = Nothing
    }

withSystem :: Request
withSystem =
  Request
    { reqModel = ModelId "gemini-2.5-pro",
      reqSystem = Just "You are a concise assistant.",
      reqMessages =
        [Message {msgRole = User, msgContent = "Summarize monads."}],
      reqMaxTokens = 2048,
      reqTemperature = Nothing
    }

withTemperature :: Request
withTemperature =
  Request
    { reqModel = ModelId "gemini-2.5-flash",
      reqSystem = Nothing,
      reqMessages =
        [ Message {msgRole = User, msgContent = "What is 2+2?"},
          Message {msgRole = Assistant, msgContent = "4"},
          Message {msgRole = User, msgContent = "Is it always 4?"}
        ],
      reqMaxTokens = 512,
      reqTemperature = Just 0.7
    }

-- Response decode tests

stopBody :: ByteString
stopBody =
  "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hello!\"}],"
    <> "\"role\":\"model\"},\"finishReason\":\"STOP\"}],"
    <> "\"usageMetadata\":{\"promptTokenCount\":12,\"candidatesTokenCount\":3,"
    <> "\"totalTokenCount\":15},\"modelVersion\":\"gemini-2.5-pro\"}"

maxTokensBody :: ByteString
maxTokensBody =
  "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Truncated...\"}],"
    <> "\"role\":\"model\"},\"finishReason\":\"MAX_TOKENS\"}],"
    <> "\"usageMetadata\":{\"promptTokenCount\":50,\"candidatesTokenCount\":512,"
    <> "\"totalTokenCount\":562},\"modelVersion\":\"gemini-2.5-pro\"}"

safetyBody :: ByteString
safetyBody =
  "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"...\"}],"
    <> "\"role\":\"model\"},\"finishReason\":\"SAFETY\"}],"
    <> "\"usageMetadata\":{\"promptTokenCount\":8,\"candidatesTokenCount\":1,"
    <> "\"totalTokenCount\":9},\"modelVersion\":\"gemini-2.5-flash\"}"

missingBody :: ByteString
missingBody =
  "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"ok\"}],"
    <> "\"role\":\"model\"}}],"
    <> "\"usageMetadata\":{\"promptTokenCount\":5,\"candidatesTokenCount\":1,"
    <> "\"totalTokenCount\":6},\"modelVersion\":\"gemini-2.5-flash\"}"

decodeStopTest :: Assertion
decodeStopTest = case decodeResponseBody stopBody of
  Left err -> assertFailure (show err)
  Right resp -> do
    respText resp @?= "Hello!"
    respFinishReason resp @?= StopEndTurn
    respModel resp @?= ModelId "gemini-2.5-pro"
    usageInputTokens (respUsage resp) @?= 12
    usageOutputTokens (respUsage resp) @?= 3

decodeMaxTokensTest :: Assertion
decodeMaxTokensTest = case decodeResponseBody maxTokensBody of
  Left err -> assertFailure (show err)
  Right resp -> do
    respFinishReason resp @?= StopMaxTokens
    usageOutputTokens (respUsage resp) @?= 512

decodeSafetyTest :: Assertion
decodeSafetyTest = case decodeResponseBody safetyBody of
  Left err -> assertFailure (show err)
  Right resp -> respFinishReason resp @?= StopOther "SAFETY"

decodeMissingTest :: Assertion
decodeMissingTest = case decodeResponseBody missingBody of
  Left err -> assertFailure (show err)
  Right resp -> respFinishReason resp @?= StopOther "<missing>"
