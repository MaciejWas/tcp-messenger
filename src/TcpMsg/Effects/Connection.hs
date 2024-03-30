{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module TcpMsg.Effects.Connection where

import Control.Concurrent (MVar, newMVar, withMVar)
import Control.Concurrent.STM.TVar (TVar)
import qualified Data.ByteString as BS
import Data.Serialize (Serialize)

import TcpMsg.Data (ClientId, Message, UnixMsgTime, encodeMsg)

----------------------------------------------------------------------------------------------------------

type WriterMutex = MVar ()

type MessageID = Int

data ConnectionInfo
  = ConnectionInfo
      -- | Any identifier for the client
      ClientId

-- | A connection handle which is used by the parent thread to refer to the thread which is handling the connection
data ConnectionHandle a
  = ConnectionHandle
      ConnectionInfo
      a -- Some protocol-specific data. E.g. client socket address

type ConnectionHandleRef a = TVar (ConnectionHandle a)

type ConnectionRead a = Int -> IO BS.StrictByteString

type ConnectionWrite a = BS.StrictByteString -> IO ()

-- All necessary operations to handle a connection
data Connection a
  = Connection
  { chandle :: (ConnectionHandleRef a), -- Metadata about the connection
    cwriterMutex :: (WriterMutex), -- So that only one thread can be writing to a connection on a given time
    cread :: (ConnectionRead a), -- Interface for receiving bytes
    cwrite :: (ConnectionWrite a) -- Interface for sending bytes
  }

mkConnection ::
  ConnectionHandleRef a ->
  ConnectionRead a ->
  ConnectionWrite a ->
  IO (Connection a)
mkConnection handle connread connwrite = do
  writerLock <- newMVar ()
  return (Connection handle writerLock connread connwrite)

readBytes ::
  forall c.
  Connection c ->
  Int ->
  IO BS.StrictByteString
readBytes = cread

writeBytes ::
  forall c.
  Connection c ->
  BS.StrictByteString ->
  IO ()
writeBytes (Connection {cwrite, cwriterMutex}) bytes =
  withMVar
    cwriterMutex
    (const (cwrite bytes))

sendMessage ::
  forall c a.
  (Serialize a) =>
  Connection c ->
  UnixMsgTime ->
  Message a ->
  IO ()
sendMessage c messageId message = writeBytes c (encodeMsg messageId message)
