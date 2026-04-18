-- |
-- Module      : Otto.AI.CliSpec
-- Description : Unit tests for 'Otto.AI.Cli.parseAskArgs'.
module Otto.AI.CliSpec (tests) where

import Data.List (isInfixOf)
import Otto.AI.Cli (AskOptions (..), parseAskArgs)
import Otto.AI.Config (PreferredProvider (..), parseProviderName)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "cli parsing"
    [ testGroup
        "parseProviderName"
        [ testCase "anthropic" $ parseProviderName "anthropic" @?= Right PreferAnthropic,
          testCase "ANTHROPIC (case-insensitive)" $
            parseProviderName "ANTHROPIC" @?= Right PreferAnthropic,
          testCase "gemini" $ parseProviderName "gemini" @?= Right PreferGemini,
          testCase "Gemini (mixed case)" $
            parseProviderName "Gemini" @?= Right PreferGemini,
          testCase "unknown value is Left" $ do
            case parseProviderName "llama" of
              Left msg -> assertBool "mentions provider name" ("llama" `isInfixOf` msg)
              Right _ -> fail "expected Left"
        ],
      testGroup
        "parseAskArgs"
        [ testCase "plain prompt, no flags" $
            parseAskArgs ["Hello", "world"]
              @?= Right AskOptions {askProviderOverride = Nothing, askPromptWords = ["Hello", "world"]},
          testCase "empty args yield empty options" $
            parseAskArgs []
              @?= Right AskOptions {askProviderOverride = Nothing, askPromptWords = []},
          testCase "--provider gemini prompt" $
            parseAskArgs ["--provider", "gemini", "Hi"]
              @?= Right AskOptions {askProviderOverride = Just PreferGemini, askPromptWords = ["Hi"]},
          testCase "-p anthropic prompt" $
            parseAskArgs ["-p", "anthropic", "Hello", "there"]
              @?= Right
                AskOptions
                  { askProviderOverride = Just PreferAnthropic,
                    askPromptWords = ["Hello", "there"]
                  },
          testCase "flag after prompt words works too" $
            parseAskArgs ["Hi", "--provider", "gemini"]
              @?= Right
                AskOptions
                  { askProviderOverride = Just PreferGemini,
                    askPromptWords = ["Hi"]
                  },
          testCase "flag interleaved with prompt words" $
            parseAskArgs ["one", "--provider", "gemini", "two"]
              @?= Right
                AskOptions
                  { askProviderOverride = Just PreferGemini,
                    askPromptWords = ["one", "two"]
                  },
          testCase "later flag occurrence wins" $
            parseAskArgs ["--provider", "anthropic", "--provider", "gemini", "x"]
              @?= Right
                AskOptions
                  { askProviderOverride = Just PreferGemini,
                    askPromptWords = ["x"]
                  },
          testCase "`--` ends flag parsing" $
            parseAskArgs ["--provider", "gemini", "--", "--provider", "is", "a", "flag"]
              @?= Right
                AskOptions
                  { askProviderOverride = Just PreferGemini,
                    askPromptWords = ["--provider", "is", "a", "flag"]
                  },
          testCase "--provider without value is error" missingFlagValue,
          testCase "--provider with unknown value is error" unknownFlagValue
        ]
    ]

missingFlagValue :: Assertion
missingFlagValue = case parseAskArgs ["--provider"] of
  Left msg ->
    assertBool
      ("message should mention provider name requirement, got: " <> msg)
      ("requires" `isInfixOf` msg)
  Right opts ->
    fail ("expected Left but got Right: " <> show opts)

unknownFlagValue :: Assertion
unknownFlagValue = case parseAskArgs ["-p", "llama", "prompt"] of
  Left msg ->
    assertBool
      ("message should mention the unknown value, got: " <> msg)
      ("llama" `isInfixOf` msg)
  Right opts ->
    fail ("expected Left but got Right: " <> show opts)
