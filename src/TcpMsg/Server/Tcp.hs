{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module TcpMsg.Server.Tcp where

import Control.Concurrent (ThreadId, killThread)
import Control.Concurrent.STM.TVar (newTVarIO)
import Control.Exception (finally)
import qualified Control.Exception as E
import qualified Network.Socket as Net
  ( PortNumber,
    Socket,
    accept,
    close,
    gracefulClose,
    openSocket,
  )
import qualified Network.Socket.ByteString as Net
import TcpMsg.Effects.Connection (Connection, ConnectionHandle (ConnectionHandle), ConnectionInfo (ConnectionInfo), mkConnection)
import TcpMsg.Effects.Supplier (ConnectionSupplier(..))
import TcpMsg.Network (getAddr, startListening)

----------------------------------------------------------------------------------------------------------

data ServerTcpSettings = ServerTcpSettings
  { port :: Net.PortNumber
  }

createServerSocket :: ServerTcpSettings -> IO Net.Socket
createServerSocket (ServerTcpSettings {port}) = do
  socketAddress <- getAddr "localhost" port
  socket <- Net.openSocket socketAddress
  startListening socket socketAddress
  return socket

----------------------------------------------------------------------------------------------------------

nextConnection :: Net.Socket -> IO (Connection Net.Socket)
nextConnection sock = do
  (peerSocket, peerAddr) <- Net.accept sock
  connRef <- newTVarIO (ConnectionHandle (ConnectionInfo "some conn") peerSocket)
  mkConnection
    connRef
    (Net.recv peerSocket)
    (Net.sendAll peerSocket)

----------------------------------------------------------------------------------------------------------

defaultServerTcpSettings :: ServerTcpSettings
defaultServerTcpSettings = ServerTcpSettings {port = 4455}

createTcpConnSupplier ::
  ServerTcpSettings ->
  IO (ConnectionSupplier Net.Socket)
createTcpConnSupplier
  serverSettings
  =
    do
      socket <- createServerSocket serverSettings
      return (ConnectionSupplier {supplyConn = nextConnection socket})

----------------------------------------------------------------------------------------------------------
