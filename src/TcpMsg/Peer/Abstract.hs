{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module TcpMsg.Peer.Abstract where

import Control.Concurrent (ThreadId, forkIO)
import Control.Concurrent.Async (mapConcurrently_)
import qualified Control.Concurrent.STM as STM
import qualified Control.Concurrent.STM.TChan as STMChan
import Control.Exception (Exception)
import qualified Control.Exception as Exception
import Control.Monad (forever, void)
import qualified Control.Monad.Catch as Catch
import Data.Serialize (Serialize)
import Data.UnixTime (getUnixTime)
import GHC.Generics (Generic)
import Network.Socket (HostName)
import TcpMsg.Connection (Connection, sendMessage)
import TcpMsg.Data (ClientId, Message (Message), UnixMsgTime, fromUnix)
import TcpMsg.Parsing (parseMsg)

----------------------------------------------------------------------------------------------------------

data PeerMsg a
  = JustData a
  | NewPeer HostName
  deriving (Eq, Generic)

instance (Serialize a) => Serialize (PeerMsg a)

----------------------------------------------------------------------------------------------------------

type Incoming a =
  STMChan.TChan
    (Message (PeerMsg a))

type Outgoing a =
  STMChan.TChan
    (Message (PeerMsg a))

data PeerState
  = Healthy
  | HadIOErr Exception.IOException

data PeerWorkers = PeerWorkers {writer :: ThreadId, reader :: ThreadId}

data PeerHandle a c
  = PeerHandle
  { cid :: HostName,
    connection :: Connection c,
    incoming :: Incoming a,
    outgoing :: Outgoing a,
    peerState :: STM.TVar PeerState,
    workers :: STM.TVar PeerWorkers
  }

type OtherPeers a c = [PeerHandle a c]

----------------------------------------------------------------------------------------------------------

data Peer a c = Peer
  { otherPeers :: STM.TVar (OtherPeers a c),
    thisPeerId :: ClientId,
    initPeerConn :: HostName -> IO (Connection c)
  }

----------------------------------------------------------------------------------------------------------

newMessageId :: IO UnixMsgTime
newMessageId = fromUnix <$> getUnixTime

----------------------------------------------------------------------------------------------------------

broadcast :: forall a c. Peer a c -> Message a -> IO ()
broadcast (Peer {otherPeers}) msg =
  STM.atomically
    ( doWith
        otherPeers
        (mapM_ sendToPeer)
    )
  where
    sendToPeer (PeerHandle {outgoing}) =
      STMChan.writeTChan
        outgoing
        (fmap JustData msg)

----------------------------------------------------------------------------------------------------------

initPeer :: HostName -> Connection c -> IO (PeerHandle a c)
initPeer hostname conn = do
  incomingChan <- STMChan.newBroadcastTChanIO
  outgoingChan <- STMChan.newTChanIO
  peerStateVar <- STM.newTVarIO Healthy
  workerthreads <- STM.newTVarIO (PeerWorkers{})
  return
    ( PeerHandle
        { cid = hostname,
          connection = conn,
          incoming = incomingChan,
          outgoing = outgoingChan,
          peerState = peerStateVar,
          workers = workerthreads
        }
    )

----------------------------------------------------------------------------------------------------------

startPeersWorker :: forall a c. (Serialize a) => Peer a c -> IO ()
startPeersWorker (Peer {otherPeers, initPeerConn}) = do
  peers <- STM.atomically (STM.readTVar otherPeers)
  mapConcurrently_
    workPeer
    peers
  where
    -- Start two threads: one listens for new message and other reads
    workPeer :: PeerHandle a c -> IO ()
    workPeer (PeerHandle {connection, incoming, peerState, workers}) = do
      readerThread <-
        forkIO -- Create a thread which parses incoming messages
          ( Catch.catch
              ( forever $ do
                  (header, msg) <- parseMsg connection
                  case msg of
                    Message (JustData x) bs -> STM.atomically (STMChan.writeTChan incoming (Message x bs))
                    Message (NewPeer peerHostName) _ -> do
                      peerHandle <- initPeerConn peerHostName >>= initPeer peerHostName
                      STM.atomically (STM.modifyTVar otherPeers (peerHandle :))
                      workPeer peerHandle
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
