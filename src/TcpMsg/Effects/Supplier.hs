{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeApplications #-}

module TcpMsg.Effects.Supplier where

import Effectful
  ( Dispatch (Static),
    DispatchOf,
    Eff,
    Effect,
    IOE,
    (:>),
  )

import Effectful.Dispatch.Static
  ( SideEffects (WithSideEffects),
    StaticRep, getStaticRep, unsafeEff_, evalStaticRep,
  )
import TcpMsg.Effects.Connection (Conn, ConnectionActions, runConnection)
import Effectful.Concurrent (Concurrent, forkFinally)

----------------------------------------------------------------------------------------------------------

data ConnSupplier a :: Effect

type instance DispatchOf (ConnSupplier a) = Static WithSideEffects

newtype instance StaticRep (ConnSupplier a) = ConnSupplier (ConnSupplierActions a)

----------------------------------------------------------------------------------------------------------

data ConnSupplierActions c
  = ConnSupplierActions
      (IO (ConnectionActions c))

nextConnection :: forall c es. ( ConnSupplier c :> es) => Eff es (ConnectionActions c)
nextConnection = do
  (ConnSupplier (ConnSupplierActions nextConnection' )) <- (getStaticRep :: Eff es (StaticRep (ConnSupplier c)))
  unsafeEff_ nextConnection'

runConnSupplier :: forall c es a. (IOE :> es ) => ConnSupplierActions c -> Eff (ConnSupplier c ': es) a -> Eff es a
runConnSupplier connectionActions = evalStaticRep (ConnSupplier connectionActions)

----------------------------------------------------------------------------------------------------------

eachConnectionDo ::
  forall c es.
  ( IOE :> es,
    ConnSupplier c :> es,
    Concurrent :> es
  ) =>
  Eff (Conn c ': es) () ->
  Eff es ()
eachConnectionDo action = do
  connHandle <- nextConnection
  _ <- forkFinally (runConnection connHandle action) (\e -> return ())
  eachConnectionDo action
