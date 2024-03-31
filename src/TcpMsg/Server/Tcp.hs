{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module TcpMsg.Server.Tcp where

import Control.Concurrent.STM.TVar (newTVarIO)
import qualified Network.Socket as Net
  ( PortNumber,
    Socket,
    accept,
    openSocket, 
    gracefulClose,
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
defaultServerTcpSettings = ServerTcpSettings {port = 44551}

createTcpConnSupplier ::
  ServerTcpSettings ->
  IO (ConnectionSupplier Net.Socket)
createTcpConnSupplier
  serverSettings
  =
    do
      socket <- createServerSocket serverSettings
      return (ConnectionSupplier {
        supplyConn = nextConnection socket,
        finalize = Net.gracefulClose socket 2000
        })

----------------------------------------------------------------------------------------------------------
