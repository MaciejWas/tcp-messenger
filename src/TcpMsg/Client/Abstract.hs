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

module TcpMsg.Client.Abstract where
import Control.Concurrent (ThreadId, forkIO)

import qualified Control.Concurrent.STM as STM
import Control.Monad (forever)
import Data.Serialize (Serialize)

import qualified StmContainers.Map as M
import TcpMsg.Data (Header (Header), Message)
import TcpMsg.Effects.Connection (Connection)
import TcpMsg.Parsing (parseMsg)
import TcpMsg.Effects.Client (Client (Client), MessageMap)
import Control.Concurrent.STM (atomically)

notifyMessage ::
  forall b .
  STM.TVar (MessageMap b) ->
  (Header, Message b) ->
  IO ()
notifyMessage msgs (Header msgTime _ _, newMsg) =
  atomically
    ( do
        msgs_ <- STM.readTVar msgs
        currVar <- M.lookup msgTime msgs_
        case currVar of
          Nothing ->
            ( do
                responseMVar <- STM.newTMVar newMsg
                M.insert responseMVar msgTime msgs_ 
            )
          Just mvar -> STM.putTMVar mvar newMsg
    )

startWorker ::
  forall b c.
  ( Serialize b) =>
  Connection c ->
  STM.TVar (MessageMap b) ->
  IO ThreadId
startWorker conn msgs =
  (forkIO . forever)
    (readNextMessage >>= notifyMessageReceived)
  where
    readNextMessage = parseMsg conn
    notifyMessageReceived = notifyMessage msgs

createClient ::
  forall a b c.
  ( Serialize b
  ) =>
  Connection c ->
  IO (Client a b c)
createClient conn = do
  msgs <- atomically (M.new >>= STM.newTVar)
  workerThreadId <- startWorker conn msgs
  return (Client mempty msgs workerThreadId conn)