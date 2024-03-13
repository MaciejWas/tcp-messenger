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
{-# LANGUAGE GADTs #-}

module TcpMsg.Effects.Supplier where

import Effectful
  ( Dispatch (Static),
    DispatchOf,
    Eff,
    Effect,
    IOE,
    (:>),
  )
import Effectful (  Dispatch(Dynamic) )
import TcpMsg.Effects.Connection (ConnectionHandle, ConnectionActions, ConnectionHandleRef, Conn, runConnection)
import Effectful.Dispatch.Dynamic (HasCallStack, send)

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
data ConnSupplier conn :: Effect where
  GetNextConn :: ConnSupplier conn m (ConnectionActions conn)
  Finalize :: a -> ConnSupplier conn m ()

type instance DispatchOf (ConnSupplier a) = Dynamic

nextConnection :: forall conn es. (HasCallStack, ConnSupplier conn :> es) => Eff es (ConnectionActions conn)
nextConnection = send GetNextConn

----------------------------------------------------------------------------------------------------------

eachConnectionDo ::
  forall c es.
  ( IOE :> es,
    ConnSupplier c :> es
  ) =>
  Eff (Conn c ': es) () ->
  Eff es ()
eachConnectionDo action = do
  connHandle <- nextConnection
  runConnection connHandle action
  eachConnectionDo action
