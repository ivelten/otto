-- |
-- Module      : Main
-- Description : Top-level @tasty@ test runner for Otto.
--
-- Tests are grouped by module under 'tests'. As modules are added, their
-- own test trees are imported here and combined with 'testGroup'.
module Main (main) where

import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "otto"
    [ testCase "scaffold compiles and links" $
        (1 + 1 :: Int) @?= 2
    ]
