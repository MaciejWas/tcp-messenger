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

module TcpMsg.Client.Tcp where

import Control.Concurrent.STM (newTVarIO)
import qualified Control.Monad.Catch as Err
import qualified Network.Socket as Net
  ( AddrInfo (addrAddress),
    HostName,
    PortNumber,
    Socket,
    close,
    connect,
    gracefulClose,
    openSocket,
  )
import qualified Network.Socket.ByteString as Net
import TcpMsg.Effects.Connection (Connection, ConnectionHandle (ConnectionHandle), ConnectionInfo (ConnectionInfo), mkConnection)
import TcpMsg.Network (getAddr)

connectToServer :: ClientOpts -> IO Net.Socket
connectToServer (ClientOpts {serverHost, serverPort}) = do
  addrInfo <- getAddr serverHost serverPort
  serverSocket <- Net.openSocket addrInfo
  Net.connect serverSocket (Net.addrAddress addrInfo)
  return serverSocket

data ClientOpts = ClientOpts
  { serverHost :: Net.HostName,
    serverPort :: Net.PortNumber
  }

createClientConnection ::
  ClientOpts ->
  IO (Connection Net.Socket)
createClientConnection opts =
  do
    socket <- connectToServer opts

    connRef <-
      newTVarIO
        ( ConnectionHandle
            (ConnectionInfo "some conn")
            socket
        )

    mkConnection
      connRef
      (Net.recv socket)
      (Net.sendAll socket)
