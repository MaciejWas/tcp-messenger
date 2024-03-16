{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module TcpMsg.Effects.Client where

import qualified Data.HashTable.IO as H
import Data.Serialize (Serialize)
import qualified Data.Text as T
import Data.UnixTime (UnixTime (UnixTime), getUnixTime)
import Effectful
  ( Dispatch (Static),
    DispatchOf,
    Eff,
    Effect,
    (:>),
  )
import Effectful.Concurrent (Concurrent)
import Effectful.Concurrent.Async (Async)
import Effectful.Concurrent.MVar (MVar)
import Effectful.Dispatch.Static
  ( SideEffects (WithSideEffects),
    StaticRep,
    getStaticRep,
    unsafeEff_,
  )
import TcpMsg.Data (UnixMsgTime, fromUnix, mkMsg)
import TcpMsg.Effects.Connection (Conn, write)

----------------------------------------------------------------------------------------------------------

type MessageMap response = H.BasicHashTable UnixMsgTime (MVar response)

data ClientState a b = ClientActions
  { clientName :: T.Text,
    msgs :: MessageMap b
  }

-- | Effect definition
data Client a b :: Effect

type instance DispatchOf (Client a b) = Static WithSideEffects

newtype instance StaticRep (Client a b) = Client (ClientState a b)

----------------------------------------------------------------------------------------------------------

blockingWaitForResponse :: UnixMsgTime -> Eff es a
blockingWaitForResponse = do
  (Client (ClientState {msgs})) <- (getStaticRep :: Eff es (StaticRep (Client a b)))

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
  (Client _) <- (getStaticRep :: Eff es (StaticRep (Client a b)))
  unixTime <- unsafeEff_ getUnixTime
  let msgTime = fromUnix unixTime
  write @c msgTime request
  async ()
  return undefined
