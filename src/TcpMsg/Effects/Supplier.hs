{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

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
    StaticRep,
    getStaticRep,
    unsafeEff_,
  )
import TcpMsg.Effects.Connection (ConnectionHandle, ConnectionActions, ConnectionHandleRef, Conn, runConnection)

----------------------------------------------------------------------------------------------------------

type NextConnection c = IO (ConnectionHandle c)

type InitConn c = ConnectionHandle c -> IO (ConnectionActions c)

type Finalize c = ConnectionHandleRef c -> IO ()

data ConnSupplierActions c
  = ConnSupplierActions
      (NextConnection c)
      (InitConn c)

----------------------------------------------------------------------------------------------------------

-- | Effect definition
data ConnSupplier a :: Effect

type instance DispatchOf (ConnSupplier a) = Static WithSideEffects

newtype instance StaticRep (ConnSupplier a) = ConnSupplier (ConnSupplierActions a)

----------------------------------------------------------------------------------------------------------

eachConnectionDo ::
  forall c es.
  ( IOE :> es,
    ConnSupplier c :> es
  ) =>
  Eff (Conn c ': es) () ->
  Eff es ()
eachConnectionDo action = do
  (ConnSupplier (ConnSupplierActions nextConnection initConnection)) <- (getStaticRep :: Eff es (StaticRep (ConnSupplier c)))
  connHandle <- unsafeEff_ nextConnection
  connActions <- unsafeEff_ (initConnection connHandle)
  runConnection connActions action
  eachConnectionDo action
