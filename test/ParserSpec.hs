{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}

module ParserSpec (parserSpec) where

import Control.Concurrent (newMVar)
import Control.Concurrent.STM (atomically)
import Control.Concurrent.STM.TVar (modifyTVar, newTVarIO, readTVar, writeTVar)
import Control.Monad (replicateM, unless)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.Maybe (fromMaybe)
import Data.Serialize (Serialize)
import System.Random (randomRIO)
import TcpMsg.Connection
  ( Connection (..),
    ConnectionHandle (ConnectionHandle),
  )
import TcpMsg.Data (FullMessage (FullMessage), Header (Header), Message (Message), MessageId (MessageId), prepare, prepareWithId, serializeMsg, setId)
import TcpMsg.Parsing (parseHeader, parseMsg)
import Test.Hspec
  ( describe,
    it,
  )
import Test.QuickCheck (Testable (property))
import Test.QuickCheck.Arbitrary (Arbitrary, arbitrary)
import Test.QuickCheck.Instances.ByteString ()
import Test.QuickCheck.Monadic (assert, monadicIO, run)

data MockConnStream
  = MockConnStream
      BS.StrictByteString -- input
      BS.StrictByteString -- output

testConn ::
  MockConnStream ->
  Maybe Int ->
  IO (Connection MockConnStream)
testConn mockStream maxRead = do
  writerLock <- newMVar ()
  readerLock <- newMVar ()
  handle <- newTVarIO (ConnectionHandle mockStream)

  -- mockConnStreamWrite :: BS.StrictByteString -> IO ()
  let mockConnStreamWrite bytes = atomically (modifyTVar handle (\(ConnectionHandle (MockConnStream inp outp)) -> ConnectionHandle (MockConnStream inp (outp <> bytes))))

  -- mockConnStreamRead :: Int -> IO BS.StrictByteString
  let mockConnStreamRead size = do
        actualSize <- randomRIO (1, size) -- Simulate a network which doesn't always return the requested size
        atomically
          ( do
              (ConnectionHandle (MockConnStream inp outp)) <- readTVar handle
              let (read, remain) = BS.splitAt actualSize inp
              writeTVar handle (ConnectionHandle (MockConnStream remain outp))
              return read
          )

  return (Connection handle mockConnStreamRead mockConnStreamWrite writerLock readerLock)

connectionWhichYields ::
  (Serialize a) =>
  [(MessageId, Message a)] ->
  IO (Connection MockConnStream)
connectionWhichYields messages = do
  preparedMessages <-
    mapM
      ( \(messageId, message) ->
          ( do
              fullmsg <- prepare message
              return (setId messageId fullmsg)
          )
      )
      messages

  let inputStream = foldl (<>) mempty (map serializeMsg preparedMessages)

  testConn (MockConnStream inputStream mempty) Nothing

instance Arbitrary MessageId where
  arbitrary = MessageId <$> arbitrary

--------------------------------------------------------------------------------------------------------------------------------------------------------

parserSpec = do
  describe "Data" $ do
    describe "encodeMsg" $ do
      it "creates a message which contains the payload" $ do
        property $ \(messageId :: MessageId) (payload :: BS.ByteString) -> BS.isInfixOf payload (serializeMsg (prepareWithId messageId (Message payload Nothing)))

  describe "Parsing" $ do
    describe "parseHeader" $ do
      it "parses message id" $ do
        property $ \(messageId :: MessageId) (payload :: BS.ByteString) -> monadicIO $ do
          (Header responseMsgId _ _) <- run (connectionWhichYields [(messageId, Message payload Nothing)] >>= parseHeader)
          assert (responseMsgId == messageId)

      it "parses message size" $ do
        property $ \(messageId :: MessageId) (payload :: BS.ByteString) -> monadicIO $ do
          (Header _ sizeOfData _) <- run (connectionWhichYields [(messageId, Message payload Nothing)] >>= parseHeader)
          assert (sizeOfData >= BS.length payload)

      it "parses trunk size" $ do
        property $ \(messageId :: MessageId) (trunk :: Maybe LBS.ByteString) -> monadicIO $ do
          (Header _ _ sizeOfTrunk) <- run (connectionWhichYields [(messageId, Message () trunk)] >>= parseHeader)
          case trunk of
            Nothing -> assert (sizeOfTrunk == 0)
            Just x -> assert (sizeOfTrunk == LBS.length x)

    describe "parseMsg" $ do
      it "parses message body (bytestring)" $ do
        property $ \(messageId :: MessageId) (payload :: BS.ByteString) -> monadicIO $ do
          (FullMessage _ (Message body _) _) <- run (connectionWhichYields [(messageId, Message payload Nothing)] >>= parseMsg)
          assert (body == payload)

      it "parses message body (int)" $ do
        property $ \(messageId :: MessageId) (payload :: Int) -> monadicIO $ do
          (FullMessage _ (Message body _) _) <- run (connectionWhichYields [(messageId, Message payload Nothing)] >>= parseMsg)
          assert (body == payload)

      it "parses message body (tuple)" $ do
        property $ \(messageId :: MessageId) (payload :: (String, Int, ())) -> monadicIO $ do
          (FullMessage _ (Message body _) _) <- run (connectionWhichYields [(messageId, Message payload Nothing)] >>= parseMsg)
          assert (body == payload)

      it "parses message body (list of tuples)" $ do
        property $ \(messageId :: MessageId) (payload :: [(String, Int, ())]) -> monadicIO $ do
          (FullMessage _ (Message body _) _) <- run (connectionWhichYields [(messageId, Message payload Nothing)] >>= parseMsg)
          assert (body == payload)

      it "parses many messages" $ do
        property $ \(messageId :: MessageId) (payloads :: [(String, Int, Bool)]) -> monadicIO $ do
          unless (null payloads) $ do
            let messages = map (\p -> (messageId, Message p Nothing)) payloads
            received <-
              run
                ( connectionWhichYields messages
                    >>= \conn -> replicateM (length payloads) (parseMsg conn)
                )
            mapM_
              (\(payload, FullMessage _ (Message body _) _) -> assert (body == payload))
              (zip payloads received)