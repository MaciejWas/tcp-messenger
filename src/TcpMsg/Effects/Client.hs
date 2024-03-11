{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}

module TcpMsg.Effects.Client where

import Effectful
  ( Dispatch (Static),
    DispatchOf,
    Effect,
  )
import Effectful.Dispatch.Static
  ( SideEffects (WithSideEffects),
    StaticRep,
  )

----------------------------------------------------------------------------------------------------------

data ClientActions a b = ClientActions
  { ask :: a -> IO (),
    poll :: Int -> IO b
  }

-- | Effect definition
data Client a b :: Effect

type instance DispatchOf (Client a b) = Static WithSideEffects

newtype instance StaticRep (Client a b) = Client (ClientActions a b)