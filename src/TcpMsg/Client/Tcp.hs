{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module TcpMsg.Client.Tcp where

import qualified Network.Socket as Net
  ( AddrInfo (addrAddress),
    HostName,
    PortNumber,
    Socket,
    connect,
    openSocket,
  )
import qualified Network.Socket.ByteString as Net
import TcpMsg.Connection (Connection, mkConnection)
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
    mkConnection
      socket
      (Net.recv socket)
      (Net.sendAll socket)
