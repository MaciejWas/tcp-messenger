{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module TcpMsg.Effects.Client where

import qualified Data.Text as T
import Effectful
  ( Dispatch (Static),
    DispatchOf,
    Eff,
    Effect,
    (:>),
  )
import Effectful.Concurrent (Concurrent)
import Effectful.Concurrent.Async (Async)
import Effectful.Dispatch.Static
  ( SideEffects (WithSideEffects),
    StaticRep,
  )
import TcpMsg.Effects.Connection (Conn)

----------------------------------------------------------------------------------------------------------

data ClientActions a b = ClientActions
  { clientName :: T.Text }

-- | Effect definition
data Client a b :: Effect

type instance DispatchOf (Client a b) = Static WithSideEffects

newtype instance StaticRep (Client a b) = Client (ClientActions a b)

----------------------------------------------------------------------------------------------------------

ask ::
  forall a b c es.
  ( Client a b :> es,
    Concurrent :> es,
    Conn c :> es
  ) =>
  a ->
  Eff es (Async b)
ask msg = undefined
  
