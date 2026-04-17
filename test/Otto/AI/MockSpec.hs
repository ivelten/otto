-- |
-- Module      : Otto.AI.MockSpec
-- Description : Unit tests for "Otto.AI.Mock".
--
-- Verifies the three observable properties of the mock provider:
-- requests are captured in call order, responses are popped FIFO from
-- the queue, and an exhausted queue yields a deterministic
-- 'ProviderMisconfigured' error rather than hanging or crashing.
module Otto.AI.MockSpec (tests) where

import Data.Text (Text)
import Data.Text qualified as Text
import Otto.AI.Error (ProviderError (..))
import Otto.AI.Mock (newMock, takeCapturedRequests)
import Otto.AI.Provider (Provider (..))
import Otto.AI.Types
  ( FinishReason (..),
    Message (..),
    ModelId (..),
    ProviderName (Mock),
    Request (..),
    Response (..),
    Role (..),
    Usage (..),
  )
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "mock provider"
    [ testCase "captures requests in call order" captureOrderTest,
      testCase "returns canned responses in FIFO order" fifoTest,
      testCase "returns ProviderMisconfigured when queue is exhausted" exhaustTest
    ]

sampleRequest :: Text -> Request
sampleRequest content =
  Request
    { reqModel = ModelId "test-model",
      reqSystem = Nothing,
      reqMessages = [Message {msgRole = User, msgContent = content}],
      reqMaxTokens = 64,
      reqTemperature = Nothing
    }

sampleResponse :: Text -> Response
sampleResponse textOut =
  Response
    { respText = textOut,
      respModel = ModelId "test-model",
      respFinishReason = StopEndTurn,
      respUsage = Usage {usageInputTokens = 1, usageOutputTokens = 2}
    }

captureOrderTest :: Assertion
captureOrderTest = do
  (handle, provider) <-
    newMock
      [ Right (sampleResponse "r1"),
        Right (sampleResponse "r2")
      ]
  _ <- pGenerate provider (sampleRequest "a")
  _ <- pGenerate provider (sampleRequest "b")
  captured <- takeCapturedRequests handle
  captured @?= [sampleRequest "a", sampleRequest "b"]

fifoTest :: Assertion
fifoTest = do
  (_, provider) <-
    newMock
      [ Right (sampleResponse "r1"),
        Right (sampleResponse "r2")
      ]
  r1 <- pGenerate provider (sampleRequest "x")
  r2 <- pGenerate provider (sampleRequest "y")
  case (r1, r2) of
    (Right a, Right b) -> do
      respText a @?= "r1"
      respText b @?= "r2"
    _ ->
      assertFailure
        ( "expected two successful responses, got: "
            <> show r1
            <> " / "
            <> show r2
        )

exhaustTest :: Assertion
exhaustTest = do
  (_, provider) <- newMock [Right (sampleResponse "only")]
  _ <- pGenerate provider (sampleRequest "first")
  r <- pGenerate provider (sampleRequest "second")
  case r of
    Left (ProviderMisconfigured Mock msg) ->
      assertBool
        ("expected 'exhausted' in message: " <> Text.unpack msg)
        ("exhausted" `Text.isInfixOf` msg)
    other ->
      assertFailure
        ("expected ProviderMisconfigured Mock, got: " <> show other)
