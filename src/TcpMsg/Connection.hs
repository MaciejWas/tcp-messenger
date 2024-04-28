{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module TcpMsg.Connection where

import Control.Concurrent (MVar, ThreadId, newMVar, withMVar, forkIO)
import qualified Control.Concurrent.STM as STM
import Control.Concurrent.STM.TVar (TVar)
import Control.Monad (forever)
import qualified Data.ByteString as BS
import Data.Serialize (Serialize)
import qualified GHC.IO.Device as STM
import Network.Socket (Socket)
import TcpMsg.Data (FullMessage (..), Header, Message (Message), MessageId, UnixMsgTime, msgId, prepare, serializeMsg)
import TcpMsg.Parsing (parseMsg)

----------------------------------------------------------------------------------------------------------

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

type ConnectionRead = Int -> IO BS.StrictByteString

type ConnectionWrite = BS.StrictByteString -> IO ()

----------------------------------------------------------------------------------------------------------

-- All necessary operations to handle a connection
data Connection c a b
  = Connection
  { chandle :: ConnectionHandleRef c, -- Metadata about the connection
    incoming :: STM.TChan (FullMessage a), -- Incoming messages
    outgoing :: STM.TChan (FullMessage b) -- Outgoing messages
  }

-- Start connection worker
startWriter ::
  ConnectionWrite ->
  STM.TChan (FullMessage a) ->
  IO ()
startWriter connWrite outgoingChan = do
  forever ((STM.atomically . STM.readTChan) outgoingChan >>= (connWrite . serializeMsg))

startReader ::
  forall a.
  (Serialize a) =>
  ConnectionRead ->
  STM.TChan (FullMessage a) ->
  IO ()
startReader connRead incomingChan = do
  forever (parseMsg @a connRead >>= STM.atomically . STM.writeTChan incomingChan)

mkConnection ::
  forall a b c.
  (Serialize a) =>
  c ->
  ConnectionRead ->
  ConnectionWrite ->
  IO (Connection c a b)
mkConnection conn connread connwrite = do
  outgoingWriter <- STM.newBroadcastTChanIO
  incomingWriter <- STM.newBroadcastTChanIO

  -- \| Duplicate channel the because `outgoingWriter` is write-only
  outgoingWriter' <- STM.atomically $ STM.dupTChan outgoingWriter

  writerThread <- forkIO (startWriter @b connwrite outgoingWriter')
  readerThread <- forkIO (startReader @a connread incomingWriter)

  handle <- STM.atomically $ STM.newTVar (ConnectionHandle (PeerWorkers writerThread readerThread) conn)

  return (Connection handle incomingWriter outgoingWriter')

-- | Read the message from the connection
-- If there is no message, the function will block
nextMessage :: Connection c a b  -> IO (FullMessage a)
nextMessage Connection {incoming} = STM.atomically $ STM.readTChan incoming

-- | Write the message to the connection
-- The message will not be sent immediately, but rather put into the outgoing queue
dispatchMessage :: (Serialize b) => Connection c a b -> Message b -> IO MessageId
dispatchMessage Connection {outgoing} msg = do
  fullMessage <- prepare msg
  STM.atomically $ STM.writeTChan outgoing fullMessage
  return (msgId fullMessage)

reply ::
  forall a b c.
  ( Serialize b ) =>
  Connection c a b ->
  (Message a -> IO (Message b)) ->
  IO ()
reply conn@Connection{incoming} respond = do
  incoming' <- STM.atomically $ STM.dupTChan incoming
  forever (do
    FullMessage _ msg _ <- STM.atomically $ STM.readTChan incoming'
    response <- respond msg
    dispatchMessage conn response 
    )