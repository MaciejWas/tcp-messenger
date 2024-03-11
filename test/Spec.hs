{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

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
import Effectful.Concurrent.STM (STM, atomically, modifyTVar, newTVar, newTVarIO, readTVar, writeTVar, readTVarIO)
import GHC.Base (undefined)
import TcpMsg.Effects.Connection
  ( ConnectionActions (ConnectionActions),
    ConnectionHandle (ConnectionHandle),
    ConnectionHandleRef,
    ConnectionInfo (ConnectionInfo),
    Conn,
    mkConnectionActions, runConnection,
  )
import TcpMsg.Data (mkMsg, Header (Header))
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
import Test.QuickCheck.Monadic (monadicIO, run, assert)
import TcpMsg.Parsing (parseMsg, parseHeader)

data MockConnStream
  = MockConnStream
      BS.StrictByteString -- input
      BS.StrictByteString -- output

testConnHandle :: BS.StrictByteString -> ConnectionHandle MockConnStream
testConnHandle input = ConnectionHandle (ConnectionInfo mempty) (MockConnStream input mempty)

testConnActions ::
  forall es.
  (Concurrent :> es) =>
  ConnectionHandleRef MockConnStream ->
  Eff es (ConnectionActions MockConnStream)
testConnActions connHandleRef = mkConnectionActions connHandleRef mockConnStreamRead mockConnStreamWrite
  where
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

inConnectionContext ::
  forall a x.
  (Serialize a) =>
  [(Int, a)] ->
  Eff '[Conn MockConnStream, Concurrent, IOE] x ->
  IO x
inConnectionContext messages action =
  let inputStream = foldl (<>) mempty (map (uncurry mkMsg) messages)
      testHandle = testConnHandle inputStream
  in runEff (runConcurrent (do
    testHandleRef <- newTVarIO testHandle
    connActions <- testConnActions testHandleRef
    runConnection connActions action
  ))

--------------------------------------------------------------------------------------------------------------------------------------------------------

main :: IO ()
main = hspec $ do
  describe "TcpMsg" $ do
    describe "Data" $ do
      describe "mkMsg" $ do
        it "creates a message which contains the payload" $ do
          property $ \(messageId :: Int) (payload :: BS.ByteString) -> BS.isInfixOf payload (mkMsg messageId payload)

    describe "ParsingBuffers" $ do
      describe "parseMsg" $ do
        it "parses a header" $ do
          property $ \(messageId :: Int) (payload :: BS.ByteString)  -> monadicIO $ do
            (Header responseMsgId _) <- run (inConnectionContext [(messageId, payload)] (parseHeader @MockConnStream))
            assert (responseMsgId == messageId)

        it "parses a message" $ do
          property $ \(messageId :: Int) (payload :: BS.ByteString)  -> monadicIO $ do
            (Header responseMsgId _, response) <- run (inConnectionContext [(messageId, payload)] (parseMsg @MockConnStream @BS.ByteString))
            assert (response == payload)
            assert (responseMsgId == messageId)


-- QuickCheck
-- (id, payload) -> ByteString ->

-- it "returns the first element of a list" $ do
--   head [23 ..] `shouldBe` (23 :: Int)

-- it "returns the first element of an *arbitrary* list" $
--   property $ \x xs -> head (x:xs) == (x :: Int)

-- it "throws an exception if used with an empty list" $ do
--   evaluate (head []) `shouldThrow` anyException