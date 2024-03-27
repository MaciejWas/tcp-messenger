{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module TcpMsg.Effects.Client where

import Control.Concurrent (ThreadId)
import Control.Concurrent.Async (Async, async)

import qualified Control.Concurrent.STM as STM
import qualified Data.ByteString.Lazy as LBS
import Data.Serialize (Serialize)
import qualified Data.Text as T

import qualified Network.Socket as Net
import Data.UnixTime (getUnixTime)

import qualified StmContainers.Map as M
import TcpMsg.Data (Header (Header), Message, UnixMsgTime, fromUnix)
import TcpMsg.Effects.Connection (Connection, sendMessage)
import TcpMsg.Parsing (parseMsg)
import Control.Concurrent.STM (atomically)

----------------------------------------------------------------------------------------------------------

type MessageMap response =
  M.Map
    UnixMsgTime
    (STM.TMVar (Message response))

data Client a b c = Client
  { clientName :: T.Text,
    msgs :: STM.TVar (MessageMap b),
    worker :: ThreadId,
    connection :: Connection c
  }

type TcpClient a b = Client a b Net.Socket

----------------------------------------------------------------------------------------------------------

newMessageId :: IO UnixMsgTime
newMessageId = fromUnix <$> getUnixTime

-- Get a map of pending messages
pendingMessages :: Client a b c -> STM.TVar (MessageMap b)
pendingMessages = msgs

blockingWaitForResponse :: Client a b c -> UnixMsgTime -> IO (Message b)
blockingWaitForResponse client unixTime = do
  atomically
    ( do
        msgs_ <- STM.readTVar (msgs client)
        response <- M.lookup unixTime msgs_
        case response of
          Just r -> M.delete unixTime msgs_ >> STM.takeTMVar r
          Nothing -> initMessage msgs_ unixTime >>= STM.takeTMVar
    )
  where
    -- Create a new MVar which will contain the response
    initMessage ::
      MessageMap b ->
      UnixMsgTime ->
      STM.STM (STM.TMVar (Message b))
    initMessage msgs msgTime =
      do
        v <- STM.newEmptyTMVar
        M.insert v msgTime msgs
        return v

ask ::
  forall a b c.
    Serialize a
  =>
  Client a b c ->
  Message a ->
  IO (Async (Message b))
ask client@Client{connection} msg = sendRequest >>= (async . blockingWaitForResponse client)
  where
    sendRequest :: IO UnixMsgTime
    sendRequest = do
      msgId <- newMessageId
      sendMessage connection msgId msg
      return msgId
