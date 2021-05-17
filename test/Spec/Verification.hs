{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}
{-# LANGUAGE RecordWildCards   #-}
module Spec.Verification
  ( specs
  ) where

import           Test.Tasty
import           Test.Tasty.HUnit

import           Biscuit
import           Datalog.AST      (Expression' (..), ID' (..), Query,
                                   QueryItem' (..))
import qualified Datalog.Executor as Executor
import           Datalog.Parser   (block, check, verifier)

specs :: TestTree
specs = testGroup "Datalog checks"
  [ singleBlock
  , unboundVarRule
  , symbolRestrictions
  , factsRestrictions
  ]

allowIfTrue :: Query
allowIfTrue = [QueryItem [] [EValue $ LBool True]]

singleBlock :: TestTree
singleBlock = testCase "Single block" $ do
  keypair <- newKeypair
  biscuit <- mkBiscuit keypair [block|right(#authority, "file1", #read);|]
  res <- verifyBiscuit biscuit [verifier|check if right(#authority, "file1", #read);allow if true;|] (publicKey keypair)
  res @?= Right allowIfTrue

unboundVarRule :: TestTree
unboundVarRule = testCase "Rule with unbound variable" $ do
  keypair <- newKeypair
  b1 <- mkBiscuit keypair [block|check if operation(#ambient, #read);|]
  b2 <- addBlock [block|operation($unbound, #read) <- operation($any1, $any2);|] b1
  res <- verifyBiscuit b2 [verifier|operation(#ambient,#write);allow if true;|] (publicKey keypair)
  res @?= Left (DatalogError $ Executor.FailedCheck [check|check if operation(#ambient, #read)|])

symbolRestrictions :: TestTree
symbolRestrictions = testGroup "Restricted symbols in blocks"
  [ testCase "In facts" $ do
      keypair <- newKeypair
      b1 <- mkBiscuit keypair [block|check if operation(#ambient, #read);|]
      b2 <- addBlock [block|operation(#ambient, #read);|] b1
      res <- verifyBiscuit b2 [verifier|allow if true;|] (publicKey keypair)
      res @?= Left (DatalogError $ Executor.FailedCheck [check|check if operation(#ambient, #read)|])
  , testCase "In rules" $ do
      keypair <- newKeypair
      b1 <- mkBiscuit keypair [block|check if operation(#ambient, #read);|]
      b2 <- addBlock [block|operation($ambient, #read) <- operation($ambient, $any);|] b1
      res <- verifyBiscuit b2 [verifier|operation(#ambient,#write);allow if true;|] (publicKey keypair)
      res @?= Left (DatalogError $ Executor.FailedCheck [check|check if operation(#ambient, #read)|])
  ]

factsRestrictions :: TestTree
factsRestrictions =
  let limits = defaultLimits { allowBlockFacts = False }
   in testGroup "No facts or rules in blocks"
        [ testCase "No facts" $ do
            keypair <- newKeypair
            b1 <- mkBiscuit keypair [block|right(#read);|]
            b2 <- addBlock [block|right(#write);|] b1
            res <- verifyBiscuitWithLimits limits b2 [verifier|allow if right(#write);|] (publicKey keypair)
            res @?= Left (DatalogError Executor.NoPoliciesMatched)
        , testCase "No rules" $ do
            keypair <- newKeypair
            b1 <- mkBiscuit keypair [block|right(#read);|]
            b2 <- addBlock [block|right(#write) <- right(#read);|] b1
            res <- verifyBiscuitWithLimits limits b2 [verifier|allow if right(#write);|] (publicKey keypair)
            res @?= Left (DatalogError Executor.NoPoliciesMatched)
        ]
