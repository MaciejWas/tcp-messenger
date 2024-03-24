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
import Effectful.Concurrent.STM (atomically)
import Effectful.Dispatch.Static
  ( evalStaticRep,
  )
import qualified StmContainers.Map as M
import TcpMsg.Data (Header (Header))
import TcpMsg.Effects.Connection (Conn)
import TcpMsg.Parsing (parseMsg)
import TcpMsg.Effects.Client (Client, MessageMap, StaticRep (Client), ClientState (ClientState))

notifyMessage ::
  forall b es.
  (Concurrent :> es) =>
  STM.TVar (MessageMap b) ->
  Header ->
  b ->
  Eff es ()
notifyMessage msgs (Header msgTime _ _) response =
  atomically
    ( do
        msgs_ <- STM.readTVar msgs
        currVar <- M.lookup msgTime msgs_
        case currVar of
          Nothing ->
            ( do
                responseMVar <- STM.newTMVar response
                M.insert responseMVar msgTime msgs_ 
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