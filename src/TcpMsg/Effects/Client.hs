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
import Control.Monad.ST (runST)
import qualified Data.HashTable.IO as H (BasicHashTable, insert, lookup, new)
import Data.Serialize (Serialize)
import qualified Data.Text as T
import Data.UnixTime (UnixTime (UnixTime), getUnixTime)
import Effectful
  ( Dispatch (Static),
    DispatchOf,
    Eff,
    Effect,
    (:>), IOE,
  )
import Effectful.Concurrent (Concurrent, forkIO)
import Effectful.Concurrent.Async (Async, async)
import Effectful.Concurrent.MVar (MVar, newEmptyMVar, newMVar, putMVar, takeMVar)
import Effectful.Dispatch.Static
  ( SideEffects (WithSideEffects),
    StaticRep,
    getStaticRep,
    putStaticRep,
    unsafeEff_, evalStaticRep,
  )
import TcpMsg.Data (Header (Header), UnixMsgTime, fromUnix, mkMsg)
import TcpMsg.Effects.Connection (Conn, write)
import TcpMsg.Parsing (parseMsg)

----------------------------------------------------------------------------------------------------------

type MessageMap response = H.BasicHashTable UnixMsgTime (MVar response)

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

lookupMessage :: forall a b es. (Client a b :> es) => UnixMsgTime -> Eff es (Maybe (MVar b))
lookupMessage msgTime = do
  (Client (ClientState {msgs})) <- (getStaticRep :: Eff es (StaticRep (Client a b)))
  unsafeEff_ (H.lookup msgs msgTime)

initMessage ::
  forall a b es.
  ( Concurrent :> es,
    Client a b :> es
  ) =>
  UnixMsgTime ->
  Eff es (MVar b)
initMessage msgTime = do
  (Client (ClientState {msgs})) <- (getStaticRep :: Eff es (StaticRep (Client a b)))
  m <- newEmptyMVar
  unsafeEff_ (H.insert msgs msgTime m)
  return m

notifyMessage ::
  forall a b es.
  ( Concurrent :> es,
    Client a b :> es
  ) =>
  Header ->
  b ->
  Eff es ()
notifyMessage (Header msgTime _) response = do
  (Client (ClientState {msgs})) <- (getStaticRep :: Eff es (StaticRep (Client a b)))
  mvar <- unsafeEff_ (H.lookup msgs msgTime)
  case mvar of
    Nothing -> error "Unexpected message from server"
    Just mvar -> putMVar mvar response

startWorker ::
  forall b c es.
  ( Serialize b,
    Concurrent :> es,
    Conn c :> es
  ) =>
  MessageMap b ->
  Eff es ()
startWorker msgs =
  do

        forkIO
          ( do
              (header, msg) <- parseMsg @c @b
              notifyMessage @a @b header msg
          )


runClient ::
  forall a b c es.
  ( Serialize b,
    Serialize a,
    Concurrent :> es,
    Conn c :> es,
    IOE :> es
  ) =>
  Eff (Client a b : es) ()
  -> Eff es ()
runClient op = do
  msgs <- unsafeEff_ (H.new)
  evalStaticRep (Client @a @b (ClientState mempty msgs Nothing)) op


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
  msg <- lookupMessage @a @b unixTime
  case msg of
    (Just mvar) -> takeMVar mvar
    Nothing -> initMessage @a @b unixTime >>= takeMVar

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
  async (blockingWaitForResponse @a @b msgTime)
