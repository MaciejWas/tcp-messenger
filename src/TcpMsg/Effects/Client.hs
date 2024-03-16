{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE RankNTypes #-}

module TcpMsg.Effects.Client where


import qualified Data.HashTable.ST.Basic as H
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
import Effectful.Concurrent.Async (Async, async)
import Effectful.Concurrent.MVar (MVar, takeMVar)
import Effectful.Dispatch.Static
  ( SideEffects (WithSideEffects),
    StaticRep,
    getStaticRep,
    unsafeEff_,
  )
import TcpMsg.Data (UnixMsgTime, fromUnix, mkMsg)
import TcpMsg.Effects.Connection (Conn, write)
import Control.Monad.ST (runST)

----------------------------------------------------------------------------------------------------------

type MessageMap response = forall s. H.HashTable s UnixMsgTime (MVar response)

data ClientState a b = ClientState
  { clientName :: T.Text,
    msgs :: MessageMap b
  }

-- | Effect definition
data Client a b :: Effect

type instance DispatchOf (Client a b) = Static WithSideEffects

newtype instance StaticRep (Client a b) = Client (ClientState a b)

----------------------------------------------------------------------------------------------------------

takeOrDefault :: MessageMap b -> UnixMsgTime -> Eff es a
takeOrDefault messageMap unixTime = runST (do
  x <- H.lookup messageMap unixTime
  case x of
    (Just val) -> return val
    (Nothing) -> H.insert messageMap unixTime 
  return undefined
  )

blockingWaitForResponse :: UnixMsgTime -> Eff es a
blockingWaitForResponse unixTime = do
  (Client (ClientState {msgs})) <- (getStaticRep :: Eff es (StaticRep (Client a b)))
  x <- runST (H.lookup msgs unixTime)
  takeMVar x

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
  async undefined
  return undefined
