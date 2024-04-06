{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE DeriveGeneric #-}

module TcpMsg.Peer.Abstract where

import Control.Concurrent (forkIO)
import qualified Control.Concurrent as STM
import Control.Concurrent.Async (mapConcurrently_)
import Control.Concurrent.STM (TMVar)
import qualified Control.Concurrent.STM as STM
import qualified Control.Concurrent.STM.TChan as STMChan
import Control.Monad (forever, void)
import Data.Foldable (find)
import Data.Map (Map)
import qualified Data.Map as M
import Data.Maybe (listToMaybe)
import Data.Serialize (Serialize)
import Data.UnixTime (getUnixTime)
import TcpMsg.Client.Abstract (Client)
import TcpMsg.Connection (Connection, sendMessage)
import TcpMsg.Data (ClientId, Message (Message), UnixMsgTime, fromUnix)
import TcpMsg.Parsing (parseMsg)
import GHC.Generics (Generic)

----------------------------------------------------------------------------------------------------------

data PeerMsg a
  = JustData a
  | NewConn deriving (Eq, Generic)

instance Serialize a => Serialize (PeerMsg a)

----------------------------------------------------------------------------------------------------------

type Incoming a =
  STMChan.TChan
    (Message (PeerMsg a))

type Outgoing a =
  STMChan.TChan
    (Message (PeerMsg a))

data PeerState a c
  = PeerState
  { cid :: ClientId,
    connection :: Connection c,
    incoming :: Incoming a,
    outgoing :: Outgoing a
  }

type OtherPeers a c = [PeerState a c]

----------------------------------------------------------------------------------------------------------

data Peer a c = Peer
  { otherPeers :: STM.TMVar (OtherPeers a c),
    thisPeerId :: ClientId
  }

----------------------------------------------------------------------------------------------------------

doWith :: STM.TMVar a -> (a -> STM.STM ()) -> STM.STM ()
doWith var operation = do
  val <- STM.takeTMVar var
  operation val
  STM.putTMVar var val

----------------------------------------------------------------------------------------------------------

newMessageId :: IO UnixMsgTime
newMessageId = fromUnix <$> getUnixTime

----------------------------------------------------------------------------------------------------------

broadcast :: forall a c. Peer a c -> Message a -> IO ()
broadcast (Peer {otherPeers, thisPeerId}) msg =
  STM.atomically
    ( doWith
        otherPeers
        (mapM_ sendToPeer)
    )
  where
    sendToPeer (PeerState {outgoing}) =
      STMChan.writeTChan
        outgoing
        (fmap JustData msg)

listen :: forall a c. (Serialize a) => Peer a c -> IO ()
listen (Peer {otherPeers}) = do
  peers <- STM.atomically (STM.readTMVar otherPeers)

  void
    ( (forkIO . forever)
        ( mapConcurrently_
            pushToIncoming
            peers
        )
    )

  return undefined
  where
    pushToIncoming :: PeerState a c -> IO ()
    pushToIncoming (PeerState {connection, incoming}) = do
      (h, msg) <- parseMsg connection
      STM.atomically (STMChan.writeTChan incoming msg)
      return undefined