{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

{-# HLINT ignore "Use <&>" #-}

module TcpMsg.Peer.Abstract where

import Control.Concurrent (ThreadId, forkIO)
import Control.Concurrent.Async (mapConcurrently_)
import qualified Control.Concurrent.STM as STM
import qualified Control.Concurrent.STM.TChan as STMChan
import Control.Exception (Exception)
import qualified Control.Exception as Exception
import Control.Monad (forever, unless, void)
import qualified Control.Monad.Catch as Catch
import Data.Serialize (Serialize)
import Data.UnixTime (getUnixTime)
import GHC.Generics (Generic)
import Network.Socket (HostName)
import TcpMsg.Connection (Connection)
import TcpMsg.Data (Message (Message), UnixMsgTime, fromUnix)
import TcpMsg.Parsing (parseMsg)

----------------------------------------------------------------------------------------------------------

-- | A message sent from a peer. It can be either a data message or a message indicating a new peer.
data PeerMsg a
  = JustData a
  | NewPeer HostName
  deriving (Eq, Generic)

instance (Serialize a) => Serialize (PeerMsg a)

----------------------------------------------------------------------------------------------------------

-- | A queue of messages sent from a peer
type Incoming a =
  STMChan.TChan
    (Message (PeerMsg a))

-- | A queue of messages to be sent to a peer
type Outgoing a =
  STMChan.TChan
    (Message (PeerMsg a))

data PeerState
  = Healthy
  | HadIOErr Exception.IOException

data PeerWorkers = PeerWorkers
  { -- | Thread which sends messages to the peer
    writer :: ThreadId,
    -- | Thread which reads messages from the peer
    reader :: ThreadId
  }

data PeerHandle a c
  = PeerHandle
  { -- | The hostname of the peer
    hostName :: HostName,
    -- | The connection to the peer
    connection :: Connection c,
    -- | The incoming message queue
    incoming :: Incoming a,
    -- | The outgoing message queue
    outgoing :: Outgoing a,
    -- | The state of the peer
    peerState :: STM.TVar PeerState,
    -- | The threads which handle the peer
    workers :: STM.TVar PeerWorkers
  }

type OtherPeers a c = [PeerHandle a c]

----------------------------------------------------------------------------------------------------------

data ThisPeer a c = ThisPeer
  { otherPeers :: STM.TVar (OtherPeers a c),
    thisPeerId :: ClientId,
    initPeerConn :: HostName -> IO (Connection c)
  }

----------------------------------------------------------------------------------------------------------

broadcast :: forall a c. ThisPeer a c -> Message a -> IO ()
broadcast thisPeer msg =
  STM.atomically
    ( withOtherPeersSTM
        thisPeer
        (mapM_ sendToPeer)
    )
  where
    sendToPeer (PeerHandle {outgoing}) =
      STMChan.writeTChan
        outgoing
        (fmap JustData msg)

----------------------------------------------------------------------------------------------------------

-- | Initialize a peer handle. This function should be called when a new peer is discovered.
--   It initializes the incoming and outgoing message queues and the peer state.
initPeer :: HostName -> Connection c -> IO (PeerHandle a c)
initPeer hostname conn = do
  incomingChan <- STMChan.newBroadcastTChanIO
  outgoingChan <- STMChan.newTChanIO
  peerStateVar <- STM.newTVarIO Healthy
  workerthreads <- STM.newTVarIO (PeerWorkers {})
  return
    ( PeerHandle
        { hostName = hostname,
          connection = conn,
          incoming = incomingChan,
          outgoing = outgoingChan,
          peerState = peerStateVar,
          workers = workerthreads
        }
    )

----------------------------------------------------------------------------------------------------------

newPeerDiscovered :: forall a c. (Serialize a) => ThisPeer a c -> HostName -> IO ()
newPeerDiscovered thisPeer@ThisPeer {otherPeers} peerHostName = do
  isKnown <-
    STM.atomically
      ( STM.readTVar otherPeers
          >>= return . any ((== peerHostName) . hostName)
      )

  unless isKnown $ do
    conn <- initPeerConn thisPeer peerHostName
    peerHandle <- initPeer peerHostName conn
    STM.atomically (STM.modifyTVar otherPeers (peerHandle :))
    workPeer thisPeer peerHandle

----------------------------------------------------------------------------------------------------------

-- | Start the worker threads for all peers. This function should be called when this peer is initialized.
--   It starts two threads for each peer: one for reading incoming messages and one for sending outgoing messages.
startPeersWorker :: forall a c. (Serialize a) => ThisPeer a c -> IO ()
startPeersWorker thisPeer =
  withOtherPeers
    thisPeer
    (mapConcurrently_ (workPeer @a thisPeer))

-- Start two threads: one listens for new message and other reads
workPeer :: (Serialize a) => ThisPeer a c -> PeerHandle a c -> IO ()
workPeer thisPeer (PeerHandle {connection, incoming, peerState, workers}) = do
  readerThread <-
    forkIO -- Create a thread which parses incoming messages
      ( Catch.catch
          ( forever $ do
              (_, msg) <- parseMsg connection
              case msg of
                Message (JustData x) bs -> STM.atomically (STMChan.writeTChan incoming (Message x bs))
                Message (NewPeer peerHostName) _ -> newPeerDiscovered thisPeer peerHostName
          )
          (STM.atomically . STM.modifyTVar peerState . const . HadIOErr)
      )
  writerThread <-
    forkIO -- Create a thread which dispatches outgoing messages
      ( Catch.catch
          ( forever $ do
              msg <- STM.atomically (STMChan.readTChan incoming)
              msgTime <- newMessageId
              sendMessage connection msgTime msg
          )
          (STM.atomically . STM.modifyTVar peerState . const . HadIOErr)
      )
  (STM.atomically . STM.writeTVar workers)
    (PeerWorkers readerThread writerThread)

----------------------------------------------------------------------------------------------------------
-- UTILS

doWith :: STM.TVar a -> (a -> STM.STM ()) -> STM.STM ()
doWith var operation = STM.readTVar var >>= operation

-- | Take other peers and perform an operation
withOtherPeers :: ThisPeer a c -> (OtherPeers a c -> IO b) -> IO b
withOtherPeers (ThisPeer {otherPeers}) operation = do
  peers <- STM.atomically (STM.readTVar otherPeers)
  operation peers

-- | Take other peers and perform an STM operation
withOtherPeersSTM :: ThisPeer a c -> (OtherPeers a c -> STM.STM b) -> STM.STM b
withOtherPeersSTM (ThisPeer {otherPeers}) operation = STM.readTVar otherPeers >>= operation

newMessageId :: IO UnixMsgTime
newMessageId = fromUnix <$> getUnixTime
