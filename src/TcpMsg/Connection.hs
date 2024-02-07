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

module TcpMsg.Connection where

import Control.Concurrent (MVar, putMVar, takeMVar)
import qualified Data.ByteString as BS
import Data.Serialize (Serialize, encode)
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
import Effectful.Concurrent.STM (TVar, atomically, modifyTVar)
import Effectful.Dispatch.Static
  ( SideEffects (WithSideEffects),
    StaticRep,
    evalStaticRep,
    getStaticRep,
    unsafeEff_,
  )
import GHC.Generics (Generic)
import TcpMsg.Data (ClientId, Time, mkMsg)

----------------------------------------------------------------------------------------------------------

type WriterMutex = MVar ()

data ServerOpts = ServerOpts

data ConnectionInfo
  = ConnectionInfo
      -- | Any identifier for the client
      ClientId
      -- | Time when connection was started
      Time

data ConnectionState = Awaiting Int -- Waiting for n bytes

-- | A connection handle which is used by the parent thread to refer to the thread which is handling the connection
data ConnectionHandle a
  = ConnectionHandle
      ConnectionState
      ConnectionInfo
      a -- Some protocol-specific data. E.g. client socket address

instance Functor ConnectionHandle where
  fmap :: (a -> b) -> ConnectionHandle a -> ConnectionHandle b
  fmap f (ConnectionHandle st inf a) = ConnectionHandle st inf (f a)

type ConnectionHandleRef a = TVar (ConnectionHandle a)

type ConnectionRead a = ConnectionHandleRef a -> Int -> IO BS.StrictByteString

type ConnectionWrite a = ConnectionHandleRef a -> BS.StrictByteString -> IO ()

type Finalize a = ConnectionHandleRef a -> IO ()

-- All necessary operations to handle a connection
data ConnectionActions a
  = ConnectionActions
      (ConnectionHandleRef a) -- Metadata about the connection
      (WriterMutex) -- So that only one thread can be writing to a connection on a given time
      (ConnectionRead a) -- Interface for receiving bytes
      (ConnectionWrite a) -- Interface for sending bytes
      (Finalize a) -- Action to be performed when connection is closed

----------------------------------------------------------------------------------------------------------

-- | Effect definition
data Conn a :: Effect

type instance DispatchOf (Conn a) = Static WithSideEffects

newtype instance StaticRep (Conn a) = Conn (ConnectionActions a)

-- | Connection effects (e.g. reading and writing to a socket) and concurrency
type ConcurrConn c m = (Concurrent :> m, Conn c :> m)

----------------------------------------------------------------------------------------------------------
-- | Effectful operations

readBytes :: forall es c. (Conn c :> es) => Int -> Eff es BS.StrictByteString
readBytes n = do
  (Conn (ConnectionActions st _ connRead _ _)) <- (getStaticRep :: Eff es (StaticRep (Conn c)))
  unsafeEff_ (connRead st n)

writeBytesUnsafe :: forall c es. (Conn c :> es) => BS.StrictByteString -> Eff es ()
writeBytesUnsafe bytes = do
  (Conn (ConnectionActions st _ _ connWrite _)) <- (getStaticRep :: Eff es (StaticRep (Conn c)))
  unsafeEff_ (connWrite st bytes)

writeBytes :: forall c es. (Conn c :> es) => BS.StrictByteString -> Eff es ()
writeBytes bytes = withWriterLock @c (writeBytesUnsafe @c bytes)

write :: forall c a es. (Conn c :> es, Serialize a) => Int -> a -> Eff es ()
write messageId obj = writeBytes @c (mkMsg messageId obj)

markState :: forall es c. (ConcurrConn c es) => ConnectionState -> Eff es ()
markState state = do
  (Conn (ConnectionActions st _ _ _ _)) <- (getStaticRep :: Eff es (StaticRep (Conn c)))
  atomically (modifyTVar st (setConnState state))

runConnection :: (IOE :> es) => ConnectionActions c -> Eff (Conn c ': es) a -> Eff es a
runConnection connectionActions = evalStaticRep (Conn connectionActions)

withWriterLock :: forall c es a. (Conn c :> es) => Eff es a -> Eff es a
withWriterLock operation = do
  (Conn (ConnectionActions _ writerMutex _ _ _)) <- (getStaticRep :: Eff es (StaticRep (Conn c)))
  lock <- unsafeEff_ (takeMVar writerMutex)
  ret <- operation
  unsafeEff_ (putMVar writerMutex lock)
  return ret

----------------------------------------------------------------------------------------------------------
-- Various helpers

setConnState :: ConnectionState -> ConnectionHandle a -> ConnectionHandle a
setConnState newSt (ConnectionHandle _ info a) = ConnectionHandle newSt info a

showConn :: ConnectionHandle a -> T.Text
showConn (ConnectionHandle {}) = "TODO: conn representation"
