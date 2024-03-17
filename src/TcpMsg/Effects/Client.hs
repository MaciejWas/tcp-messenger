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

import qualified Control.Concurrent as STM
import qualified Control.Concurrent.STM as STM
import Control.Monad (forever)
import Data.Maybe (isNothing)
import Data.Serialize (Serialize)
import qualified Data.Text as T
import Data.UnixTime (getUnixTime)
import Effectful
  ( Dispatch (Static),
    DispatchOf,
    Eff,
    Effect,
    IOE,
    MonadIO (liftIO),
    (:>),
  )
import Effectful.Concurrent (Concurrent, forkIO)
import Effectful.Concurrent.Async (Async, async)
import Effectful.Concurrent.MVar (MVar, newEmptyMVar, newMVar, putMVar, takeMVar)
import Effectful.Concurrent.STM (atomically)
import Effectful.Dispatch.Static
  ( SideEffects (WithSideEffects),
    StaticRep,
    evalStaticRep,
    getStaticRep,
    putStaticRep,
    unsafeEff_,
  )
import qualified StmContainers.Map as M
import TcpMsg.Data (Header (Header), UnixMsgTime, fromUnix, mkMsg)
import TcpMsg.Effects.Connection (Conn, write)
import TcpMsg.Parsing (parseMsg)

----------------------------------------------------------------------------------------------------------

type UnboxedMessageMap response = M.Map UnixMsgTime (STM.TMVar response)

type MessageMap response = STM.TVar (UnboxedMessageMap response)

data ClientState a b = ClientState
  { clientName :: T.Text,
    msgs :: MessageMap b,
    worker :: ThreadId
  }

-- | Effect definition
data Client a b :: Effect

type instance DispatchOf (Client a b) = Static WithSideEffects

newtype instance StaticRep (Client a b) = Client (ClientState a b)

----------------------------------------------------------------------------------------------------------

-- Create a new awaitable MVar which will contain the response
initMessage ::
  forall b.
  UnboxedMessageMap b ->
  UnixMsgTime ->
  STM.STM (STM.TMVar b)
initMessage msgs msgTime =
  do
    v <- STM.newEmptyTMVar
    M.insert v msgTime msgs
    return v
    

notifyMessage ::
  forall b es.
  (Concurrent :> es) =>
  MessageMap b ->
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
  MessageMap b ->
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

----------------------------------------------------------------------------------------------------------

makeRequest ::
  forall a c es.
  ( Serialize a,
    Concurrent :> es,
    Conn c :> es
  ) =>
  a ->
  Eff es UnixMsgTime
makeRequest x = do
  unixTime <- unsafeEff_ getUnixTime
  let msgTime = fromUnix unixTime
  write @c msgTime x
  return msgTime

----------------------------------------------------------------------------------------------------------

blockingWaitForResponse :: forall a b es. (Concurrent :> es, Client a b :> es) => UnixMsgTime -> Eff es b
blockingWaitForResponse unixTime = do
  (Client (ClientState {msgs})) <- (getStaticRep :: Eff es (StaticRep (Client a b)))
  atomically
    ( do
        msgs_ <- STM.readTVar msgs
        response <- M.lookup unixTime msgs_
        case response of
          Just r -> STM.takeTMVar r
          Nothing -> initMessage msgs_ unixTime >>= STM.takeTMVar
    )

-- msg <- lookupMessage @a @b unixTime
-- unsafeEff_ (print ("waiting for " ++ show unixTime))
-- r <- case msg of
--   (Just mvar) -> takeMVar mvar
--   Nothing ->
--     ( do
--         unsafeEff_ (print ("init new mvar for " ++ show unixTime))
--         initMessage @a @b unixTime >>= takeMVar
--     )

-- unsafeEff_ (print ("Response received for" ++ show unixTime))
-- return r

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
  msgTime <- makeRequest @a @c request
  unsafeEff_ (print ("made a request at " ++ show msgTime))
  async (blockingWaitForResponse @a @b msgTime)
