{-# LANGUAGE FlexibleContexts #-}

import Test.Hspec
import Data.Monoid
import Data.List
import Data.Maybe
import Control.Monad
import Control.Monad.RWS
import Control.Monad.Trans.Maybe
import qualified Data.Set as S
import Data.Tuple.Utils

type ProposalId = Int
type AcceptorId = String
type Value = String

data AcceptedMessage = Accepted ProposalId AcceptorId Value
  deriving (Show, Eq)

data LearnerState = LearnerState [AcceptedMessage]

learner :: (MonadState LearnerState m, MonadWriter [String] m) => AcceptedMessage -> m ()
learner newMessage@(Accepted proposalId acceptorId value) = do
  LearnerState previousMessages <- get
  put $ LearnerState $ newMessage : previousMessages
  when (any isMatch previousMessages) $ tell [value]

  where isMatch (Accepted proposalId' acceptorId' _)
          | proposalId /= proposalId' = False
          | acceptorId == acceptorId' = False
          | otherwise                 = True

data PromiseType = Free | Bound ProposalId Value deriving (Show, Eq)
data PromisedMessage = Promised ProposalId AcceptorId PromiseType deriving (Show, Eq)
data ProposedMessage = Proposed ProposalId Value deriving (Show, Eq)

data ProposerState = ProposerState (S.Set ProposalId) [PromisedMessage]

proposer :: (MonadState ProposerState m, MonadWriter [ProposedMessage] m, MonadReader Value m, Functor m) => PromisedMessage -> m ()
proposer newMessage@(Promised proposalId acceptorId promiseType) = do
  ProposerState proposalsMade previousMessages <- get
  unless (S.member proposalId proposalsMade) $ do
    put $ ProposerState proposalsMade $ newMessage : previousMessages
    void $ runMaybeT $ forM_ previousMessages proposeValueIfMatch

  where
  proposeValueIfMatch (Promised proposalId' acceptorId' promiseType') = when isMatch $ do
      value <- case (promiseType, promiseType') of
        (Bound pid1 val1, Bound pid2 val2)
          | pid1 < pid2   -> return val2
          | otherwise     -> return val1
        (Bound _ val1, _) -> return val1
        (_, Bound _ val2) -> return val2
        _                 -> ask
      tell [Proposed proposalId value]
      modify $ \(ProposerState proposalsMade msgs) -> ProposerState (S.insert proposalId proposalsMade) msgs
      mzero
    where isMatch
            | proposalId /= proposalId' = False
            | acceptorId == acceptorId' = False
            | otherwise                 = True

main :: IO ()
main = hspec $ do
  describe "Learner" $ learnerTest
    [(Accepted 1 "alice" "foo", [],      "should learn nothing with the first message")
    ,(Accepted 2 "brian" "bar", [],      "should learn nothing with a message for a different proposal")
    ,(Accepted 2 "brian" "bar", [],      "should learn nothing from a duplicate of the previous message")
    ,(Accepted 2 "chris" "bar", ["bar"], "should learn a value from another message for proposal 2")
    ]
  describe "Proposer" $ proposerTest
    [(Promised 1 "alice" Free,                      [], "should propose nothing from the first message")

    ,(Promised 2 "brian" Free,                      [], "should propose nothing from a message for a different proposal")
    ,(Promised 2 "brian" Free,                      [], "should propose nothing from a duplicate of the previous message")
    ,(Promised 2 "chris" Free,                      [Proposed 2 "my value"],
                                "should propose 'my value' with another promise")
    ,(Promised 2 "alice" Free,                      [], "should ignore another message for a proposal that's already been made")

    ,(Promised 3 "brian" Free,                      [], "should propose nothing from the first message of proposal 3")
    ,(Promised 3 "alice" (Bound 1 "alice's value"), [Proposed 3 "alice's value"],
                                "should propose the value given in the second promise")

    ,(Promised 4 "alice" (Bound 1 "alice's value"), [], "should propose nothing from the first message of proposal 4")
    ,(Promised 4 "brian" Free,                      [Proposed 4 "alice's value"],
                                "should propose the value given in the first promise")

    ,(Promised 5 "alice" (Bound 1 "alice's value"), [], "should propose nothing from the first message of proposal 5")
    ,(Promised 5 "brian" (Bound 2 "brian's value"), [Proposed 5 "brian's value"],
                                "should propose the value given in the second promise as it has the higher-numbered value")

    ,(Promised 6 "brian" (Bound 2 "brian's value"), [],  "should propose nothing from the first message of proposal 6")
    ,(Promised 6 "alice" (Bound 1 "alice's value"), [Proposed 6 "brian's value"],
                                "should propose the value given in the first promise as it has the higher-numbered value")
    ]

learnerTest :: [(AcceptedMessage, [String], String)] -> SpecWith ()
learnerTest testSeq = forM_ (inits testSeq) $ \ioPairs ->
  let inputs          =          map fst3 ioPairs
      expectedOutputs = concat $ map snd3 ioPairs
      worksAsExpected = last $ "should learn nothing from no messages" : map thd3 ioPairs
      (_, _, outputs) = runRWS (mapM_ learner inputs) () (LearnerState [])
  in it worksAsExpected $ outputs `shouldBe` expectedOutputs

proposerTest :: [(PromisedMessage, [ProposedMessage], String)] -> SpecWith ()
proposerTest testSeq = forM_ (inits testSeq) $ \ioPairs ->
  let inputs          =          map fst3 ioPairs
      expectedOutputs = concat $ map snd3 ioPairs
      worksAsExpected = last $ "should propose nothing from no messages" : map thd3 ioPairs
      (_, _, outputs) = runRWS (mapM_ proposer inputs) "my value" (ProposerState S.empty [])
  in it worksAsExpected $ outputs `shouldBe` expectedOutputs
