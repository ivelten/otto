-- |
-- Module      : Otto.AI.AnthropicSpec
-- Description : Pure-path tests for the Anthropic provider.
--
-- Exercises the request body builder and the response decoder in
-- "Otto.AI.Anthropic.Internal" without going over the network.
--
-- * /Request body:/ golden tests pin the exact JSON wire format we send to
--   Anthropic. Any unintentional change in field ordering, naming, or
--   shape produces a diff.
-- * /Response decode:/ plain HUnit assertions on the decoded 'Response',
--   covering the expected stop-reason mappings and usage extraction.
module Otto.AI.AnthropicSpec (tests) where

import Data.ByteString.Lazy (ByteString)
import Otto.AI.Anthropic.Internal (buildRequestBody, decodeResponseBody)
import Otto.AI.Config
  ( AnthropicConfig (..),
    defaultAnthropicBaseUrl,
    defaultAnthropicModel,
  )
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
    "anthropic"
    [ testGroup
        "request body (golden)"
        [ goldenRequest "simple-user" simpleUser,
          goldenRequest "with-system" withSystem,
          goldenRequest "with-temperature" withTemperature
        ],
      testGroup
        "response decode"
        [ testCase "end_turn stop reason" decodeEndTurnTest,
          testCase "max_tokens stop reason" decodeMaxTokensTest,
          testCase "unknown stop reason preserved" decodeUnknownStopTest,
          testCase "missing stop reason surfaces as StopOther <missing>" decodeMissingStopTest
        ]
    ]

testConfig :: AnthropicConfig
testConfig =
  AnthropicConfig
    { anthropicApiKey = "unused-in-pure-path",
      anthropicBaseUrl = defaultAnthropicBaseUrl,
      anthropicDefaultModel = defaultAnthropicModel
    }

goldenRequest :: String -> Request -> TestTree
goldenRequest name req =
  goldenVsString
    name
    ("test/golden/anthropic/request-" <> name <> ".json")
    $ case buildRequestBody testConfig req of
      Left err -> error (show err)
      Right body -> pure (body <> "\n")

-- Request fixtures

simpleUser :: Request
simpleUser =
  Request
    { reqModel = ModelId "claude-sonnet-4-6",
      reqSystem = Nothing,
      reqMessages = [Message {msgRole = User, msgContent = "Hello, Otto."}],
      reqMaxTokens = 1024,
      reqTemperature = Nothing
    }

withSystem :: Request
withSystem =
  Request
    { reqModel = ModelId "claude-sonnet-4-6",
      reqSystem = Just "You are a concise assistant.",
      reqMessages =
        [Message {msgRole = User, msgContent = "Summarize monads."}],
      reqMaxTokens = 2048,
      reqTemperature = Nothing
    }

withTemperature :: Request
withTemperature =
  Request
    { reqModel = ModelId "claude-opus-4-7",
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

endTurnBody :: ByteString
endTurnBody =
  "{\"id\":\"msg_01\",\"type\":\"message\",\"role\":\"assistant\","
    <> "\"content\":[{\"type\":\"text\",\"text\":\"Hello!\"}],"
    <> "\"model\":\"claude-sonnet-4-6-20260101\",\"stop_reason\":\"end_turn\","
    <> "\"usage\":{\"input_tokens\":12,\"output_tokens\":3}}"

maxTokensBody :: ByteString
maxTokensBody =
  "{\"id\":\"msg_02\",\"type\":\"message\",\"role\":\"assistant\","
    <> "\"content\":[{\"type\":\"text\",\"text\":\"Truncated...\"}],"
    <> "\"model\":\"claude-sonnet-4-6-20260101\",\"stop_reason\":\"max_tokens\","
    <> "\"usage\":{\"input_tokens\":50,\"output_tokens\":1024}}"

unknownStopBody :: ByteString
unknownStopBody =
  "{\"id\":\"msg_03\",\"type\":\"message\",\"role\":\"assistant\","
    <> "\"content\":[{\"type\":\"text\",\"text\":\"done\"}],"
    <> "\"model\":\"claude-haiku-4-5\",\"stop_reason\":\"mystery_reason\","
    <> "\"usage\":{\"input_tokens\":8,\"output_tokens\":1}}"

missingStopBody :: ByteString
missingStopBody =
  "{\"id\":\"msg_04\",\"type\":\"message\",\"role\":\"assistant\","
    <> "\"content\":[{\"type\":\"text\",\"text\":\"ok\"}],"
    <> "\"model\":\"claude-haiku-4-5\","
    <> "\"usage\":{\"input_tokens\":5,\"output_tokens\":1}}"

decodeEndTurnTest :: Assertion
decodeEndTurnTest = case decodeResponseBody endTurnBody of
  Left err -> assertFailure (show err)
  Right resp -> do
    respText resp @?= "Hello!"
    respFinishReason resp @?= StopEndTurn
    respModel resp @?= ModelId "claude-sonnet-4-6-20260101"
    usageInputTokens (respUsage resp) @?= 12
    usageOutputTokens (respUsage resp) @?= 3

decodeMaxTokensTest :: Assertion
decodeMaxTokensTest = case decodeResponseBody maxTokensBody of
  Left err -> assertFailure (show err)
  Right resp -> do
    respFinishReason resp @?= StopMaxTokens
    usageOutputTokens (respUsage resp) @?= 1024

decodeUnknownStopTest :: Assertion
decodeUnknownStopTest = case decodeResponseBody unknownStopBody of
  Left err -> assertFailure (show err)
  Right resp -> respFinishReason resp @?= StopOther "mystery_reason"

decodeMissingStopTest :: Assertion
decodeMissingStopTest = case decodeResponseBody missingStopBody of
  Left err -> assertFailure (show err)
  Right resp -> respFinishReason resp @?= StopOther "<missing>"
