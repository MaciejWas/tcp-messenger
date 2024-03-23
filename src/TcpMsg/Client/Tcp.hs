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

import Effectful
  ( Eff,
    IOE,
    MonadIO (liftIO),
    (:>),
  )
import Effectful.Concurrent (Concurrent)
import Effectful.Concurrent.STM (newTVarIO)
import qualified Network.Socket as Net
  ( HostName,
    PortNumber,
    Socket,
    gracefulClose, openSocket, AddrInfo (addrAddress), connect,
  )
import qualified Network.Socket.ByteString as Net
import TcpMsg.Effects.Connection (Conn, ConnectionHandle (ConnectionHandle), ConnectionInfo (ConnectionInfo), mkConnectionActions, runConnection)
import TcpMsg.Network (getAddr)

createSocket :: ClientOpts -> IO Net.Socket
createSocket (ClientOpts {serverHost, serverPort}) = do
  addrInfo <- getAddr serverHost serverPort
  serverSocket <- Net.openSocket addrInfo
  Net.connect serverSocket (Net.addrAddress addrInfo)
  return serverSocket

data ClientOpts = ClientOpts
  { serverHost :: Net.HostName,
    serverPort :: Net.PortNumber
  }

-- | Runs a `Connection` effect. In other words, provides an environment where
-- | data can be sent / read
runTcpConnection ::
  forall a es.
  (IOE :> es, Concurrent :> es) =>
  ClientOpts ->
  Eff (Conn Net.Socket ': es) a ->
  Eff es a
runTcpConnection opts operation =
  do
    serverSocket <- liftIO (createSocket opts)

    connRef <-
      newTVarIO
        ( ConnectionHandle
            (ConnectionInfo "some conn")
            serverSocket
        )

    connActions <-
      mkConnectionActions
        connRef
        (Net.recv serverSocket)
        (Net.sendAll serverSocket)
        (Net.gracefulClose serverSocket 500)

    runConnection
      connActions
      operation

