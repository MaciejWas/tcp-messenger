{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module TcpMsg.Connection where

import Control.Concurrent (MVar, newMVar, withMVar, ThreadId)
import Control.Concurrent.STM.TVar (TVar)

import qualified Control.Concurrent.STM as STM

import qualified Data.ByteString as BS
import Data.Serialize (Serialize)

import TcpMsg.Data (ClientId, Message (Message), UnixMsgTime, serializeMsg, Header, addHeader)
import TcpMsg.Parsing (parseMsg)

import Network.Socket (Socket)
import qualified Control.Concurrent.STM as STM
import Control.Monad (forever)
import qualified GHC.IO.Device as STM

----------------------------------------------------------------------------------------------------------

type MessageID = Int

data PeerWorkers = PeerWorkers
  { -- | Thread which sends messages to the peer
    peerWriter :: ThreadId,
    -- | Thread which reads messages from the peer
    peerReader :: ThreadId
  }

-- | A connection handle which is used by the parent thread to refer to the thread which is handling the connection
data ConnectionHandle a
  = ConnectionHandle
      PeerWorkers
      a -- Some protocol-specific data. E.g. client socket address

type ConnectionHandleRef a = TVar (ConnectionHandle a)

type ConnectionRead a = Int -> IO BS.StrictByteString

type ConnectionWrite a = BS.StrictByteString -> IO ()

----------------------------------------------------------------------------------------------------------

-- All necessary operations to handle a connection
data Connection a
  = Connection
  { chandle :: ConnectionHandleRef a, -- Metadata about the connection
    incoming :: STM.TChan (Header, Message a), -- Incoming messages
    outgoing :: STM.TChan (Header, Message a) -- Outgoing messages
  }

-- Start connection worker
startWriter ::
  ConnectionWrite a ->
  STM.TChan (Header, Message a) ->
  IO ()
startWriter connWrite outgoingChan = do
  forever ((STM.atomically . STM.readTChan) outgoingChan >>= (connWrite . serializeMsg))

startReader ::
  forall a.
  ConnectionRead a ->
  STM.TChan (Header, Message a) ->
  IO ()
startReader connRead incomingChan = do
  forever (parseMsg @a connRead >>= STM.atomically . STM.writeTChan incomingChan)

mkConnection ::
  ConnectionHandleRef a ->
  ConnectionRead a ->
  ConnectionWrite a ->
  IO (Connection a)
mkConnection handle connread connwrite = do
  outgoingWriter <- STM.newBroadcastTChanIO
  incomingWriter <- STM.newBroadcastTChanIO
  incomingReader <- STM.atomically $ STM.dupTChan incomingWriter

  startWriter connwrite outgoingWriter
  startReader connread incomingWriter

  return (Connection handle incomingReader outgoingWriter)


nextMessage :: Connection a -> IO (Header, Message a)
nextMessage Connection {incoming} = STM.atomically $ STM.readTChan incoming

dispatchMessage :: Connection a -> Message a -> IO UnixMsgTime
dispatchMessage Connection {outgoing} msg = do
  time <- newMessageId
  let header = addHeader time msg
  STM.atomically $ STM.writeTChan outgoing 
  

sendMessage ::
  (Serialize a) =>
  Connection c ->
  UnixMsgTime ->
  Message a ->
  IO ()
sendMessage c messageId message = writeBytes c (encodeMsg messageId message)

newMessageId :: IO UnixMsgTime
newMessageId = fromUnix <$> getUnixTime
