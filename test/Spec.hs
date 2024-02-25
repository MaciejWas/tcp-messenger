{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

import Control.Concurrent (MVar)
import Control.Exception (evaluate)
import qualified Data.ByteString as BS
import Data.Serialize (Serialize)
import qualified Data.Text as T
import Effectful
  ( Dispatch (Static),
    DispatchOf,
    Eff,
    Effect,
    IOE,
    runEff,
    (:>),
  )
import Effectful.Concurrent (Concurrent, runConcurrent)
import Effectful.Concurrent.MVar (newMVar, withMVar)
import Effectful.Concurrent.STM (STM, atomically, modifyTVar, newTVar, newTVarIO, readTVar, writeTVar)
import GHC.Base (undefined)
import TcpMsg.Connection
  ( ConnectionActions (ConnectionActions),
    ConnectionHandle (ConnectionHandle),
    ConnectionHandleRef,
    ConnectionInfo (ConnectionInfo),
    mkConnectionActions,
  )
import TcpMsg.Data (mkMsg)
import Test.Hspec
  ( anyException,
    describe,
    hspec,
    it,
    shouldBe,
    shouldThrow,
  )
import Test.QuickCheck (Testable (property))
import Test.QuickCheck.Instances.ByteString

data MockConnStream
  = MockConnStream
      BS.StrictByteString -- input
      BS.StrictByteString -- output

mockConnStreamWrite :: ConnectionHandleRef MockConnStream -> BS.StrictByteString -> IO ()
mockConnStreamWrite conn bytes = runEff (runConcurrent (atomically go))
  where
    go :: STM ()
    go = modifyTVar conn (\(ConnectionHandle info (MockConnStream inp outp)) -> ConnectionHandle info (MockConnStream inp (outp <> bytes)))

mockConnStreamRead :: ConnectionHandleRef MockConnStream -> Int -> IO BS.StrictByteString
mockConnStreamRead conn size = runEff (runConcurrent (atomically go))
  where
    go :: STM BS.StrictByteString
    go = do
      (ConnectionHandle info (MockConnStream inp outp)) <- readTVar conn
      let (read, remain) = BS.splitAt size inp
      writeTVar conn (ConnectionHandle info (MockConnStream remain outp))
      return read

testConnHandle :: BS.StrictByteString -> ConnectionHandle MockConnStream
testConnHandle input = ConnectionHandle (ConnectionInfo mempty) (MockConnStream input mempty)

testConnActions ::
  forall es.
  (Concurrent :> es) =>
  ConnectionHandleRef MockConnStream ->
  Eff es (ConnectionActions MockConnStream)
testConnActions connHandleRef = mkConnectionActions connHandleRef mockConnStreamRead mockConnStreamWrite

main :: IO ()
main = hspec $ do
  describe "TcpMsg" $ do
    describe "Data" $ do
      describe "mkMsg" $ do
        it "encodes arbitrary payload" $ do
          property $ \(messageId :: Int) (payload :: BS.ByteString) -> BS.length (mkMsg messageId payload) > 0

    describe "ParsingBuffers" $ do
      describe "parseHeader" $ do
        it "parses arbitrary header" $ do
          property $ inConnectionContext (\inputStream -> ...)

inConnectionContext ::
  forall es c a.
  (Serialize a, Conn c :> es) =>
  [(Int, a)] ->
  Eff es Bool ->
  IO Bool
inConnectionContext = undefined

testParsesArbitraryHeader :: Int -> BS.ByteString -> IO ()
testParsesArbitraryHeader messageId content =
  let msg = mkMsg messageId content
      mock = testConnHandle msg
   in do
        (runEff . runConcurrent)
          (newTVarIO mock >>= testConnActions >> return ())

-- QuickCheck
-- (id, payload) -> ByteString ->

-- it "returns the first element of a list" $ do
--   head [23 ..] `shouldBe` (23 :: Int)

-- it "returns the first element of an *arbitrary* list" $
--   property $ \x xs -> head (x:xs) == (x :: Int)

-- it "throws an exception if used with an empty list" $ do
--   evaluate (head []) `shouldThrow` anyException