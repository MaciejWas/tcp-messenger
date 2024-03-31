{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}

module ParserSpec (parserSpec) where

import Control.Concurrent.STM (STM, atomically)
import Control.Concurrent.STM.TVar (modifyTVar, newTVarIO, readTVar, writeTVar)
import Control.Monad (replicateM, unless)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.Maybe (fromMaybe)
import Data.Serialize (Serialize)
import TcpMsg.Data (Header (Header), Message (Message), UnixMsgTime, encodeMsg)
import TcpMsg.Effects.Connection
  ( Connection (..),
    ConnectionHandle (ConnectionHandle),
    ConnectionHandleRef,
    ConnectionInfo (ConnectionInfo),
    mkConnection,
  )
import Test.QuickCheck.Instances.ByteString ()
import TcpMsg.Parsing (parseHeader, parseMsg)
import Test.Hspec
  ( describe,
    it,
  )
import Test.QuickCheck (Testable (property))
import Test.QuickCheck.Monadic (assert, monadicIO, run)

data MockConnStream
  = MockConnStream
      BS.StrictByteString -- input
      BS.StrictByteString -- output

testConnHandle :: BS.StrictByteString -> ConnectionHandle MockConnStream
testConnHandle input = ConnectionHandle (ConnectionInfo mempty) (MockConnStream input mempty)

testConn ::
  ConnectionHandleRef MockConnStream ->
  Maybe Int ->
  IO (Connection MockConnStream)
testConn connHandleRef maxRead = do
  mkConnection connHandleRef mockConnStreamRead mockConnStreamWrite
  where
    mockConnStreamWrite :: BS.StrictByteString -> IO ()
    mockConnStreamWrite bytes = atomically go
      where
        go :: STM ()
        go = modifyTVar connHandleRef (\(ConnectionHandle info (MockConnStream inp outp)) -> ConnectionHandle info (MockConnStream inp (outp <> bytes)))

    mockConnStreamRead :: Int -> IO BS.StrictByteString
    mockConnStreamRead size = atomically go
      where
        go :: STM BS.StrictByteString
        go = do
          (ConnectionHandle info (MockConnStream inp outp)) <- readTVar connHandleRef
          let actualsize = min size (fromMaybe size maxRead) -- Restrict size of returned bytestring
          let (read, remain) = BS.splitAt actualsize inp
          writeTVar connHandleRef (ConnectionHandle info (MockConnStream remain outp))
          return read

connectionWhichYields ::
  (Serialize a) =>
  [(UnixMsgTime, Message a)] ->
  IO (Connection MockConnStream)
connectionWhichYields messages =
  let inputStream = foldl (<>) mempty (map (uncurry encodeMsg) messages)
      testHandle = testConnHandle inputStream
   in do
        testHandleRef <- newTVarIO testHandle
        testConn testHandleRef Nothing

connectionWhichYieldsAndLimitsBytes ::
  (Serialize a) =>
  [(UnixMsgTime, Message a)] ->
  IO (Connection MockConnStream)
connectionWhichYieldsAndLimitsBytes messages =
  let inputStream = foldl (<>) mempty (map (uncurry encodeMsg) messages)
      testHandle = testConnHandle inputStream
   in do
        testHandleRef <- newTVarIO testHandle
        testConn testHandleRef (Just 10)

--------------------------------------------------------------------------------------------------------------------------------------------------------

parserSpec = do
  describe "Data" $ do
    describe "encodeMsg" $ do
      it "creates a message which contains the payload" $ do
        property $ \(messageId :: UnixMsgTime) (payload :: BS.ByteString) -> BS.isInfixOf payload (encodeMsg messageId (Message payload Nothing))

  describe "Parsing" $ do
    describe "parseHeader" $ do
      it "parses message id" $ do
        property $ \(messageId :: UnixMsgTime) (payload :: BS.ByteString) -> monadicIO $ do
          (Header responseMsgId _ _) <- run (connectionWhichYields [(messageId, Message payload Nothing)] >>= parseHeader)
          assert (responseMsgId == messageId)

      it "parses message size" $ do
        property $ \(messageId :: UnixMsgTime) (payload :: BS.ByteString) -> monadicIO $ do
          (Header _ sizeOfData _) <- run (connectionWhichYields [(messageId, Message payload Nothing)] >>= parseHeader)
          assert (sizeOfData >= BS.length payload)

      it "parses trunk size" $ do
        property $ \(messageId :: UnixMsgTime) (trunk :: Maybe LBS.ByteString) -> monadicIO $ do
          (Header _ _ sizeOfTrunk) <- run (connectionWhichYields [(messageId, Message () trunk)] >>= parseHeader)
          case trunk of
            Nothing -> assert (sizeOfTrunk == 0)
            Just x -> assert (sizeOfTrunk == LBS.length x)

    describe "parseMsg" $ do
      it "parses message body (bytestring)" $ do
        property $ \(messageId :: UnixMsgTime) (payload :: BS.ByteString) -> monadicIO $ do
          (_, Message body trunk) <- run (connectionWhichYields [(messageId, Message payload Nothing)] >>= parseMsg)
          assert (body == payload)

      it "parses message body (int)" $ do
        property $ \(messageId :: UnixMsgTime) (payload :: Int) -> monadicIO $ do
          (_, Message body trunk) <- run (connectionWhichYields [(messageId, Message payload Nothing)] >>= parseMsg)
          assert (body == payload)

      it "parses message body (tuple)" $ do
        property $ \(messageId :: UnixMsgTime) (payload :: (String, Int, ())) -> monadicIO $ do
          (_, Message body trunk) <- run (connectionWhichYields [(messageId, Message payload Nothing)] >>= parseMsg)
          assert (body == payload)

      it "parses message body (list of tuples)" $ do
        property $ \(messageId :: UnixMsgTime) (payload :: [(String, Int, ())]) -> monadicIO $ do
          (_, Message body trunk) <- run (connectionWhichYields [(messageId, Message payload Nothing)] >>= parseMsg)
          assert (body == payload)

      it "parses many messages" $ do
        property $ \(messageId :: UnixMsgTime) (payloads :: [(String, Int, Bool)]) -> monadicIO $ do
          unless (null payloads) $ do
            let messages = map (\p -> (messageId, Message p Nothing)) payloads
            received <-
              run
                ( connectionWhichYields messages
                    >>= \conn -> replicateM (length payloads) (parseMsg conn)
                )
            mapM_
              (\(payload, (Header _ _ _, Message body trunk)) -> assert (body == payload))
              (zip payloads received)

      describe "when connection is limited" $ do
        it "parses message body (tuple)" $ do
          property $ \(messageId :: UnixMsgTime) (payload :: (String, Int, ())) -> monadicIO $ do
            (_, Message body trunk) <- run (connectionWhichYieldsAndLimitsBytes [(messageId, Message payload Nothing)] >>= parseMsg)
            assert (body == payload)

        it "parses many messages" $ do
          property $ \(messageId :: UnixMsgTime) (payloads :: [(String, Int, Bool)]) -> monadicIO $ do
            unless (null payloads) $ do
              let messages = map (\p -> (messageId, Message p Nothing)) payloads
              received <-
                run
                  ( connectionWhichYieldsAndLimitsBytes messages
                      >>= \conn -> replicateM (length payloads) (parseMsg conn)
                  )
              mapM_
                (\(payload, (Header _ _ _, Message body trunk)) -> assert (body == payload))
                (zip payloads received)
