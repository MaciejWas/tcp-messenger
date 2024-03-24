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
-- import qualified Data.HashTable.IO as H (BasicHashTable, insert, lookup, new)

import qualified Control.Concurrent.STM as STM
import Control.Monad (forever)
import Data.Serialize (Serialize)
import qualified Data.Text as T
import Data.UnixTime (getUnixTime)
import Effectful
  ( Dispatch (Static),
    DispatchOf,
    Eff,
    Effect,
    IOE,
    (:>),
  )
import Effectful.Concurrent (Concurrent, forkIO)
import Effectful.Concurrent.Async (Async, async)
import Effectful.Concurrent.STM (atomically)
import Effectful.Dispatch.Static
  ( SideEffects (WithSideEffects),
    StaticRep,
    evalStaticRep,
    getStaticRep,
    unsafeEff_,
  )
import qualified StmContainers.Map as M
import TcpMsg.Data (Header (Header), UnixMsgTime, fromUnix)
import TcpMsg.Effects.Connection (Conn, sendMessage)
import TcpMsg.Parsing (parseMsg)
import qualified Data.ByteString.Lazy as LBS

----------------------------------------------------------------------------------------------------------

type MessageMap response = M.Map UnixMsgTime (STM.TMVar response)

data ClientState a b = ClientState
  { clientName :: T.Text,
    msgs :: STM.TVar (MessageMap b),
    worker :: ThreadId
  }

----------------------------------------------------------------------------------------------------------

data Client a b :: Effect

type instance DispatchOf (Client a b) = Static WithSideEffects

newtype instance StaticRep (Client a b) = Client (ClientState a b)

----------------------------------------------------------------------------------------------------------

newMessageId :: forall a b es. (Client a b :> es) => Eff es UnixMsgTime
newMessageId = fromUnix <$> unsafeEff_ getUnixTime

-- Get a map of pending messages
pendingMessages :: forall a b es. (Client a b :> es) => Eff es (STM.TVar (MessageMap b))
pendingMessages = do
  (Client (ClientState {msgs})) <- (getStaticRep :: Eff es (StaticRep (Client a b)))
  return msgs

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
  Maybe LBS.LazyByteString ->
  Eff es (Async b)
ask payload trunk = do
  msgTime <- sendRequest
  async (blockingWaitForResponse @a @b msgTime)
  where
    sendRequest :: Eff es UnixMsgTime
    sendRequest = do
      msgId <- newMessageId @a @b
      sendMessage @c msgId payload trunk
      return msgId
