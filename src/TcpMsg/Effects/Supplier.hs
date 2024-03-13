{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module TcpMsg.Effects.Supplier where

import Effectful
  ( Dispatch (Dynamic, Static),
    DispatchOf,
    Eff,
    Effect,
    IOE,
    (:>),
  )
import Effectful.Dispatch.Dynamic (HasCallStack, send)
import TcpMsg.Effects.Connection (Conn, ConnectionActions, ConnectionHandle, ConnectionHandleRef, runConnection)

----------------------------------------------------------------------------------------------------------

-- | Effect definition
data ConnSupplier conn :: Effect where
  GetNextConn :: ConnSupplier conn m (ConnectionActions conn)

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
