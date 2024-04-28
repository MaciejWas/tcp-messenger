{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE ScopedTypeVariables #-}

module TcpMsg.Connection where

import Control.Concurrent (MVar, newMVar, withMVar)
import Control.Concurrent.STM.TVar (TVar, newTVarIO)
import qualified Data.ByteString as BS
import Data.Serialize (Serialize)
import TcpMsg.Data (Message, MessageId, msgId, prepare, prepareWithId, serializeMsg, setId)

----------------------------------------------------------------------------------------------------------

type Mutex = MVar ()

-- | A connection handle which is used by the parent thread to refer to the thread which is handling the connection
newtype ConnectionHandle a
  = ConnectionHandle a -- Some protocol-specific data. E.g. client socket address

type ConnectionHandleRef a = TVar (ConnectionHandle a)

type ConnectionRead = Int -> IO BS.StrictByteString

type ConnectionWrite = BS.StrictByteString -> IO ()

-- All necessary operations to handle a connection
data Connection a
  = Connection
  { chandle :: ConnectionHandleRef a, -- Metadata about the connection
    readBytes :: ConnectionRead, -- Interface for receiving bytes
    cwrite :: ConnectionWrite, -- Interface for sending bytes
    cwriterMutex :: Mutex, -- So that only one thread can be writing to a connection on a given time
    creaderMutex :: Mutex -- So that only one thread can be reading from a connection on a given time
  }

mkConnection ::
  a ->
  ConnectionRead ->
  ConnectionWrite ->
  IO (Connection a)
mkConnection a connread connwrite = do
  writerLock <- newMVar ()
  readerLock <- newMVar ()
  handle <- newTVarIO (ConnectionHandle a)
  return (Connection handle connread connwrite writerLock readerLock)

writeBytes ::
  Connection c ->
  BS.StrictByteString ->
  IO ()
writeBytes (Connection {cwrite, cwriterMutex}) bytes =
  withMVar
    cwriterMutex
    (const (cwrite bytes))

sendMessageWithId ::
  (Serialize a) =>
  Connection c ->
  Message a ->
  MessageId ->
  IO ()
sendMessageWithId c message mid =
  let fullMsg = prepareWithId mid message
   in writeBytes c (serializeMsg fullMsg)

sendMessage ::
  (Serialize a) =>
  Connection c ->
  Message a ->
  IO MessageId
sendMessage c message = do
  fullMsg <- prepare message
  writeBytes c (serializeMsg fullMsg)
  return (msgId fullMsg)
