-- |
-- Module      : Otto.AI.Cli
-- Description : Argument parsing and CLI-specific messages for `otto ask`.
--
-- The executable accepts a small, hand-rolled flag grammar so no
-- 'optparse-applicative' dependency is needed. The parser is split out
-- into this module — separate from @app\/Main.hs@ — so it can be unit
-- tested exhaustively.
--
-- Grammar (inside @otto ask …@):
--
-- > [--provider NAME | -p NAME] PROMPT...
--
-- The @--provider@ flag may appear anywhere in the argument list; the
-- last occurrence wins. A literal @--@ ends flag parsing: every
-- following argument is treated as part of the prompt, even if it
-- starts with a dash.
--
-- Types and parsers shared with the non-CLI entry points
-- ('PreferredProvider', 'parseProviderName') live in "Otto.AI.Config"
-- alongside the other configuration concerns.
module Otto.AI.Cli
  ( AskOptions (..),
    parseAskArgs,
    missingKeyMessage,
  )
where

import Otto.AI.Config (PreferredProvider (..), parseProviderName)

-- | Parsed shape of @otto ask …@'s argument list.
data AskOptions = AskOptions
  { -- | 'Just' when the caller passed @--provider@/@-p@; 'Nothing'
    -- means defer to the environment variable.
    askProviderOverride :: Maybe PreferredProvider,
    -- | Remaining positional arguments — joined with spaces to form
    -- the prompt sent to the provider.
    askPromptWords :: [String]
  }
  deriving stock (Eq, Show)

-- | Parse the argument list that follows @ask@.
--
-- Returns a 'Left' with a human-readable message on malformed input
-- (missing flag value, unknown provider). Empty prompts are /not/ an
-- error here — the caller decides how to surface that — so an empty
-- 'askPromptWords' is a valid result.
--
-- ==== __Examples__
--
-- >>> parseAskArgs ["Hello", "world"]
-- Right (AskOptions {askProviderOverride = Nothing, askPromptWords = ["Hello","world"]})
--
-- >>> parseAskArgs ["--provider", "gemini", "Hi"]
-- Right (AskOptions {askProviderOverride = Just PreferGemini, askPromptWords = ["Hi"]})
--
-- >>> parseAskArgs ["-p", "anthropic", "--", "--flag-like", "prompt"]
-- Right (AskOptions {askProviderOverride = Just PreferAnthropic, askPromptWords = ["--flag-like","prompt"]})
parseAskArgs :: [String] -> Either String AskOptions
parseAskArgs = go (AskOptions Nothing [])
  where
    go acc [] = Right acc
    -- `--` ends flag parsing; everything after is literal prompt text.
    go acc ("--" : rest) =
      Right acc {askPromptWords = askPromptWords acc <> rest}
    go _ [flag]
      | flag `elem` providerFlags =
          Left (flag <> " requires a provider name")
    go acc (flag : name : rest)
      | flag `elem` providerFlags =
          case parseProviderName name of
            Left err -> Left err
            Right p -> go acc {askProviderOverride = Just p} rest
    go acc (word : rest) =
      go acc {askPromptWords = askPromptWords acc <> [word]} rest

    providerFlags = ["--provider", "-p"]

-- | Human-readable message shown when the caller invokes @otto ask@ but
-- the API key for the selected provider is not set.
missingKeyMessage :: PreferredProvider -> String
missingKeyMessage = \case
  PreferAnthropic ->
    "OTTO_ANTHROPIC_API_KEY is not set; cannot call `otto ask` with Anthropic."
  PreferGemini ->
    "OTTO_GEMINI_API_KEY is not set; cannot call `otto ask` with Gemini."
