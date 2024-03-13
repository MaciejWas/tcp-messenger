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

module TcpMsg.Effects.Connection where

import Control.Concurrent (MVar)
import qualified Data.ByteString as BS
import Data.Serialize (Serialize)
import qualified Data.Text as T
import Effectful
  ( Dispatch (Static),
    DispatchOf,
    Eff,
    Effect,
    IOE,
    (:>),
  )
import Effectful.Concurrent (Concurrent)
import Effectful.Concurrent.MVar (newMVar, withMVar)
import Effectful.Concurrent.STM (TVar)
import Effectful.Dispatch.Static
  ( SideEffects (WithSideEffects),
    StaticRep,
    evalStaticRep,
    getStaticRep,
    unsafeEff_,
  )
import TcpMsg.Data (ClientId, mkMsg)

----------------------------------------------------------------------------------------------------------

type WriterMutex = MVar ()

data ServerOpts = ServerOpts

data ConnectionInfo
  = ConnectionInfo
      -- | Any identifier for the client
      ClientId

-- | A connection handle which is used by the parent thread to refer to the thread which is handling the connection
data ConnectionHandle a
  = ConnectionHandle
      ConnectionInfo
      a -- Some protocol-specific data. E.g. client socket address

instance Functor ConnectionHandle where
  fmap :: (a -> b) -> ConnectionHandle a -> ConnectionHandle b
  fmap f (ConnectionHandle inf a) = ConnectionHandle inf (f a)

type ConnectionHandleRef a = TVar (ConnectionHandle a)

type ConnectionRead a = Int -> IO BS.StrictByteString

type ConnectionWrite a = BS.StrictByteString -> IO ()

-- All necessary operations to handle a connection
data ConnectionActions a
  = ConnectionActions
      (ConnectionHandleRef a) -- Metadata about the connection
      (WriterMutex) -- So that only one thread can be writing to a connection on a given time
      (ConnectionRead a) -- Interface for receiving bytes
      (ConnectionWrite a) -- Interface for sending bytes

mkConnectionActions ::
  forall es a.
  (Concurrent :> es) =>
  ConnectionHandleRef a ->
  ConnectionRead a ->
  ConnectionWrite a ->
  Eff es (ConnectionActions a)
mkConnectionActions handle connread connwrite = do
  writerLock <- newMVar ()
  return (ConnectionActions handle writerLock connread connwrite)

----------------------------------------------------------------------------------------------------------

-- | Effect definition
data Conn a :: Effect

type instance DispatchOf (Conn a) = Static WithSideEffects

newtype instance StaticRep (Conn a) = Conn (ConnectionActions a)

----------------------------------------------------------------------------------------------------------

-- | Effectful operations
readBytes :: forall es c. (Conn c :> es) => Int -> Eff es BS.StrictByteString
readBytes n = do
  (Conn (ConnectionActions _ _ connRead _)) <- (getStaticRep :: Eff es (StaticRep (Conn c)))
  unsafeEff_ (connRead n)

writeBytes ::
  forall c es.
  ( Concurrent :> es,
    Conn c :> es
  ) =>
  BS.StrictByteString ->
  Eff es ()
writeBytes bytes = do
  (Conn (ConnectionActions _ writerMutex _ connWrite)) <- (getStaticRep :: Eff es (StaticRep (Conn c)))
  let doWriteBytes (_lock :: ()) = unsafeEff_ (connWrite bytes)
  withMVar
    writerMutex
    doWriteBytes

write ::
  forall c a es.
  ( Concurrent :> es,
    Conn c :> es,
    Serialize a
  ) =>
  Int ->
  a ->
  Eff es ()
write messageId obj = writeBytes @c (mkMsg messageId obj)

runConnection :: forall c a es. (IOE :> es) => ConnectionActions c -> Eff (Conn c ': es) a -> Eff es a
runConnection connectionActions = evalStaticRep (Conn connectionActions)

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

----------------------------------------------------------------------------------------------------------

data ClientActions a b = ClientActions
  { ask :: a -> IO (),
    poll :: Int -> IO b
  }

-- | Effect definition
data Client a b :: Effect

type instance DispatchOf (Client a b) = Static WithSideEffects

newtype instance StaticRep (Client a b) = Client (ClientActions a b)

----------------------------------------------------------------------------------------------------------
-- Various helpers

showConn :: ConnectionHandle a -> T.Text
showConn (ConnectionHandle {}) = "TODO: conn representation"
