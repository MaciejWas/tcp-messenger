{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
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
import TcpMsg.Effects.Logger (logInfo, Logger)
import Effectful.Concurrent (Concurrent, forkIO)

----------------------------------------------------------------------------------------------------------

data ConnSupplier a :: Effect

type instance DispatchOf (ConnSupplier a) = Static WithSideEffects

newtype instance StaticRep (ConnSupplier a) = ConnSupplier (ConnSupplierActions a)

----------------------------------------------------------------------------------------------------------

data ConnSupplierActions c
  = ConnSupplierActions
      (IO (ConnectionActions c))

nextConnection :: forall c es. (Logger :> es, ConnSupplier c :> es) => Eff es (ConnectionActions c)
nextConnection = do
  (ConnSupplier (ConnSupplierActions nextConnection' )) <- (getStaticRep :: Eff es (StaticRep (ConnSupplier c)))
  nextConn <- unsafeEff_ nextConnection'
  logInfo "New connection established!"
  return nextConn

runConnSupplier :: forall c es a. (IOE :> es ) => ConnSupplierActions c -> Eff (ConnSupplier c ': es) a -> Eff es a
runConnSupplier connectionActions = evalStaticRep (ConnSupplier connectionActions)

----------------------------------------------------------------------------------------------------------

eachConnectionDo ::
  forall c es.
  ( IOE :> es,
    ConnSupplier c :> es,
    Concurrent :> es,
    Logger :> es
  ) =>
  Eff (Conn c ': es) () ->
  Eff es ()
eachConnectionDo action = do
  connHandle <- nextConnection
  _ <- forkIO (runConnection connHandle action)
  eachConnectionDo action
