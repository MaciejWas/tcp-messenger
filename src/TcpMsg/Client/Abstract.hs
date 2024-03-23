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
import Control.Concurrent (ThreadId)

import qualified Control.Concurrent.STM as STM
import Control.Monad (forever)
import Data.Serialize (Serialize)
import Effectful
  ( Eff,
      IOE,
      (:>),
  )
import Effectful.Concurrent (Concurrent, forkIO)
import Effectful.Concurrent.Async (Async, async)
import Effectful.Concurrent.STM (atomically)
import Effectful.Dispatch.Static
  ( evalStaticRep,
  )
import qualified StmContainers.Map as M
import TcpMsg.Data (Header (Header), UnixMsgTime)
import TcpMsg.Effects.Connection (Conn, sendMessage)
import TcpMsg.Parsing (parseMsg)
import TcpMsg.Effects.Client (Client, MessageMap, pendingMessages, StaticRep (Client), ClientState (ClientState), newMessageId)



notifyMessage ::
  forall b es.
  (Concurrent :> es) =>
  STM.TVar (MessageMap b) ->
  Header ->
  b ->
  Eff es ()
notifyMessage msgs (Header msgTime _) response =
  atomically
    ( do
        msgs_ <- STM.readTVar msgs
        currVar <- M.lookup msgTime msgs_
        case currVar of
          Nothing ->
            ( do
                responseMVar <- STM.newTMVar response
                M.insert responseMVar msgTime msgs_ -- TODO: probably message table should be an effect on its own
            )
          Just mvar -> STM.putTMVar mvar response
    )

startWorker ::
  forall b c es.
  ( Serialize b,
    Concurrent :> es,
    Conn c :> es
  ) =>
  STM.TVar (MessageMap b) ->
  Eff es ThreadId
startWorker msgs =
  (forkIO . forever)
    (readNextMessage >>= notifyMessageReceived)
  where
    readNextMessage = parseMsg @c @b
    notifyMessageReceived = uncurry (notifyMessage msgs)


----------------------------------------------------------------------------------------------------------

blockingWaitForResponse :: forall a b es. (Concurrent :> es, Client a b :> es) => UnixMsgTime -> Eff es b
blockingWaitForResponse unixTime = do
  msgs <- pendingMessages @a
  atomically
    ( do
        msgs_ <- STM.readTVar msgs
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
      STM.STM (STM.TMVar b)
    initMessage msgs msgTime =
      do
        v <- STM.newEmptyTMVar
        M.insert v msgTime msgs
        return v

ask ::
  forall a b c es.
  ( Client a b :> es,
    Concurrent :> es,
    Conn c :> es,
    Serialize a
  ) =>
  a ->
  Eff es (Async b)
ask request = do
  msgTime <- makeRequest @a @b request
  async (blockingWaitForResponse @a @b msgTime)
  where
    makeRequest :: forall a b es. (Serialize a, Concurrent :> es, Client a b :> es, Conn c :> es) => a -> Eff es UnixMsgTime
    makeRequest x = do
      msgId <- newMessageId @a @b
      sendMessage @c msgId x
      return msgId


runClient ::
  forall a b c es.
  ( Serialize b,
    Concurrent :> es,
    Conn c :> es,
    IOE :> es
  ) =>
  Eff (Client a b : es) () ->
  Eff es ()
runClient op = do
  msgs <- atomically (M.new >>= STM.newTVar)
  workerThreadId <- startWorker @b @c msgs
  evalStaticRep
    (Client @a @b (ClientState mempty msgs workerThreadId))
    op